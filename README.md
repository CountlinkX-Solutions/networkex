# Networkex

[![Hex.pm](https://img.shields.io/hexpm/v/networkex.svg)](https://hex.pm/packages/networkex)
[![HexDocs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/networkex)
[![CI](https://github.com/CountlinkX-Solutions/networkex/actions/workflows/ci.yml/badge.svg)](https://github.com/CountlinkX-Solutions/networkex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/networkex.svg)](LICENSE)

Spatial network analysis for Elixir. Networkex builds networks from street or river lines,
snaps observations to them, and measures distances and neighbours **along** the network instead
of in a straight line. On top of that it computes network spatial weights and
network-constrained point pattern statistics such as the network K-function. It ports the
functionality of [spaghetti](https://github.com/pysal/spaghetti), PySAL's library for spatial
analysis on networks, and checks its results against spaghetti's; the covered functionality and
every deviation are listed in [docs/parity.md](docs/parity.md). The algorithms are written in
Rust and reach Elixir through a thin NIF layer.

Networkex is analysis on networks, not a routing engine for routes, isochrones or fleets at
scale.

## Installation

Add `networkex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:networkex, "~> 0.3"}
  ]
end
```

Networkex needs Elixir 1.17 or later, and so Erlang/OTP 25 or later. The NIF is precompiled for
NIF versions 2.16 (OTP 25) and 2.17 (OTP 26 and later) on these targets, so no Rust toolchain is
needed:

- `aarch64-apple-darwin` and `x86_64-apple-darwin` (macOS)
- `aarch64-unknown-linux-gnu` and `x86_64-unknown-linux-gnu` (Linux, glibc 2.28 or newer)
- `x86_64-unknown-linux-musl` (Linux, musl)
- `x86_64-pc-windows-msvc` (Windows)

### Building the NIF from source

On other platforms (for example `aarch64-unknown-linux-musl` or FreeBSD), or on a Linux system
with a glibc older than 2.28 where the precompiled NIF does not load, build the NIF from source.
You need Rust 1.91 or newer and `rustler` in your own dependencies, because Networkex declares it
optional:

```elixir
def deps do
  [
    {:networkex, "~> 0.3"},
    {:rustler, "~> 0.38", runtime: false}
  ]
end
```

Then set `NETWORKEX_BUILD=1` (or `true`). The variable is read when Networkex compiles, so
recompile it after changing it:

```sh
NETWORKEX_BUILD=1 mix deps.compile networkex --force
```

Instead of the variable you can use `rustler_precompiled`'s own setting, in `config/config.exs`:

```elixir
config :rustler_precompiled, :force_build, networkex: true
```

Pre-release versions (`X.Y.Z-rc.N`) always build from source.

## Quickstart

Three streets around a block, two schools and three homes. Points are snapped to the nearest
street, and the distance to the nearest school is measured along the streets:

```elixir
iex> streets = [
...>   [{0, 0}, {100, 0}, {200, 0}],
...>   [{100, 0}, {100, 100}],
...>   [{100, 100}, {200, 100}, {200, 0}]
...> ]
iex> ntw = Networkex.Network.new(streets)
iex> {ntw.arcs, ntw.arc_lengths}
{[{0, 1}, {1, 2}, {1, 3}, {2, 4}, {3, 4}], [100.0, 100.0, 100.0, 100.0, 100.0]}
iex> schools = Networkex.Network.snap(ntw, [{10, 5}, {195, 60}])
iex> schools.snapped
[{10.0, 0.0}, {200.0, 60.0}]
iex> homes = Networkex.Network.snap(ntw, [{90, 40}, {150, 110}, {205, 30}])
iex> Networkex.Network.nearest_neighbor_distances(ntw, homes, schools)
[{[0], 130.0}, {[1], 90.0}, {[1], 30.0}]
iex> Networkex.Network.counts_per_link(ntw, homes)
[0, 0, 1, 1, 1]
iex> w = Networkex.Network.contiguity_weights(ntw)
iex> {w.focal, w.neighbor}
{[0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4], [1, 2, 0, 2, 3, 0, 1, 4, 1, 4, 2, 3]}
```

The first home is 130 units from the first school along the streets (40 down its street to the
corner, then 90 along the bottom one), against about 98 in a straight line between the same
snapped points. Each nearest
neighbour comes as `{indices, distance}`, with every index at the minimum distance.
`counts_per_link/3` gives the number of homes on each arc, and `contiguity_weights/2` the arcs
that share a vertex, as `focal`/`neighbor`/`weight` arrays by arc index.

## Features

The analysis functions are in `Networkex.Network`; see its documentation for the options.

- **Networks**: `new/2` from point lists or WKB `LineString`/`MultiLineString` binaries, with
  spaghetti's vertex rounding (`:vertex_sig`, `:vertex_atol`): vertices, arcs and their
  lengths, adjacency, connected components, and the graph with degree-2 chains merged into
  edges. `arcs_at/2` lists the arcs at a vertex.
- **Observations**: `snap/2` snaps points to their nearest arc and returns a
  `Networkex.PointPattern` with the snapped points and the distances to the arc's vertices.
- **Distances along the network**: `distance_matrix/2` between vertices,
  `all_neighbor_distances/4` and `nearest_neighbor_distances/4` between observations, and
  `shortest_paths/3` with the coordinates of each path.
- **Spatial weights**: `contiguity_weights/2` (arcs or graph edges, binary, by length or by
  value), `distance_band_weights/3` and `counts_per_link/3`.
- **Point pattern statistics**: `simulate_observations/3` and the global network K-function
  with a Monte Carlo envelope, `global_auto_k/3`; random steps take a `:seed`.
- **Utilities**: `split_arcs/3`, `extract_component/2`, `spanning_tree/2` and
  `regular_lattice/3`.
- **Saving networks**: `to_binary/1`, `from_binary/1`, `save/2` and `load/1`.

Numeric inputs are lists, `Nx` tensors or `Explorer` series (see `Networkex.Input`).

### Optional integrations

- **Nx and Explorer** are optional dependencies: add them to your own dependencies to pass
  tensors or series. Networkex compiles and runs without them.
- **GeoFrame**: `Networkex.GeoFrame` builds networks from [GeoFrame](https://hexdocs.pm/geoframe)
  data frames of line geometries, snaps their geometries, and returns arcs, point patterns and
  shortest paths as GeoFrame frames for maps. Networkex does not depend on GeoFrame: the adapter
  calls it at runtime, and works once GeoFrame is in your own dependencies:

  ```elixir
  {:geoframe, "~> 0.3.4"}
  ```

- **Spatex**: the weights use the `focal`/`neighbor`/`weight` array layout of the
  [Spatex](https://hexdocs.pm/spatex) spatial statistics library, so the counts and weights can
  feed its statistics, such as Moran's I.

## Parity with spaghetti

Results are checked against spaghetti 1.7.6: Python scripts run spaghetti and libpysal on the
geodanet streets of Tempe, Arizona, and on synthetic networks, and the Elixir and Rust tests
compare against the committed outputs. [docs/parity.md](docs/parity.md) lists what is covered
and every deviation, and the [fixture generators](https://github.com/CountlinkX-Solutions/networkex/blob/main/test/reference/README.md)
describe how the reference outputs are produced. [docs/architecture.md](docs/architecture.md)
describes the Elixir and Rust layers.

## Stability

Networkex follows [Semantic Versioning](https://semver.org/). Before 1.0, a minor release
(0.4.0) may change the public API, and the [changelog](CHANGELOG.md) lists every such change; a
patch release (0.3.1) does not. To receive patch releases only, use `{:networkex, "~> 0.3.0"}`.

The public API is the documented functions and structs of `Networkex.Network`,
`Networkex.PointPattern`, `Networkex.Input` and `Networkex.GeoFrame`. Modules and functions
without documentation, such as the NIF bindings, and the `ref` field of a network, which points
to the network in Rust memory, are internal.

`Networkex.Network.to_binary/1` writes networks in a versioned format (currently version 1).
`from_binary/1` and `load/1` return `{:error, reason}` for a version they do not read, instead
of misreading it, and a release that changes the format says so in the changelog.

## Notebooks

Livebook use cases, in English and Spanish, are part of the documentation: open one from HexDocs
with "Run in Livebook", or from a clone of the repository. They install Networkex, GeoFrame and
Spatex from Hex; see each notebook's setup to run one against a local checkout of Networkex.

- [Crime on the streets of Tempe](notebooks/tempe_case.livemd): the network, distances to the
  nearest school, the network K-function, crimes per street with Moran's I and shortest paths, on
  the spaghetti tutorials' data. Spanish: [caso_tempe.livemd](notebooks/es/caso_tempe.livemd).
- [The Tempe crimes on OpenStreetMap streets](notebooks/tempe_osm_case.livemd): the same crimes
  and schools on current OpenStreetMap streets, compared with the geodanet network. Spanish:
  [caso_tempe_osm.livemd](notebooks/es/caso_tempe_osm.livemd).
- [John Snow's cholera map on the streets of Soho](notebooks/snow_network_case.livemd): topology
  cleaning of the digitised streets, the nearest pump on foot, the network K-function of the
  deaths, deaths per street with Moran's I and walking routes to Broad Street. Spanish:
  [caso_snow_red.livemd](notebooks/es/caso_snow_red.livemd).

## Related projects

Networkex shares its conventions (committed reference fixtures, documented deviations, a seed
for every random step) with these libraries:

- **Spatex**, spatial statistics after PySAL: [Hex](https://hex.pm/packages/spatex),
  [HexDocs](https://hexdocs.pm/spatex), [GitHub](https://github.com/CountlinkX-Solutions/spatex).
- **Geostatex**, geostatistics: [Hex](https://hex.pm/packages/geostatex),
  [HexDocs](https://hexdocs.pm/geostatex),
  [GitHub](https://github.com/CountlinkX-Solutions/geostatex).
- **GeoFrame**, geospatial data frames: [Hex](https://hex.pm/packages/geoframe),
  [HexDocs](https://hexdocs.pm/geoframe),
  [GitHub](https://github.com/CountlinkX-Solutions/geoframe).

## Contributing

Bug reports, questions and pull requests are welcome; see the
[contributing guide](https://github.com/CountlinkX-Solutions/networkex/blob/main/CONTRIBUTING.md)
and the [code of conduct](https://github.com/CountlinkX-Solutions/networkex/blob/main/CODE_OF_CONDUCT.md).
Report security issues privately, as described in the
[security policy](https://github.com/CountlinkX-Solutions/networkex/blob/main/SECURITY.md).

## License

Copyright 2026 Yendris Rogelio Cruz Mendoza. Licensed under the Apache License 2.0; see
[LICENSE](LICENSE). Portions of the code are derived from spaghetti (BSD 3-Clause License) and
from CPython's `math.hypot` (Python Software Foundation License Version 2), so the Hex package
declares the licenses `Apache-2.0`, `PSF-2.0` and `BSD-3-Clause`. [NOTICE](NOTICE) holds the
attribution notices, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) describes the derived
code, the Rust crates linked into the precompiled NIFs and the third-party data in the
repository, and the
[LICENSES](https://github.com/CountlinkX-Solutions/networkex/tree/main/LICENSES) directory holds
the license texts.
