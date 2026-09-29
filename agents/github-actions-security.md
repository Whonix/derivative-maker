# GitHub Actions security - derivative-maker pins

The required patterns themselves (permissions, `persist-credentials: false`,
fork-PR guards, no `${{ }}` into `run:`, SHA pinning, job timeouts, the
"why no actionlint" rationale, and the pin-bump procedure) are maintained in
the AI-maintained `dist-ai` repo:
[`dist-ai:agents/github-actions-security.md`](https://github.com/org-ai-assisted/dist-ai/blob/master/agents/github-actions-security.md).
We do not duplicate them.

For org-wide cross-repo conventions, see
`packages/kicksecure/developer-meta-files/agents/github-actions.md`
([upstream](https://github.com/Kicksecure/developer-meta-files/blob/master/agents/github-actions.md)).

This file holds only THIS repo's live pin state. It stays here because a pin
must be bumped in the same commit as the workflow line it documents, which a
cross-repo file cannot do -- a Dependabot bump here would silently desync it.

## Currently pinned

**`actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2`**
- Source: https://github.com/actions/checkout/releases/tag/v6.0.2
- Verbatim quote: `"de0fac2e4500dabe0009e67214ff5f5447ce83dd"` (under "Assets" / "This commit was created on GitHub.com" indicator on the tag page).
- Verified: 2026-04 by direct fetch of the release / tag page.

**`actions/setup-python@a309ff8b426b58ec0e2a45f0f869d46889d02405  # v6.2.0`**
- Source: https://github.com/actions/setup-python/releases/tag/v6.2.0
- Verbatim quote: `"a309ff8b426b58ec0e2a45f0f869d46889d02405"`.
- Verified: 2026-04.

**`actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a  # v7.0.1`**
- Source: https://github.com/actions/upload-artifact/releases/tag/v7.0.1
- Verbatim quote: `"043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"`.
- Verified: 2026-04.

**`actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c  # v8.0.1`**
- Source: https://github.com/actions/download-artifact/releases/tag/v8.0.1
- Verbatim quote: `"3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c"` (release target commit).
- Verified: 2026-07-14 by git-api tag resolution (`git/ref/tags/v8.0.1`, lightweight tag -> commit).
- Used by `local-reproducible-build-test.yml` (compare job downloads both independent build images). Reads artifacts written by `upload-artifact` v7.

**`actions/cache@27d5ce7f107fe9357f9df03efb73ab90386fccae  # v5.0.5`**
- Source: https://github.com/actions/cache/releases/tag/v5.0.5
- Verbatim quote: `"27d5ce7f107fe9357f9df03efb73ab90386fccae"`.
- Verified: 2026-07-08 by git-api tag resolution; matches the pin in developer-meta-files' apt-install-with-cache action.
- Used by `local-reproducible-build-test.yml` (approx package-cache sidecar). No `restore-keys` on the paired step (G-A-007).

**`github/codeql-action/{init,analyze,upload-sarif}@95e58e9a2cdfd71adc6e0353d5c52f41a045d225  # v4.35.2`**
- Source: https://github.com/github/codeql-action/releases/tag/v4.35.2
- Verbatim quote: `"95e58e9a2cdfd71adc6e0353d5c52f41a045d225"`.
- Verified: 2026-04.
- Note: codeql-action is a monorepo - all three sub-actions share the same SHA.

**`ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a  # v2.4.3`**
- Source: https://github.com/ossf/scorecard-action/releases/tag/v2.4.3
- Verbatim quote: `"4eaacf0543bb3f2c246792bd56e8cdeffafb205a"`.
- Verified: 2026-04.

**`google/clusterfuzzlite/actions/{build_fuzzers,run_fuzzers}@884713a6c30a92e5e8544c39945cd7cb630abcd1  # v1`**
- Source: https://github.com/google/clusterfuzzlite/tree/v1 (HEAD of the v1 branch; ClusterFuzzLite does not cut numbered releases).
- Verbatim quote: `"884713a6c30a92e5e8544c39945cd7cb630abcd1"` (HEAD of v1 at time of pin).
- Verified: 2026-04.
- Note: there is no immutable release tag; we re-verify HEAD of v1 manually before each bump.

## Container image digests (Docker Hub)

Workflow `image:` lines must also be pinned to a content digest. Tags
are mutable.

**`debian:trixie@sha256:35b8ff74ead4880f22090b617372daff0ccae742eb5674455d542bef71ef1999`** (2026-04-27)
- Source: Docker Hub registry API. Re-pin with:
  ```
  curl -sS -I \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    -H "Authorization: Bearer $(curl -sS 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull' | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')" \
    'https://index.docker.io/v2/library/debian/manifests/trixie' \
    | grep -i 'docker-content-digest:'
  ```
- Multi-arch index digest. Used by both `local-lint.yml` and
  `local-build-dry-run.yml`; bump both call sites in lockstep.
