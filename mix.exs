defmodule Networkex.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/CountlinkX-Solutions/networkex"
  @checksum_file "checksum-Elixir.Networkex.Native.exs"

  def project do
    [
      app: :networkex,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Spatial network analysis for Elixir, backed by a Rust core.",
      name: "Networkex",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        # "Run in Livebook" works from HexDocs: the notebooks install everything from Hex and,
        # outside the repository, download their data from the release tag on GitHub.
        "notebooks/tempe_case.livemd": [title: "Use case: crime on the streets of Tempe"],
        "notebooks/es/caso_tempe.livemd": [
          title: "Caso de uso: delitos en las calles de Tempe (es)"
        ],
        "notebooks/tempe_osm_case.livemd": [title: "Use case: Tempe on OpenStreetMap streets"],
        "notebooks/es/caso_tempe_osm.livemd": [title: "Caso de uso: Tempe en calles de OSM (es)"],
        "notebooks/snow_network_case.livemd": [title: "Use case: John Snow's map on the streets"],
        "notebooks/es/caso_snow_red.livemd": [
          title: "Caso de uso: el mapa de Snow en la red (es)"
        ],
        "docs/architecture.md": [title: "Architecture"],
        "docs/parity.md": [title: "Parity"],
        LICENSE: [title: "License"],
        NOTICE: [title: "Notice"],
        "THIRD_PARTY_NOTICES.md": [title: "Third-party notices"]
      ],
      # Networkex.Native is internal (@moduledoc false) but the architecture doc names it.
      skip_undefined_reference_warnings_on: ["docs/architecture.md"],
      groups_for_extras: [
        Guides: ~r{docs/},
        Notebooks: ~r{notebooks/},
        Legal: ["LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"]
      ]
    ]
  end

  # Ship the NIF sources, their Cargo target settings (`.cargo`) and the precompiled NIF
  # checksums once a release has them; `priv/native` is a build output and never packaged.
  # `LICENSES` holds the license texts that NOTICE and THIRD_PARTY_NOTICES.md refer to; the
  # PSF-2.0 and spaghetti BSD-3-Clause texts must travel with the code derived from CPython and
  # spaghetti in native/networkex_core and lib/networkex/network.ex.
  # Hex refuses a pattern that matches nothing, so the checksum file is listed only when it
  # exists. Without it the package builds the NIF from source (see Networkex.Native), which is
  # why `mix hex.publish` refuses to run without it (see guarded_publish/2).
  defp package do
    [
      # SPDX identifiers: the code is Apache-2.0, with portions derived from CPython (PSF-2.0)
      # and spaghetti (BSD-3-Clause); see NOTICE.
      licenses: ["Apache-2.0", "PSF-2.0", "BSD-3-Clause"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/networkex/changelog.html"
      },
      files:
        ~w(lib native/networkex_core/src native/networkex_core/Cargo.toml
           native/networkex_native/src native/networkex_native/Cargo.toml
           .cargo Cargo.toml Cargo.lock mix.exs docs README.md CHANGELOG.md LICENSE NOTICE
           LICENSES THIRD_PARTY_NOTICES.md) ++
          Path.wildcard("checksum-*.exs")
    ]
  end

  # A single function, not a list: Mix passes the command-line arguments only to the last entry
  # of an alias, so a check listed before "hex.publish" would never see them.
  defp aliases do
    ["hex.publish": &guarded_publish/1]
  end

  # The precompiled NIFs of Networkex.Native (`targets` x `nif_versions` there; a test keeps the
  # two lists equal).
  @nif_targets ~w(
    aarch64-apple-darwin
    aarch64-unknown-linux-gnu
    x86_64-apple-darwin
    x86_64-pc-windows-msvc
    x86_64-unknown-linux-gnu
    x86_64-unknown-linux-musl
  )
  @nif_versions ["2.16", "2.17"]

  @doc false
  def nif_artifacts(version) do
    for target <- @nif_targets, nif_version <- @nif_versions do
      {prefix, ext} = if target =~ "windows", do: {"", "dll"}, else: {"lib", "so"}
      "#{prefix}networkex_native-v#{version}-nif-#{nif_version}-#{target}.#{ext}.tar.gz"
    end
  end

  # `mix hex.publish`: checks the checksum file, then runs Hex's task with the same arguments.
  # `rustler` is optional, so a package published without the precompiled NIF checksums of its
  # own version would make every user build the NIF from source, which fails unless they have
  # Rust and `:rustler`. Publishing only the docs, reverting and pre-release versions (always
  # built from source, see Networkex.Native) need no checksums. See RELEASING.md for how the file
  # is produced. The options exist for the tests.
  @doc false
  def guarded_publish(args, opts \\ []) do
    config = Mix.Project.config()

    opts =
      Keyword.merge(
        [
          run: &Mix.Task.run/2,
          dir: File.cwd!(),
          version: config[:version],
          files: config[:package][:files]
        ],
        opts
      )

    if publishes_package?(args) and Version.parse!(opts[:version]).pre == [] do
      check_checksum_file!(opts[:dir], opts[:version], opts[:files])
    end

    opts[:run].("hex.publish", args)
  end

  # The switches of Hex's own `mix hex.publish` (Mix.Tasks.Hex.Publish in Hex 2.5.3), parsed the
  # way it parses them, so that a switch value such as an organization named "docs" is never
  # taken for the `docs` subcommand.
  @hex_publish_switches [
    revert: :string,
    progress: :boolean,
    organization: :string,
    organisation: :string,
    yes: :boolean,
    dry_run: :boolean,
    replace: :boolean
  ]

  defp publishes_package?(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @hex_publish_switches)

    # Hex refuses arguments it cannot parse; until then they count as a package publish, the
    # most they could do (how OptionParser splits an unknown switch from its neighbours varies).
    invalid != [] or (positional != ["docs"] and not Keyword.has_key?(opts, :revert))
  end

  defp check_checksum_file!(dir, version, files) do
    path = Path.join(dir, @checksum_file)

    cond do
      not File.exists?(path) ->
        refuse_publish("""
        #{@checksum_file} is missing.

        Without it the package builds the NIF from source on every user's machine. Wait for the
        release workflow to attach the precompiled NIFs to the GitHub release of v#{version}, then
        run `mix rustler_precompiled.download Networkex.Native --all --print` (see RELEASING.md).
        """)

      @checksum_file not in files ->
        refuse_publish("""
        #{@checksum_file} exists but is not in the package files.

        The package file list is computed when mix.exs loads, so a checksum file created by an
        earlier task of the same `mix` invocation is left out. Run `mix hex.publish` again as a
        new command.
        """)

      true ->
        check_checksums!(path, version)
    end
  end

  defp check_checksums!(path, version) do
    expected = MapSet.new(nif_artifacts(version))

    case read_checksums(path) do
      {:ok, checksums} ->
        names = MapSet.new(Map.keys(checksums))
        missing = expected |> MapSet.difference(names) |> Enum.sort()
        unexpected = names |> MapSet.difference(expected) |> Enum.sort()
        sha256? = Enum.all?(Map.values(checksums), &(&1 =~ ~r/\Asha256:[0-9a-f]{64}\z/))

        if missing != [] or unexpected != [] or not sha256? do
          refuse_publish("""
          #{@checksum_file} does not hold the SHA-256 checksums of exactly the \
          #{MapSet.size(expected)} precompiled NIFs of v#{version}.
          #{list_names("missing", missing)}#{list_names("unexpected", unexpected)}
          It may be left over from another release. Delete it and download it again with
          `mix rustler_precompiled.download Networkex.Native --all --print` (see RELEASING.md).
          """)
        end

      :error ->
        refuse_publish("""
        #{@checksum_file} is not a map of artifact names to checksums.

        Delete it and download it again with
        `mix rustler_precompiled.download Networkex.Native --all --print` (see RELEASING.md).
        """)
    end
  end

  # The file is read as data, not evaluated.
  defp read_checksums(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, {:%{}, _meta, [_ | _] = pairs}} <- Code.string_to_quoted(contents),
         true <- Enum.all?(pairs, &match?({k, v} when is_binary(k) and is_binary(v), &1)) do
      {:ok, Map.new(pairs)}
    else
      _ -> :error
    end
  end

  defp list_names(_label, []), do: ""
  defp list_names(label, names), do: "\n#{label}:\n" <> Enum.map_join(names, &"  #{&1}\n")

  defp refuse_publish(reason), do: Mix.raise("Refusing to publish: " <> reason)

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # The crate is rustler 0.39; Hex has the Mix package 0.38.0, which builds it (as in Spatex).
      # Optional, as rustler_precompiled expects: users of the precompiled NIFs never need it,
      # and a source build (see Networkex.Native) needs it in the user's own deps.
      {:rustler, "~> 0.38", runtime: false, optional: true},
      {:rustler_precompiled, "~> 0.8"},
      {:nx, "~> 0.10", optional: true},
      {:explorer, "~> 0.13", optional: true},
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      # The oracle test helper decodes fixtures with it; nothing in lib/ uses it. Optional, so
      # applications do not inherit it (rustler, when present, brings its own requirement).
      {:jason, "~> 1.4", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      # For the Networkex.GeoFrame tests only. The adapter calls GeoFrame at runtime, so
      # Networkex compiles and runs without it and the Hex package does not require it.
      {:geoframe, "~> 0.3.4", only: :test}
    ]
  end
end
