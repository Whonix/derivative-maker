# git_sanity_test: design notes

Detailed design documentation for `help-steps/git_sanity_test`.
For tag verification security analysis, see `agents/git_sanity_test_security.md`.

## What this script does

`help-steps/git_sanity_test` is the single entry point for all git
verification in derivative-maker. It replaces the old sourced-functions
approach (`signed_by_fingerprint`, `verify_ref`, `git_sanity_test_main`
etc. that used to live in a sourceable `help-steps/git_sanity_test`).
Now it's an executable script with explicit `--mode` arguments.

### Modes

| Mode | Purpose |
|---|---|
| `--mode all --context LABEL` | Full check: working-tree on cwd + all submodules. Default when no --mode given. |
| `--mode working-tree --context LABEL` | Verify cwd's git repo: commit authentication, tag policy, uncommitted check. |
| `--mode ref --ref REF --ref-type {tag\|commit}` | Authenticate a specific ref's target commit. For tags: enforce refs/tags/... + classify_tag. |
| `--mode submodules` | Iterate all submodules via `git submodule foreach --recursive`, run working-tree on each. |

### Callers

- `derivative-update` (initial all-check, tag verification, submodule verification, post-merge re-verification)
- `build-steps.d/1100_sanity-tests`

### Standalone use

Developers can run `./help-steps/git_sanity_test` directly from a
clone. If env vars aren't set, the script sources `pre`, `colors`,
`variables` to populate them. Detection: checks `dist_build_one_parsed`
(the flag `variables` sets after running `parse-cmd`).

## Trust model

### Commit authentication (primary cryptographic gate)

`sq-git log --policy-file P --trust-root ROOT -- TARGET` walks the
commit chain from ROOT to TARGET, validating each commit signature
against `openpgp-policy.toml`. This is commit-centric: tags don't
enter into it.

**IMPORTANT**: Always pass `--policy-file` explicitly. Without it,
`sq-git log --trust-root HEAD -- HEAD` is unsafe: when trust root and
target are the same commit, sq-git may assume authentication without
verifying the signature. With an explicit `--policy-file`, sq-git
verifies even the trust root's commit signature.

### Tag authentication (secondary cryptographic gate)

Tag signatures are verified separately from commit signatures, using
`sqop verify` (Stateless OpenPGP) against certificates extracted from
`openpgp-policy.toml`. See the "Tag verification flow" section below
and `agents/git_sanity_test_security.md` for the full analysis.

### TOFU (trust-on-first-use)

CI and non-redistributable builds set `sq_git_trust_root="HEAD"`.
sq-git log's chain is a single commit and authentication is
definitional. On first run, the operator must manually verify:
https://www.kicksecure.com/wiki/Dev/Build_Documentation/images

### Redistributable builds

Pin `sq_git_trust_root` to a specific historical commit hash
(set in `help-steps/variables`). sq-git log walks every commit from
that anchor to HEAD. Strictly stronger than TOFU.

### Submodule trust

`--mode submodules` forces `sq_git_trust_root=HEAD` per submodule
(TOFU). The real integrity guarantee comes from the superproject:
the parent repo pins each submodule's gitlink (commit SHA) and the
parent repo is already authenticated. Anyone tampering with a
submodule commit without also tampering with the superproject commit
gets caught at the superproject level.

Per project policy, all submodules have tags. Tag verification runs
on submodules the same as the main repo.

## Tag policy (strict)

Valid tag states:
- (A) no tag at HEAD -- allowed under `--allow-untagged`
- (B) exactly one annotated signed tag at HEAD

Everything else is an **unconditional error**, regardless of
`--allow-untagged`:
- lightweight tag at HEAD
- annotated but unsigned tag at HEAD
- annotated tag signed by untrusted key
- multiple tags at HEAD

`--allow-untagged` is a **narrow** escape hatch covering case A only.
It means "no tag here is OK" not "broken tag state is OK".

`--mode ref --ref-type tag` does NOT honour `--allow-untagged`: when
the caller explicitly names a ref and declares its type, the
declaration is enforced strictly.

