# Build paths: who calls what

NOTE: All of the line numbers in this file are either wrong or will probably
become wrong in the (potentially near) future. Consider removing them or
replacing them with function name references as appropriate.

Text-only flow charts of how a derivative-maker build is actually driven, and
where the dry-run path stops matching the real one.

Every arrow below was read out of the files on the 'ai' branch. `ci/build` no longer
exists here -- `ee8711e7f` retired it so there is one build path, with
`ci/reproducible-build-twice` driving `dm-build-official` directly.

## The single build spine

All four lanes converge here. Nothing bypasses it.

```
help-steps/dm-build-official
  -> ./derivative-update --update-only         # CI=true only
  -> help-steps/dm-build-official-one          # the orchestrator
       Phase 1  build-steps.d/*_sanity-tests           (per flavor)
       Phase 2  *_prepare-build-machine
                *_cowbuilder-setup
                *_local-dependencies
                *_create-debian-packages   --flavor source
                                           --target iso + the union target set
       Phase 3  ./derivative-maker  <build_args> <skip_shared_args> --flavor F
                  -> for step in ./build-steps.d/* ; do "$step" ; done
                     ...
                     1100_sanity-tests
                     1600_export-libvirt-xml           (raw/qcow2 only)
                     4310_convert-raw-to-iso           (iso only)
                     5200_prepare-release -> dm-prepare-release
                          -> dm-reproducible-buildinfo   # per-image .dm-buildinfo
                     ...
       Phase 4  if flavor_built "$dist_build_source_release_flavor":
                   dm-prepare-release --target source
                   dm-upload-images   --target source
                dm-upload-images   <image targets>
```

Two things that read like gaps and are not:

- Phase 4 runs `dm-prepare-release` for `--target source` ONLY. Per-image
  buildinfo comes from `5200_prepare-release` inside each Phase 3
  `./derivative-maker` run. `./derivative-maker` iterates ALL of
  `build-steps.d/`, and Phase 3's `$skip_shared_args` skips only
  prepare-build-machine, cowbuilder-setup, local-dependencies and
  published-packages -- never 5200.
- The source release is gated on `flavor_built "$dist_build_source_release_flavor"`
  (default `kicksecure-lxqt`), so a flavors_list without it publishes no source.

## 1. CI reproducibility lane

```
.github/workflows/local-reproducible-build-test.yml     # dispatch-only + release tags + weekly
  -> job build (matrix: copy = a, b)          # two SEPARATE runners
       flavor kicksecure-ci-tiny-do-not-use -- the SAME flavor the boot-test
       lane builds, so the two lanes can share one image instead of building
       two
       ci/configure-fork-mirror
       git submodule update --init --recursive
       ci/checkout-fork-submodule-branches
       docker/derivative-maker-docker-run --
         help-steps/signing-key-create
         help-steps/sign-and-tag
         help-steps/dm-build-official --freshness frozen
  -> job compare
       ci/assert-submodule-not-stale packages/kicksecure/developer-meta-files
       ci/assert-submodule-not-stale --all --report-only
       download the two image artifacts
       docker-run -- ci/reproducible-compare
                       -> ci/reproducible-install-deps
                       -> dm-reproducible-compare-artifacts
                          (a vs b, whole-file sha256 for the verdict,
                           best-effort diffoscope to explain a difference)
```

## 2. CI dry-run lane

```
.github/workflows/local-build-dry-run.yml
  -> docker image: docker/derivative-maker-docker-image-ref (the REAL build image)
  -> launch-systemd-container
  -> ci/dry-run
       -> run-parts ci/dry-run.d/
            100_install
            150_signing-key-create
            200_sign-and-tag
            300_run-derivative-maker
              -> help-steps/run-as-user -- builder
                   env flavors_list=kicksecure-lxqt
                       dist_build_multi_target_list=qcow2
                   help-steps/dm-build-official --dry-run true --freshness frozen
              -> assert_produced '*.qcow2.libvirt.xz'
              -> assert_produced '*.dm-buildinfo'
              -> assert provenance is not 'unrecorded'
```

## 3. CI boot-test lane

```
.github/workflows/local-boot-test.yml   # dispatch-only + weekly
  -> job build (matrix: image_kind = qcow2, iso)
       docker/derivative-maker-docker-run --
         signing-key-create && sign-and-tag && dm-build-official --freshness frozen
  -> job boot-test (matrix: kind x firmware x session = 12 legs)
       ci/locate-boot-image
       dist-ai/usr/bin/dm-boot-test
         -> dm-image-boot-tests
              -> dm-image-test  -> dm-qemu   (SMBIOS cmdline injection)
```

## 4. Local developer paths

```
ci/reproducible-build-twice --target T --arch A
  -> help-steps/signing-key-create
  -> help-steps/sign-and-tag          # once, before BOTH builds
  -> build a: CI=true ... help-steps/dm-build-official --freshness frozen
  -> build b: CI=true ... help-steps/dm-build-official --freshness frozen
  -> dm-reproducible-compare-artifacts a/ b/

docker/derivative-maker-docker-run -- <any command>    # bare entry point
```

## Triggering the expensive lanes

The two image-build lanes are dispatch-only. Minutes are free on a public repo,
so this is not about cost -- the free plan allows 20 concurrent jobs ORG-WIDE and
one push fanned out 17 of them.

