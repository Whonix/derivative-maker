# git_sanity_test: tag verification security analysis

Threat model, spoofability analysis, and design rationale for the
tag-state check in `help-steps/git_sanity_test`.

For design/architecture docs, see `agents/git_sanity_test_design.md`.

## Summary

Two independent cryptographic checks gate every derivative-maker build:

1. **Commit authentication** via `sq-git log` against `openpgp-policy.toml`.
   Primary trust anchor. Verifies the commit chain.
2. **Tag authentication** via `sqop verify` against certs extracted from
   `openpgp-policy.toml`. Secondary trust anchor. Verifies the tag
   object signature cryptographically.

## Why tags matter (rollback attack prevention)

Tags bind version numbers to commits. If an attacker can create tags
that end-users trust, the attacker can direct users to build artifacts
from any commit -- enabling **rollback attacks** on users who build
Kicksecure or Whonix from source. Signing tags ensures that only
trusted developers can assign version numbers to commits.

## sq-git does not authenticate tags

Proven by experiment on Debian trixie `sequoia-git 0.4.0-4+b5`
(Apr 2026):

```
$ git tag del                             # example 1: lightweight
$ git tag del -m .                        # example 2: annotated, unsigned
$ git tag -v del
# example 1: error: del: cannot verify a non-tag object of type commit.
# example 2: error: no signature found.

$ sq-git log --trust-root HEAD del        # on either example
Verified that there is an authenticated path from the trust root
bf034a8f... to bf034a8f...
```

`sq-git log` resolves any tag name to the commit it points at and
authenticates the commit chain. It ignores the tag object entirely.
A lightweight tag or unsigned annotated tag silently "passes" because
the target commit is signed. This is why separate tag verification
exists.

### sign_tag in the policy spec

`openpgp-policy.toml` defines `sign_tag = true` as an authorization
capability. The "release manager" role is "authorized to sign tags
and archives." But sq-git has no `sq-git verify-tag` command -- it
only implements commit authentication. The `sign_tag` field exists
in the spec but sq-git does not consume it for verification today.

This gap is why `classify_tag()` extracts certs with `sign_tag=true`
from the policy file and uses `sqop verify` as a workaround.

A feature request to sequoia-pgp/sequoia-git for native tag
authentication would eliminate this workaround. See:
- https://gitlab.com/sequoia-pgp/sequoia-git/-/work_items/15
- https://sequoia-pgp.gitlab.io/sequoia-git/

## Signing format policy

Only **OpenPGP (PGP)** signatures are supported for tag signing.

- **SSH signatures** (`-----BEGIN SSH SIGNATURE-----`): NOT supported
  by project policy. `sqop` only understands OpenPGP, so SSH-signed
  tags would fail verification naturally. No special code handling needed.

- **PGP MESSAGE** (`-----BEGIN PGP MESSAGE-----`): NOT accepted.
  Git tag signing produces `-----BEGIN PGP SIGNATURE-----` (detached
  binary signature in ASCII armor), never PGP MESSAGE format.

## Current implementation

### Tag verification flow

1. `git cat-file -t` classifies as lightweight (commit) vs annotated (tag)
2. Fast-path substring check for `-----BEGIN PGP SIGNATURE-----`
3. `extract-openpgp-policy-trusted-certs` (Python/tomllib) extracts
   PGP certs for users with `sign_tag = true` from the policy file
4. `split_tag()` splits tag body into payload + signature (scans
   backwards from end for BEGIN marker to reduce spoofing risk)
5. `sqop verify tag-sig cert < tag-text` against each cert
6. If any cert verifies -> annotated-signed (return 0)
7. If none verify -> annotated-unsigned (return 2)

### Why sqop (Stateless OpenPGP)?

`sqop` is the right tool because:
- It's stateless: takes cert file + signature file + payload on stdin.
  No keyring management.
- It's part of the OpenPGP standard
  (RFC 4880 / draft-ietf-openpgp-crypto-refresh).