## Tag verification flow

1. **Enumerate** tags at HEAD via `git for-each-ref --points-at=HEAD
   --format='%(refname)' refs/tags`. Uses full refnames (not short)
   to avoid branch/tag ambiguity.

2. **Classify** each tag via `classify_tag()`:
   - `git cat-file -t` -> lightweight (commit) vs annotated (tag)
   - Fast-path substring check for `-----BEGIN PGP SIGNATURE-----`
     in tag body (only PGP SIGNATURE; not PGP MESSAGE or SSH)
   - If signature markers present: extract certs and verify

3. **Extract trusted certs** via `extract-openpgp-policy-trusted-certs`
   (Python script using `tomllib`). Parses `openpgp-policy.toml` and
   writes out PGP certificates for users with `sign_tag = true`.

4. **Split tag body** via `split_tag()` into tag-text and tag-sig.
   Scans backwards from end of body for `-----BEGIN PGP SIGNATURE-----`
   to reduce risk of signature markers in the tag message.

5. **Verify** via `sqop verify tag-sig cert < tag-text` for each
   extracted cert. If any cert verifies, the tag is accepted.

### Dependencies

- `sq-git` (package `sequoia-git`) -- commit authentication
- `sqop` (package `sqop`) -- tag signature verification
- `python3` with `tomllib` (stdlib in 3.11+) -- TOML policy parsing

All three must be installed. `sqop` is checked via `command -v sqop`
in the middle of `classify_tag()`.

### Temp directory

Tag verification creates `${binary_build_folder_dist}/verify_tag_temp`
which is `rm -rf`'d and recreated on each run. This is NOT safe for
parallel execution of derivative-maker.

## Why merge.verifySignatures was dropped from derivative-update

The old code used:
```
"${git_verify_command_wrapper[@]}" -c merge.verifySignatures=true submodule update --init --recursive --merge
```

Where `git_verify_command_wrapper` set `gpg.openpgp.program` to
`sq-git-wrapper`. This is fundamentally broken for policy-based
verification because:

1. git's gpg.openpgp.program interface passes only raw signature data
   and payload (`--verify <sigfile> -`). It does NOT pass the commit
   hash.
2. `sq-git log` needs a commit ref to walk the chain. It can't work
   from raw signature data.
3. The wrapper can't call `sq-git log` and can only call `sq verify`,
   which needs explicit signer specification.

Replaced with: plain `git submodule update` followed by
`git_sanity_test --mode submodules` which calls `sq-git log` directly
per submodule.

The old `merge.verifySignatures` command is kept commented-out in
`derivative-update` as a reference.

## Why git submodule foreach uses a separate bash script

`git submodule foreach` runs its command under `/bin/sh`, not bash.
This means:
- No bash arrays, no `[[ ]]`, no `set -o pipefail`
- No bash functions from the parent process
- Environment variables ARE inherited

The script re-invokes itself via `bash "$MYDIR/git_sanity_test"` per
submodule to get proper bash with strict options and shared logic.

`$MYDIR` (computed from `$BASH_SOURCE[0]` at startup) is used instead
of `$toplevel` because `$toplevel` points to the git superproject root
of the current repo, which may not be the derivative-maker repo if
running from a nested context. `$MYDIR` always points at the script's
own directory.

`$MYDIR` is exported so the foreach POSIX subshell can expand it.

## Standalone bootstrap: why it's conditional

The bootstrap may have unexpected side effects in the future, and
changing environment variables that are set by a parent process may be
unexpected. Therefore, we do not re-source `help-steps/variables`
multiple times. (`help-steps/variables` also does
`cd "$source_code_folder_dist"`, but this would not be a problem here
because `git_sanity_test` saves its old cwd and restores it with
`cd -- "$orig_pwd"` after sourcing `help-steps/variables`.)

Detection: `dist_build_one_parsed` flag (set by `variables` after
running `parse-cmd`). If "true", bootstrap is skipped and inherited
env vars are used.

Unrecognized args are forwarded to `parse-cmd` via `variables` in
the standalone path only. In build context, extra forwarded args
cause a hard error.

