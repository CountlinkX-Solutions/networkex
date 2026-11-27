defmodule Networkex.Native do
  @moduledoc false
  # NIF bindings to the `networkex_native` Rust crate. Each function below is replaced when the
  # NIF library loads; the bodies only run if loading failed.
  #
  # The library is built from source with Rustler unless a release ships precompiled artifacts:
  # building is forced when NETWORKEX_BUILD is "1"/"true", with
  # `config :rustler_precompiled, :force_build, networkex: true`, when the version is a
  # pre-release, or when no checksum file ships with the package (see Networkex.Native.Build).
  # rustler_precompiled reads that config only when `force_build:` is not given, hence here.
  alias Networkex.Native.Build

  version = Mix.Project.config()[:version]

  force_build? =
    Build.force?(
      env: System.get_env("NETWORKEX_BUILD"),
      config: Application.compile_env(:rustler_precompiled, [:force_build, :networkex]),
      version: version,
      checksum_file?: File.exists?("checksum-Elixir.Networkex.Native.exs")
    )

  # The release workflow builds these, and `mix hex.publish` expects their checksums (mix.exs).
  @nif_versions ["2.16", "2.17"]
  @targets ~w(
    aarch64-apple-darwin
    aarch64-unknown-linux-gnu
    x86_64-apple-darwin
    x86_64-pc-windows-msvc
    x86_64-unknown-linux-gnu
    x86_64-unknown-linux-musl
  )

  use RustlerPrecompiled,
    otp_app: :networkex,
    crate: "networkex_native",
    version: version,
    base_url: "https://github.com/CountlinkX-Solutions/networkex/releases/download/v#{version}",
    force_build: force_build?,
    nif_versions: @nif_versions,
    targets: @targets

  @doc false
  def precompiled, do: %{nif_versions: @nif_versions, targets: @targets}

  def nif_version, do: :erlang.nif_error(:nif_not_loaded)
  def sum_f64(_binary), do: :erlang.nif_error(:nif_not_loaded)

  # Networks. Coordinates are f64 binaries, part offsets u32 binaries.
  def network_from_coords(_coords, _offsets, _vertex_sig, _vertex_atol),
    do: :erlang.nif_error(:nif_not_loaded)

  def network_from_wkb(_wkbs, _vertex_sig, _vertex_atol), do: :erlang.nif_error(:nif_not_loaded)
  def network_snap(_ref, _points), do: :erlang.nif_error(:nif_not_loaded)
  def network_distance_matrix(_ref, _max_cells), do: :erlang.nif_error(:nif_not_loaded)

  def network_all_neighbors(_ref, _source, _dest, _snap_dist, _diagonal),
    do: :erlang.nif_error(:nif_not_loaded)

  def network_nearest(_ref, _source, _dest, _snap_dist, _keep_zero),
    do: :erlang.nif_error(:nif_not_loaded)

  def network_contiguity_weights(_ref, _graph, _by_length, _values),
    do: :erlang.nif_error(:nif_not_loaded)

  def network_distance_band_weights(_ref, _threshold, _max_cells),
    do: :erlang.nif_error(:nif_not_loaded)

  def network_counts(_ref, _pattern, _graph), do: :erlang.nif_error(:nif_not_loaded)
  def network_arc_order(_ref), do: :erlang.nif_error(:nif_not_loaded)
  def network_total_length(_ref), do: :erlang.nif_error(:nif_not_loaded)
  def network_simulate(_ref, _positions), do: :erlang.nif_error(:nif_not_loaded)
  def network_split_arcs(_ref, _spec, _max_arcs), do: :erlang.nif_error(:nif_not_loaded)
  def network_extract_component(_ref, _component), do: :erlang.nif_error(:nif_not_loaded)
  def network_spanning_tree(_ref, _maximum), do: :erlang.nif_error(:nif_not_loaded)
  def network_shortest_paths(_ref, _source, _dest), do: :erlang.nif_error(:nif_not_loaded)

  def network_to_binary(_ref, _vertex_sig, _vertex_atol), do: :erlang.nif_error(:nif_not_loaded)
  def network_from_binary(_binary), do: :erlang.nif_error(:nif_not_loaded)

  def network_global_auto_k(_ref, _pattern, _steps, _simulations),
    do: :erlang.nif_error(:nif_not_loaded)
end