- Available in Debian trixie as package `sqop`.
- Unlike `sq verify` (which needs sq's cert store), `sqop verify`
  accepts certs as file arguments directly.

### Why not git verify-tag or sq verify?

Both require access to a keyring / cert store:
- `git verify-tag` uses `gpg.openpgp.program` -> `sq-git-wrapper`
  -> the wrapper's verify mode only has access to `$DEBEMAIL`
  (packaging email, not the signer's email) and can't use
  `openpgp-policy.toml` natively.
- `sq verify --signer-email` needs the key in sq's cert store.

`sqop verify` avoids both problems by accepting cert files directly.

### Why not git's gpg.openpgp.program (sq-git-wrapper) for tags?

git's `gpg.openpgp.program` interface passes only `--verify <sigfile> -`
(raw signature data + payload on stdin). It does NOT pass the commit
or tag ref, so:
- The wrapper can't call `sq-git log` (needs a ref)
- The wrapper can only call `sq verify` (needs explicit signer)
- Policy-based verification is impossible through this interface

This is why `merge.verifySignatures=true` was dropped from
`derivative-update`'s submodule update command.

## Threat model summary

| Actor | Capability | Caught by |
|---|---|---|
| Honest developer forgets `-s` | unsigned annotated tag | classify_tag (fast-path: no PGP SIGNATURE marker) |
| Attacker with tag push access, no signing key | creates spoofed/unsigned tag | sqop verify (signature fails) |
| Attacker with tag push access, no signing key | creates commit | sq-git log (commit not signed by authorized signer) |
| Attacker with signing key | anything | nothing -- trusted by policy |

## Tag policy: --allow-untagged semantics

`--allow-untagged` covers ONE case: "no tag at HEAD" (building from a
non-release commit). All other tag-state violations are **unconditional
errors** regardless of `--allow-untagged`:

| State | --allow-untagged=false | --allow-untagged=true |
|---|---|---|
| no tag | die | INFO, continue |
| lightweight | die | **die** |
| annotated unsigned | die | **die** |
| annotated, untrusted signer | die | **die** |
| multiple tags | die | **die** |
| annotated signed by trusted dev | continue | continue |

`--mode ref --ref-type tag` does NOT honour `--allow-untagged` at all:
the caller explicitly named a ref and declared its type, so the
declaration is enforced strictly.

## Ref-resolution hygiene

A separate class of attack from tag content forgery: **ref name
collisions**. Git resolves an unqualified `<name>` against multiple
namespaces (`refs/heads/`, `refs/tags/`, `refs/remotes/<remote>/`,
...) and may resolve ambiguously to an attacker-pushable namespace.

### Tag shadowing a remote-tracking branch

Reproduced on Debian trixie git 2.47:

```
$ git tag 'origin/master' HEAD          # adversary creates this
$ git switch --detach origin/master
warning: refname 'origin/master' is ambiguous.
HEAD is now at <TAG-COMMIT>             # tag wins, NOT origin/master
```

Same attack pattern applies to `git checkout`, `git reset`, and any
ref-consuming command. Mitigation: pass the fully qualified refname
when the type is statically known.

| Caller knows | Use |
|---|---|
| It is a tag | `refs/tags/<name>` |
| It is a local branch | `refs/heads/<name>` |
| It is a remote-tracking branch | `refs/remotes/<remote>/<name>` |
| It is a commit object | peel: `<expr>^{commit}` |

There is an exception to the above rule, which is when using `git switch`
without `--detach`. In this instance the bare branch name must be specified
WITHOUT `refs/heads/` in front of it. Specifying `refs/heads/` here results in
`git switch` erroring out, and not specifying it is safe here (see below).

### Prefer `git switch --detach` over `git checkout`

For HEAD-changing operations on a ref:

- `git switch --detach -- <ref>` accepts `--` as end-of-options;
  combined with a fully qualified refname, both flag injection and
  namespace collision are closed.
- `git checkout -- <ref>` treats `--` as a **pathspec separator**;
  end-of-options is therefore not available, leaving leading-`-`
  arg injection unmitigated unless the caller validates first.

`git switch` without `--detach` only accepts a local branch name
and refuses commits, tags, and remote-tracking refs. That stricter
default is itself a useful guard for branch-only call sites.

## Future directions

- Sequoia-git has added `sq-git verify-tag` using the policy file,
  so we will eventually be able to replace the
  `extract-openpgp-policy-trusted-certs` + `split_tag` + `sqop verify`
  workaround with a single sq-git call. This will have to wait until Debian
  Forky, as the feature does not exist in Debian Trixie's sq-git.
