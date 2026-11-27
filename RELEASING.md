# Releasing Networkex

The maintainer checklist for publishing a version on Hex with precompiled NIFs. `X.Y.Z` stands
for the version being released.

## How the pieces fit

- `Networkex.Native` (through `rustler_precompiled`) downloads the NIF for the user's platform
  from the GitHub release `vX.Y.Z` and verifies it against
  `checksum-Elixir.Networkex.Native.exs`, a file that ships in the Hex package.
- `.github/workflows/release.yml` runs when a `v*` tag is pushed. It builds the NIF for six
  targets and NIF versions 2.16 and 2.17 (12 artifacts), checks that the Linux glibc builds need
  glibc 2.28 at most, and attaches them to the tag's release with `LICENSE`, `NOTICE`,
  `THIRD_PARTY_NOTICES.md`, `PSF-2.0.txt` and `BSD-3-Clause-spaghetti.txt` (both from
  `LICENSES/`, the texts for the CPython and spaghetti code in the NIFs), 17 assets in all.
  Release assets have no directories, so the two texts are attached under their file names; the
  release notes the workflow writes say that they are the `LICENSES/` files that NOTICE and
  `THIRD_PARTY_NOTICES.md` refer to. The release job runs only for a pushed tag and only when
  every build succeeded; a manual run of the workflow only builds. It checks that the artifacts
  are exactly the 12 NIFs of the tag's version, creates the release as a draft, uploads the
  assets and then publishes it, so it also works with immutable releases. It never replaces the
  assets of a published release and never uploads into a published release: it fails instead.
  It also stops when it cannot read the release (any `gh` failure other than "release not
  found"), rather than create a second draft, and runs once per tag at a time.
- The checksum file is generated from those published artifacts. It is **not committed** (it is
  git-ignored); `rustler_precompiled`'s precompilation guide notes that it does not need to be
  tracked. Here leaving it out is required: `Networkex.Native` builds the NIF from source
  whenever the file is absent, so a checkout (CI, contributors) always tests the source build,
  and a committed file would make the next version look for release artifacts that do not exist
  yet.
- `mix hex.publish` is an alias in `mix.exs` that checks the checksum file before running Hex's
  task with the same arguments. It refuses to publish when the file is missing, when the package
  file list does not include it (the list is computed when `mix.exs` loads, so a file downloaded
  earlier in the same `mix` command is left out), or when it does not hold exactly the 12
  checksums of the version being published (a file left over from another release). Without the
  file, every user would have to build the NIF from source, and `:rustler` is an optional
  dependency, so that build fails for most of them. `mix hex.publish docs`,
  `mix hex.publish --revert VERSION` and pre-release versions (which always build from source)
  are not checked, and `mix hex.build` is not guarded, so CI can check the package. The guard
  reads the arguments with the switches of Hex's own task (copied from Hex 2.5.3; compare them
  after a Hex upgrade that adds one), and checks arguments Hex would refuse as a package
  publish.

## Requirements

- Owner rights on the `networkex` Hex package, and permission to push tags.
- Rust 1.91 or newer (the workspace `rust-version`). Until the checksum file exists, the project
  builds its NIF from source, including when `mix rustler_precompiled.download` compiles it.

## Checklist

1. **Prepare the version in a pull request.**
   - Set `@version` in `mix.exs`.
   - In `CHANGELOG.md`, replace `Unreleased` with the release date and review the entries.
   - Update any version shown in `README.md`.
   - The six notebooks (`notebooks/*.livemd`, `notebooks/es/*.livemd`) install
     `{:networkex, "~> 0.3"}` with `Mix.install` and, outside the repository, download their
     data from the GitHub tag of the installed version. For a new minor version, raise that pin
     in all six (`"~> 0.4"` for 0.4.0): `"~> 0.3"` also accepts the older 0.3 releases, which
     lack what the new notebooks may use. "Run in Livebook" from HexDocs works only once the tag
     exists and the repository is public.
   - If `Cargo.lock` changed since the last release, regenerate the crate table of
     `THIRD_PARTY_NOTICES.md` as its section "Regenerating this list" describes: the published
     NIFs must ship the notices of the crates they link.
   - If code derived from spaghetti or CPython was added or changed, update section (a) of
     `THIRD_PARTY_NOTICES.md` (the derived functions carry a `Derived from` or `Ported from`
     comment).
   - Run `mix test`, `cargo test --workspace` and `mix hex.build --unpack --output
     /tmp/networkex-package` and review the package files.
   - Merge once CI is green.

