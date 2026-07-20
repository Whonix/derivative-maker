# Verifying a reproducible image build

You rebuilt an official image with `--freshness frozen` and the whole-image
hash does **not** match ours. This page explains how to find out *which files*
differ without downloading our multi-GB image, and why `diffoscope` alone is not
the right first tool.

> **Status.** The manifest tool (`ci/reproducible-manifest`) and the local
> build-twice check (`ci/reproducible-build-twice`) work today. Publishing a
> **signed manifest sidecar next to each official image** -- the piece that lets
> an end user compare without downloading the image (steps 1-2 below) -- is the
> proposed next step and is not shipped yet. Until it is, you can still localize
> a difference locally by generating a manifest from your rebuild and comparing
> it against a manifest you generate from a copy of our image.

## Why not just run diffoscope?

`diffoscope` compares **two** inputs and renders their differences. It cannot
analyze a single image in isolation, so a "diffoscope report of our image on its
own" does not exist. To use it you would have to download our full image and run
diffoscope against your local one, which:

- transfers ~1-1.4 GB you may not need, and
- can exhaust RAM (diffoscope on two ~1.4 GB ISOs OOMs an 8 GB host).

`diffoscope` is the right tool for the **last** step, once a mismatch has been
narrowed to a specific file.

## The cheap first step: compare manifests

A **manifest** is a per-file fingerprint of an image: one `sha256  path` line for
every regular file inside it, sorted by path. It is a few MB regardless of image
size, so you can fetch ours and compare locally without downloading the image.

The tool is `ci/reproducible-manifest` (already in this repo):

```
ci/reproducible-manifest generate --image FILE --output MANIFEST [--deep]
ci/reproducible-manifest compare  --a MANIFEST --b MANIFEST [--output REPORT]
```

- `generate` mounts the image read-only and lists every regular file. `--deep`
  also descends into a `filesystem.squashfs` member (live ISO rootfs), so
  differences inside the squashfs are localized too.
- `compare` prints files only in A, only in B, and same-path-different-hash,
  then exits `0` identical / `1` any difference / `2` usage error.

## Verification flow on a hash mismatch

1. **Fetch only our small signed manifest** (`<image>.manifest` + `<image>.manifest.asc`)
   from the same download location as the image. It is a sidecar, so you do not
   pull the image itself.

2. **Verify the manifest's OpenPGP signature** against the Kicksecure signing key
   (the same key that signs the image `.sha512sums`). A manifest you cannot
   verify tells you nothing.

3. **Generate the manifest of your local rebuild:**

   ```
   ci/reproducible-manifest generate --image <your-rebuilt-image> --output local.manifest --deep
   ```

4. **Compare the two manifests:**

   ```
   ci/reproducible-manifest compare --a <ours>.manifest --b local.manifest
   ```

   This prints exactly which in-image files diverged. For a truly reproducible
   build the list is empty (exit `0`).

5. **Explain a specific difference (optional):** once a file is localized, run
   `diffoscope` on just that pair (extract the one file from each image) for a
   byte-level explanation. This is bounded and cheap because it is one file, not
   two whole images.

## Reporting a genuine difference

If the manifests differ and the diff is not one of the known
expected-to-differ entries, it is a reproducibility bug worth reporting: include
the `compare` output (the differing paths) and your build's recorded commit
(from the signed `<image>.dm-buildinfo` sidecar, which records the inputs needed
to reproduce the build). That is enough for a maintainer to reproduce and
localize without your image.

## See also

- `ci/reproducible-manifest` -- the manifest generate/compare tool.
- `ci/reproducible-build-twice` -- build an image twice locally and diff it
  (the developer-side reproducibility check).
- `.github/workflows/local-reproducible.yml` -- the CI lane that builds twice on
  two independent runners and compares.
