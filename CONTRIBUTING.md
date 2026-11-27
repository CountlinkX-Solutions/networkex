# Contributing to Networkex

Bug reports, questions and pull requests are welcome. Everyone taking part follows the
[code of conduct](CODE_OF_CONDUCT.md). Report security issues privately, as described in
[SECURITY.md](SECURITY.md), not as public issues.

## Development setup

- **Elixir and Erlang/OTP**: the versions in [`.tool-versions`](.tool-versions) (Elixir 1.19 on
  OTP 28). Networkex supports Elixir 1.17 and later; CI also tests Elixir 1.17 on OTP 27.
- **Rust 1.91 or newer** (the workspace `rust-version` in [`Cargo.toml`](Cargo.toml)), with
  `rustfmt` and `clippy`.

```sh
mix deps.get
mix test
cargo test --workspace
```

A checkout always builds the NIF from source with Rustler, because the precompiled NIF checksum
file is generated only for a release and never committed (see [RELEASING.md](RELEASING.md)).
CI also sets `NETWORKEX_BUILD=1`, which forces the source build in any case.

[docs/architecture.md](docs/architecture.md) describes the layout: the algorithms and their unit
tests live in the pure-Rust crate `native/networkex_core`, `native/networkex_native` is a thin
Rustler layer, and `lib/` holds the Elixir API and input validation.

## Checks

CI runs these commands; run them before opening a pull request.

```sh
# Elixir (MIX_ENV=test, NETWORKEX_BUILD=1)
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test

# Package and docs (MIX_ENV=dev)
mix deps.unlock --check-unused
mix docs --warnings-as-errors
mix hex.build

# Rust
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build -p networkex_native --locked --no-default-features --features nif_version_2_16
cargo build -p networkex_native --locked --no-default-features --features nif_version_2_17
```

A separate job checks the minimum supported Rust version with `cargo check --workspace
--all-targets --locked` and `cargo test --workspace --locked` on Rust 1.91. CI runs the Elixir
tests on Linux, macOS and Windows.

### GeoFrame tests

The `Networkex.GeoFrame` tests (tagged `:geoframe`) run with the rest of the suite, against
[GeoFrame](https://hex.pm/packages/geoframe) from Hex. GeoFrame is a test-only dependency:
Networkex itself does not depend on it, and its precompiled NIF needs no Rust build.

### Notebooks

The notebooks install Networkex, GeoFrame and Spatex from Hex, and are not run in CI.
`scripts/run_livemd.exs` runs every code cell of a notebook headlessly. `NETWORKEX_PATH` makes a
notebook use a local checkout instead of the Networkex release on Hex, so this runs a notebook
against your working tree:

```sh
NETWORKEX_PATH=$PWD elixir scripts/run_livemd.exs notebooks/tempe_case.livemd
```

Outside the repository, such as after "Run in Livebook" on HexDocs, a notebook downloads its data
from `notebooks/data` at the release tag of the installed Networkex version on GitHub, so a
change to the data reaches those readers only with the next release.

## Reference fixtures

Results are checked against spaghetti through JSON fixtures in `test/reference/fixtures`. The
Python scripts `test/reference/generate_<name>.py` produce them by running the reference
libraries listed in [test/reference/requirements.txt](test/reference/requirements.txt), and the
fixtures are committed: CI never runs Python. That file pins spaghetti, libpysal, esda, numpy and
scipy; geopandas and shapely are not pinned. Every fixture records the versions of spaghetti,
libpysal, numpy and scipy in its `meta` block. To regenerate one, with
[uv](https://docs.astral.sh/uv/) and Python 3.13 (the `hypot` fixture also records the exact
Python version, 3.13.15, because it holds the results of CPython's `math.hypot`; the other
fixtures do not record it):

```sh
uv venv .venv
uv pip install --python .venv/bin/python -r test/reference/requirements.txt
prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_<name>.py
```

`prlimit` (Linux) caps the generator's memory at 3 GiB. A generator only runs the reference
libraries and records their outputs; it never copies their code. See
[test/reference/README.md](test/reference/README.md) for the JSON conventions.

When you add or change behaviour that spaghetti also has, add a case to the matching generator,
regenerate its fixture, and record any deliberate deviation in [docs/parity.md](docs/parity.md).
Code translated from spaghetti's source carries a `Derived from spaghetti 1.7.6` comment that
names the spaghetti function, and is listed in section (a) of
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); keep both up to date.

## Pull requests

- Keep a pull request to one change, with its tests and documentation.
- Write commit messages as [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
  `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `build:`, `ci:` or `chore:`, followed by a
  short summary in the imperative.
- Add user-visible changes to the unreleased section of [CHANGELOG.md](CHANGELOG.md).
- New public functions need documentation, and a doctest where an example helps.
- Pull requests target `main` and need a green CI.

Contributions are licensed under the Apache License 2.0, as section 5 of [LICENSE](LICENSE)
states.