2. **Tag the merged commit.** The tag must be `v` followed by `@version`; the release workflow
   fails otherwise.

   ```sh
   git switch main && git pull --ff-only
   git tag -a vX.Y.Z -m "Networkex X.Y.Z"
   git push origin vX.Y.Z
   ```

3. **Wait for the release workflow.** All 12 build jobs and "Attach NIFs to the release" must be
   green, and the published `vX.Y.Z` release must list 12 `.tar.gz` assets plus the 5 license
   files.
   - A transient failure: re-run the failed jobs. While the release is still a draft, a re-run
     replaces the draft's assets; once it is published, the release job refuses to touch it.
   - A release published without assets (for example created by hand before the workflow ran):
     the release job refuses to upload into it. Delete the release but keep the tag
     (`gh release delete vX.Y.Z`), or convert it to a draft, and re-run the release job.
   - A failure that needs a code change, and only before anything is on Hex: delete the release
     and the tag, locally too, fix it through a pull request, and tag again:

     ```sh
     gh release delete vX.Y.Z --cleanup-tag   # the release and the remote tag
     git tag -d vX.Y.Z                         # the local tag, or the next push sends it back
     ```

   - Never move a tag, and never re-run the release workflow for a tag, once the version's
     checksums are on Hex: the checksum file pins the bytes of every published artifact, and a
     rebuild does not reproduce them.
   - If a draft release is left over (a run failed after creating it), the next run of the
     release job reuses it. Artifacts of a draft cannot be downloaded by users or by the next
     step.

4. **Generate the checksum file from the tagged commit.**

   ```sh
   git switch --detach vX.Y.Z
   git status --short   # must print nothing
   mix deps.get
   mix rustler_precompiled.download Networkex.Native --all --print
   ```

   The task writes `checksum-Elixir.Networkex.Native.exs` to the project root and prints one
   SHA-256 per artifact; compare them with the `SHA256:` lines of the build jobs' logs. Do not
   commit the file. Check, in a new command, that the package now contains it:

   ```sh
   mix hex.build --unpack --output /tmp/networkex-package
   ls /tmp/networkex-package
   ```

5. **Publish.** Run it as a command of its own, not chained after the download with `mix do`:
   the package file list is computed when `mix.exs` loads, and the guard refuses a checksum file
   the list does not include. Review the file list Hex prints (it must include the checksum
   file) and confirm. This publishes the package and its documentation.

   ```sh
   mix hex.publish
   ```

   Then delete the checksum file and go back to `main`:

   ```sh
   rm checksum-Elixir.Networkex.Native.exs
   git switch main
   ```

   The file is git-ignored, so nothing reminds you of it. Left in place it makes a fresh local
   build download the precompiled NIF instead of building it from source (and fail once
   `@version` moves on, as that release does not exist yet), and it is stale for the next
   version (the guard refuses it then).

6. **Verify the install from Hex** in a scratch project, outside this repository.

   ```sh
   mix new networkex_smoke && cd networkex_smoke
   # In mix.exs: defp deps, do: [{:networkex, "== X.Y.Z"}]
   mix deps.get
   mix compile   # downloads the precompiled NIF; must not need Rust
   mix run -e 'IO.inspect(Networkex.Network.new([[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}]]).arc_lengths)'
   # prints [1.0, 2.0, 2.0]
   ```

   Then check the source build in the same project:

   ```sh
   # In mix.exs, add {:rustler, "~> 0.38", runtime: false} to the deps
   mix deps.get
   NETWORKEX_BUILD=1 mix deps.compile networkex --force   # compiles the crate with cargo
   NETWORKEX_BUILD=1 mix run -e 'IO.inspect(Networkex.Network.new([[{0, 0}, {1, 0}]]).arc_lengths)'
   # prints [1.0]
   ```

   Repeat the first check on another operating system when possible: CI only tests source builds.

7. **Open the next version.** Add an `Unreleased` section to `CHANGELOG.md` in the next pull
   request.

## First release

The release workflow cannot run before the first tag, so the first release (0.3.0) also checks
what CI could not:

- [ ] The release went from draft to published, and it lists 17 assets: the 12 tarballs named
      `libnetworkex_native-vX.Y.Z-nif-{2.16,2.17}-TARGET.so.tar.gz` (Windows:
      `networkex_native-vX.Y.Z-nif-{2.16,2.17}-x86_64-pc-windows-msvc.dll.tar.gz`), `LICENSE`,
      `NOTICE`, `THIRD_PARTY_NOTICES.md`, `PSF-2.0.txt` and `BSD-3-Clause-spaghetti.txt`.