```
dm-ci-dispatch --workflow local-reproducible-build-test.yml --ref ai
dm-ci-dispatch --workflow local-boot-test.yml --ref ai
```

It runs `dm-preflight` first and refuses a tree whose submodule work is
uncommitted, or whose local ref does not match the remote. `--dry-run` shows what
would be dispatched without starting jobs.

Release tags still build `local-reproducible-build-test.yml` automatically. The cheap lanes -- lint,
dry-run, dist-ai tests, CodeQL, all under a minute -- still run on every PR.

## 5. dry-run YES vs NO

`--dry-run true` sets `build_dry_run=true` in `help-steps/parse-cmd`.

### The build step by step

Seven steps return before doing any work, and three more never run under the
lane's target set. This is the whole point of the table: the lane's exit code
says nothing about them.

```
step                            under dry-run              gate
1100_sanity-tests               runs, minus the ~/.ssh
                                and ~/buildconfig.d checks  :88 -> return 0
1200_prepare-build-machine      runs                        -
1300_cowbuilder-setup           runs (real base built)      :356 gate COMMENTED OUT
1400_local-dependencies         runs (builds one real .deb) -
1600_export-libvirt-xml         runs (qcow2/raw leg)        -
1700_create-vm-text             never runs                  needs --target virtualbox
2100_create-debian-packages     SKIPPED ENTIRELY            :642 -> return 0
3200_create-raw-image           empty 1M image instead of
                                grml-debootstrap            :258 -> create-empty-raw-image
3400_copy-vms-into-raw          SKIPPED ENTIRELY            :79  -> return 0
3500_install-packages           SKIPPED ENTIRELY            :665 -> return 0
4310_convert-raw-to-iso         writes a placeholder ISO
                                (build_dry_run)             :172 -> return 0
4300_run-chroot-scripts-post-d  SKIPPED ENTIRELY            :105 -> return 0
4350_reimage-raw-reproducible   SKIPPED ENTIRELY            :221 -> return 0
4400_convert-raw-to-qcow2       runs (on the 1M raw)        -
4600_create-vbox-vm             never runs                  needs --target virtualbox
4600_export-utm-packages        never runs                  needs dist_build_utm
5100_create-report              SKIPPED ENTIRELY            :96  -> return 0
5200_prepare-release            runs, in full               -
5300_free-build-scratch         never runs                  needs CI=true, see below
```

So no DERIVATIVE package is built, no image root filesystem is constructed, no
package is installed into an image, and the reproducibility reimaging and the
compare report do not run. The cowbuilder base and the one `.deb` that `1400`
builds are real -- they are build-machine setup, not image content. What the lane does exercise end to end is the ORCHESTRATION
(dm-build-official -> dm-build-official-one -> parse-cmd -> variables), the
build-machine and cowbuilder setup, one real `.deb` build in `1400`, the qcow2
conversion, and the whole RELEASE path in `5200` -- mktorrent, sha512sums,
OpenPGP and signify signing with self-verification, and the buildinfo emission.

### The other variables

```
                         dry-run NO            dry-run YES
help-steps/variables
  VMSIZE                 100G   (:745)         1M   (:743)
  rsync_cmd              rsync  (:1068)        echo simulate-only rsync  (:1066)
  rsync_opts             as configured         + --dry-run  (:1089)

help-steps/dm-build-official-one
  ~/.ssh required        yes    (:80)          skipped  (:78)
```

`rsync_cmd` has THREE mock sites, and the first to set it wins:

```
help-steps/pre:134                    CI=true      -> echo simulate-only rsync
help-steps/dm-build-official-one:164  CI=true, or
                                      remote-derivative-packages true
                                                   -> true simulate-only
help-steps/variables:1066             dry-run      -> echo simulate-only rsync
```

### CI=true reaches the build only because the lane passes it explicitly

`help-steps/run-as-user:173` hands off with `sudo --preserve-env=PATH` -- PATH and
nothing else. So the workflow's `docker exec --env CI=true` reaches `ci/dry-run`
but NOT the build, where `help-steps/variables:335` would default `CI` to `false`.

`ci/dry-run.d/300_run-derivative-maker` therefore passes it on the `env` prefix,
which is the supported way to set a variable across `run-as-user`:

```
env CI=true dist_build_target_arch=amd64 flavors_list=... ./help-steps/dm-build-official
```

`dist_build_target_arch=amd64` comes with it: under `CI=true`,
`dm-build-official-one:92` selects arm64, and the runners are amd64.
`local-reproducible-build-test.yml` pins the same value.

The real lane gets `CI` from the container instead:
`docker/derivative-maker-docker-run:369` injects `--env CI=true` and `:394` hands
off with a full `--preserve-env`.

Anything NOT on that `env` prefix still does not cross `run-as-user` -- that is
the trap to remember when adding a variable the build must see.

### Where the dry-run therefore stops being evidence

- The DERIVATIVE package set (`2100`), the image ROOT FILESYSTEM (`3200`/`3500`)
  and the chroot post-scripts (`4300`): not run at all (the table above). The
  cowbuilder base (`1300`) and one real `.deb` (`1400`) DO get built -- those are
  build-machine setup, not the image.
- Anything depending on image CONTENTS: a 1M image holds no filesystem, so the
  boot-test lane cannot be replaced by it.
- Reproducibility: `4350` does not run, and comparing two dry-run images would
  compare two 1M placeholders.
- Any real upload.
