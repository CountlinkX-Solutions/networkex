# Architecture

## Layout

| Path | Role |
|---|---|
| `lib/networkex.ex`, `lib/networkex/` | Public Elixir API and input normalization (`Networkex.Input`) |
| `lib/networkex/native.ex` | `Networkex.Native`, the NIF bindings (internal) |
| `native/networkex_core` | Pure-Rust algorithms, unit-tested, no Rustler types |
| `native/networkex_native` | Thin Rustler layer over the core |
| `lib/networkex/geo_frame.ex` | `Networkex.GeoFrame`, the runtime adapter to GeoFrame (optional) |
| `test/reference` | Fixture generators (Python, dev-time only) and committed fixtures |
| `notebooks` | Livebook use cases (English, `notebooks/es` Spanish), run with `scripts/run_livemd.exs` |

## NIF boundary

Numeric vectors cross the boundary as native-endian `f64` binaries and index vectors as `u32`
binaries, built by `Networkex.Input` (the same contract as Spatex and Geostatex). NIFs return
`{:ok, value} | {:error, reason}`; the public layer turns errors into `ArgumentError`. Work that
grows with the input runs on dirty CPU schedulers. A built network is held in Rust memory as a
resource, so repeated queries do not rebuild it. `Network.to_binary/1` writes it in a versioned
little-endian format (`native/networkex_core/src/persist.rs`) that `from_binary/1` rebuilds; these
and `load/1` return `{:error, reason}` instead of raising, since a bad file is not a programming
error.

## Conventions

The API conventions of Spatex apply: options are a trailing keyword list with unknown keys
rejected, `seed: nil` draws a seed and records it in the result, and inputs are lists, `Nx`
tensors or `Explorer` series. Network weights are exported as `Spatex.Graph`-compatible arrays
(focal, neighbor, weight), so network neighbors feed Spatex statistics directly.

## Known limitations

- **Graph extraction is quadratic.** Building a network extracts its graph (chains of degree-2
  vertices merged into edges) with list operations whose time grows with the square of the
  arcs in such chains. A single polyline of 100_000 vertices passed to
  `Networkex.Network.new/2` takes about 3 seconds, and `Networkex.Network.split_arcs/3`, which
  builds the graph of the split network, takes about a third of a second for 25_000 arcs,
  3 seconds for 100_000 and nearly 20 seconds for 250_000 (measured with the release NIF on a
  recent x86-64 machine). The work runs on a dirty CPU scheduler and cannot be interrupted.
- **`split_arcs/3` bounds memory, not time.** Its `:max_arcs` option (default 250_000, at most
  67_108_864) is a hard limit on the arcs of the result, counted before anything is allocated,
  so a split never allocates beyond it; a split near the limit still takes the time above.