- [ ] In the four Linux glibc build jobs, the step "Check the glibc the NIF needs" printed a
      version of 2.28 or lower (about 2.18 is expected; see "The glibc floor").
- [ ] In the two `x86_64-unknown-linux-gnu` build logs, the link step succeeded without a
      `-fuse-ld=lld` error (see "The glibc floor" for the fix if it did not).
- [ ] `mix rustler_precompiled.download Networkex.Native --all --print` fetched all 12
      artifacts and the guard accepted the checksum file.
- [ ] The install from Hex (step 6) works in a scratch project without Rust, and again with
      `NETWORKEX_BUILD=1` and `:rustler`; when possible also on macOS or Windows, and on Linux
      with glibc 2.28 (for example a Debian 10 container).
- [ ] The checksum file was deleted after publishing.
- [ ] Private vulnerability reporting is enabled in the repository settings (the **Private
      vulnerability reporting** option of the security settings), before the repository is
      public: `SECURITY.md`, `CODE_OF_CONDUCT.md` and the issue template configuration send
      reports to its form.

## Building from source: `NETWORKEX_BUILD`

Users build the NIF from source when they set `NETWORKEX_BUILD=1` (or `true`) or
`config :rustler_precompiled, :force_build, networkex: true`, when the version is a pre-release
(`X.Y.Z-rc.N`), or when the package has no checksum file (`Networkex.Native.Build` decides).
`rustler_precompiled` reads that config only when the NIF module passes no `force_build:` option,
and `Networkex.Native` passes one, so Networkex reads the config itself. A source build needs:

- Rust 1.91 or newer;
- `{:rustler, "~> 0.38", runtime: false}` in the application's own dependencies (Networkex
  declares it optional).

The variable is read when Networkex compiles, so after changing it run
`mix deps.compile networkex --force`. It is the way out for platforms without a precompiled NIF
(for example `aarch64-unknown-linux-musl` or FreeBSD), or for a Linux system with a glibc older
than 2.28 where the precompiled NIF does not load.

## The glibc floor

Both Linux glibc targets build with `cross` in its Ubuntu 16.04 images (glibc 2.23), so the
libraries only need old glibc symbol versions. The release workflow prints the newest
`GLIBC_` version each one needs and fails above 2.28, the floor that README.md promises; a
local `cross` build of `x86_64-unknown-linux-gnu` needed `GLIBC_2.18`. Raise the ceiling only on
purpose, together with README.md.

Since Rust 1.90, rustc links `x86_64-unknown-linux-gnu` with `rust-lld` by passing
`-fuse-ld=lld` to `cc`. The GCC 5.4 of the `cross` image rejects that option, and rustc then
links again without it, with the system's GNU `ld`; it says so only at log level info
("The linker driver does not support `-fuse-ld=lld`. Retrying without it."). This was checked
locally with `cross` 0.2.5 and rustc 1.100, so the workflow sets no linker option. If a future
rustc stops retrying, the build fails at link time with
`unrecognized command line option '-fuse-ld=lld'`; the fix is then
`-Clinker-features=-lld` for that target only (for example through
`CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS`, passed into the `cross` container), never a
workflow-wide `RUSTFLAGS`, which would replace the macOS and musl flags of `.cargo/config.toml`.

## Targets and NIF versions

The precompiled NIFs cover `aarch64-apple-darwin`, `x86_64-apple-darwin`,
`aarch64-unknown-linux-gnu`, `x86_64-unknown-linux-gnu`, `x86_64-unknown-linux-musl` and
`x86_64-pc-windows-msvc`, each for NIF 2.16 (OTP 24 and 25; Elixir 1.17 needs OTP 25) and 2.17
(OTP 26 and later). To change them, update together:

- `targets` and `nif_versions` in `lib/networkex/native.ex`;
- `@nif_targets` and `@nif_versions` in `mix.exs` (the publish guard's expected checksums; a
  test fails until they match `lib/networkex/native.ex`);
- the build matrix and the release job's `NIF_VERSIONS` and `NIF_TARGETS` in
  `.github/workflows/release.yml` (a test fails until they match `mix.exs`), and the 12 of the
  descriptions above;
- the `nif_version_*` features in `native/networkex_native/Cargo.toml` (one per NIF version);
- the list above.