## Argument forwarding details

Script-specific: `--mode`, `--context`, `--ref`, `--ref-type`, `--help`
Everything else: forwarded one token at a time to `parse-cmd`.

One-token-at-a-time forwarding (not pairs) is important because
parse-cmd knows its own token counts. Greedy pair forwarding would
swallow subsequent tokens for bare flags like `--debug`.

`dist_build_source_run="true"` tells parse-cmd to accept zero or
unknown args without erroring.

## sq-git version

Targets sequoia-git 0.4.0+ (Debian trixie `sequoia-git` package).
No workarounds for older versions by design.

sequoia-git issue #37 (`sq-git log --trust-root=HEAD HEAD` errored
with "The given range contains no commits") was fixed in 2023.
Verified locally on Debian trixie sequoia-git 0.4.0-4+b5 (Apr 2026):
```
$ sq-git log --trust-root HEAD HEAD
Verified that there is an authenticated path from the trust root
bf034a8f... to bf034a8f...
```

## sq-git and tag authentication: gap analysis

The `openpgp-policy.toml` spec defines `sign_tag = true` as an
authorization capability. The "release manager" role is described as
"authorized to sign tags and archives". But sq-git currently only
implements **commit** authentication (`sq-git log`). There is no
`sq-git verify-tag` or equivalent.

This is why `classify_tag()` uses `sqop verify` as a workaround:
extract the trusted certs from the policy file ourselves, split the
tag body, and verify the signature with `sqop`.

If sq-git supported native tag authentication using the existing
`sign_tag` policy field, it would eliminate the need for this
workaround.

## Errexit suppression in functions called from || or &&

Bash suppresses both `set -e` (errexit) and the ERR trap for ALL
commands inside a function when that function is called from within
a `||` or `&&` list. For example:

```
classify_tag "${tags_at_head[0]}" "${context}" || cls=$?
```

Every command inside `classify_tag` -- `mkdir`, `chmod`, `safe-rm`,
`extract-openpgp-policy-trusted-certs`, `split_tag`, etc. -- runs
with errexit disabled and the ERR trap suppressed. A failing
command returns non-zero but execution continues to the next line
as if nothing happened.

This is why `help-steps/pre` ending with `set +e` is NOT the sole
cause of the problem. Even if `pre` kept `set -e`, the `|| cls=$?`
call pattern would still suppress it inside the function.

### Guard strategy

Every external command and subprocess call inside a function that
may be called from `||`/`&&` context MUST have an explicit guard:

- Critical commands: `|| die "message"` (die calls exit 1, which
  always exits regardless of errexit state)
- Cleanup commands that should not abort: `|| true`
- Commands already inside `if !` or `if` conditions: already
  guarded (bash only suppresses errexit, not the if-condition
  check itself)

Pre-flight `command -v` checks at the top of the script catch
missing binaries early with clear error messages, before we enter
any suppressed context.

### Fail-safe analysis

Even WITHOUT the explicit guards, all failure modes in
`classify_tag` are fail-safe: silent failures cause the function to
return 2 (annotated-unsigned / untrusted), which callers treat as a
hard error. No silent failure path leads to false acceptance. The
guards are added for clear error messages and defense in depth, not
because the old code could accept bad tags.

## dist_build_current_git_head

Set unconditionally by `help-steps/variables` from `git rev-parse HEAD`.
Used by `derivative-update`'s `abort_update()` as the recovery commit.
Does NOT allow caller override (security: prevents env var injection
from steering rollback to an attacker-chosen commit).

## Parallel execution

Not supported. Only one instance of derivative-maker may run at a
time. The tag verification temp directory
(`binary_build_folder_dist/verify_tag_temp`) is cleaned and recreated
on each run; concurrent runs would conflict.

## CI status

CI is only functional in `Whonix/derivative-maker` and
`Kicksecure/derivative-maker`. The `assisted-by-ai/derivative-maker`
fork's CI is broken due to missing DigitalOcean infrastructure
secrets. CI failures on PRs in `assisted-by-ai` are expected and not
caused by code changes.
