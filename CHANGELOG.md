# Changelog

All notable changes to Networkex are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.3.0] - Unreleased

First public release, and the first published on Hex.

### Added

- Precompiled NIFs: the NIF is downloaded for six targets (Linux glibc 2.28 or newer and musl,
  macOS and Windows) and NIF versions 2.16 and 2.17 when the package ships its checksum file.
  The NIF is built from source when no checksum file ships, for pre-release versions, with
  `NETWORKEX_BUILD=1`, or with `config :rustler_precompiled, :force_build, networkex: true`;
  `.cargo/config.toml` also covers source builds for `aarch64-unknown-linux-musl`.
- License notices: NOTICE holds the attribution notices for the code derived from spaghetti
  (BSD 3-Clause License) and CPython (`math.hypot`, Python Software Foundation License Version
  2). `THIRD_PARTY_NOTICES.md` lists the derived code and the changes made to CPython's, the Rust
  crates linked into the precompiled NIFs with the notices they need, and the third-party data in
  the repository with its attribution. `LICENSES/` holds the license texts of spaghetti, CPython
  and libpysal, and each GitHub release attaches the spaghetti and CPython texts beside the
  NIFs.

### Changed

- `rustler` is an optional dependency, as `rustler_precompiled` expects: users of the
  precompiled NIFs do not fetch it, and a source build needs `:rustler` in the application's own
  dependencies.
- `jason` is an optional dependency: only the test helpers use it, so applications no longer
  inherit it from Networkex.
- A source build compiles the NIF for NIF version 2.16, the oldest of the precompiled versions,
  instead of Rustler's default 2.15.
- The Hex package also ships `.cargo/config.toml` (the link settings source builds need on macOS
  and musl), the precompiled NIF checksum file, `LICENSES/` (the license texts of the code
  derived from CPython and spaghetti travel with it) and `THIRD_PARTY_NOTICES.md`.
- The package declares the licenses `Apache-2.0`, `PSF-2.0` and `BSD-3-Clause` (SPDX), instead of
  `Apache-2.0` alone, for the code derived from CPython and spaghetti.
- Documentation source links point at the release tag, and the package links include the
  changelog.
- The notebooks install Networkex, GeoFrame and Spatex from Hex instead of local checkouts
  (`NETWORKEX_PATH` selects a local Networkex checkout), and outside the repository they download
  their data from the release tag on GitHub, so they run from HexDocs with "Run in Livebook".
  The Tempe notebooks take the CRS of the geodanet `.prj` files, which GeoFrame now reads,
  instead of EPSG:2223.
- `Networkex.GeoFrame` is tested against GeoFrame 0.3.4 from Hex; its documentation gives the
  dependency to add.
- The README covers installing from Hex, the precompiled NIF targets, building from source with
  `NETWORKEX_BUILD`, and what the public API is; its quickstart runs as a doctest.

### Fixed

- `split_arcs/3` no longer allocates without bound. A split distance far below the arc lengths
  made the NIF allocate gigabytes, in native code that cannot be interrupted. The arcs of a split
  are now counted first, with one to spare for each arc cut (for the tiny last piece rounding
  can leave), and a split whose count exceeds the new option `:max_arcs` (default 250_000, at
  most 67_108_864) raises an `ArgumentError`, as `distance_matrix/2` does with `:max_cells`: a
  split that returns never has more arcs than `:max_arcs`. The limit bounds memory, not time
  (see "Known limitations" in the architecture guide).
- `split_arcs/3` raises an `ArgumentError` for a split distance too large for a float (such as
  `10 ** 400`, which raised an `ArithmeticError`), for a split count above 4_294_967_295 (which
  the NIF saturated) and for a split by count whose pieces would be shorter than the smallest
  normal float (which could loop forever).
- A network whose arc lengths, or their sum, overflow a float (finite coordinates about 1e308
  apart) raises an `ArgumentError` that says so, instead of a bare `argument error`.

## [0.2.0] - 2026-11-13

The spaghetti options that 0.1.0 left out, and saved networks.

### Added

- `Network.new/2` option `:vertex_atol` after spaghetti's `vertex_atol`: vertex coordinates are
  also rounded to that many decimals after `:vertex_sig`, which joins line ends with small
  digitising errors. `Networkex.GeoFrame.network/2` takes it too.
- `contiguity_weights/2` takes `weighting: values`, one number per arc (or graph edge), after
  spaghetti's `weightings` dict: each neighbour is weighted by its own value.
- `Network.arcs_at/2`: the arcs that touch a vertex, after spaghetti's `enum_links_vertex`.
- `Network.save/2` and `load/1` (`to_binary/1`, `from_binary/1`), after spaghetti's
  `savenetwork` and `loadnetwork`: the network in a versioned little-endian format, rebuilt on
  load. Malformed bytes give `{:error, reason}`.

## [0.1.0] - 2026-11-12

First release.

### Added

- Project foundation: Mix project with a Rust workspace (`networkex_core`, `networkex_native`),
  the shared input contract `Networkex.Input` (lists, Nx tensors, Explorer series), the oracle
  fixture harness and CI.
- `Networkex.Network.new/2`: networks from point lists or WKB lines after `spaghetti.Network`
  (vertex rounding, arcs, adjacency, components, extracted graph), verified against spaghetti.
- `Network.snap/2` (`Networkex.PointPattern`), `distance_matrix/2`, `all_neighbor_distances/4` and
  `nearest_neighbor_distances/4` after spaghetti's snapping and network distances.
- Network weights in Spatex's layout: `contiguity_weights/2` (arcs or edges, binary or by
  length), `distance_band_weights/3` and `counts_per_link/3`.
- `simulate_observations/3` and `global_auto_k/3` (with `arc_draw_order/1`) after spaghetti's
  `simulate_observations` and `GlobalAutoK`, seeded or replaying given draws.
- Utilities after spaghetti: `split_arcs/3` (by distance or count), `extract_component/2`,
  `spanning_tree/2` (minimum or maximum) and `regular_lattice/3`.
- `Networkex.GeoFrame`: networks from GeoFrame line frames, snapping their geometries, and
  arcs, point patterns and shortest paths back as GeoFrame frames (runtime adapter, GeoFrame
  optional).
- Notebooks: the Tempe crime use case, the same crimes on OpenStreetMap streets, and John Snow's
  cholera map on the street network of Soho, each in English and Spanish.
- `shortest_paths/3` after spaghetti's `allneighbordistances(gen_tree=True)` and
  `shortest_paths`.

### Fixed

- Arc lengths use `hypot`, as libpysal does, and now match spaghetti bit for bit.
- Segment lengths follow CPython's `math.hypot` algorithm instead of the platform's libm
  `hypot`, so arc lengths and `split_arcs/3` match spaghetti bit for bit on every platform
  (Ubuntu 26.04's libm rounded some lengths one ulp differently).
