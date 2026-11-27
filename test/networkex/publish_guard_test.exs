defmodule Networkex.PublishGuardTest do
  # The Hex package must ship the precompiled NIF checksum file of its own version: `rustler`
  # is an optional dependency, so without that file a user's compile would need Rust and
  # `:rustler`. mix.exs therefore replaces `mix hex.publish` with a guard that checks the file
  # and then runs the real task with the same arguments.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @checksum "checksum-Elixir.Networkex.Native.exs"
  @version "0.3.0"

  # Runs the guard with a runner that records what would reach the real `mix hex.publish`.
  defp publish(args, dir, opts \\ []) do
    test = self()

    runner = fn task, task_args ->
      send(test, {:ran, task, task_args})
      :published
    end

    opts = Keyword.merge([dir: dir, version: @version, files: [@checksum], run: runner], opts)
    Networkex.MixProject.guarded_publish(args, opts)
  end

  defp write_checksums(dir, names) do
    lines =
      for name <- names do
        ~s(  "#{name}" => "sha256:#{String.duplicate("0f", 32)}",\n)
      end

    File.write!(Path.join(dir, @checksum), ["%{\n", lines, "}\n"])
  end

  defp refused(args, dir, opts \\ []) do
    error = assert_raise Mix.Error, fn -> publish(args, dir, opts) end
    refute_received {:ran, _, _}
    error.message
  end

  test "mix hex.publish is a single function, so it receives the command-line arguments" do
    guard = Mix.Project.config()[:aliases][:"hex.publish"]

    assert is_function(guard, 1)
    assert Function.info(guard)[:name] == :guarded_publish
  end

  test "the arguments reach hex.publish once the checksum file is valid", %{tmp_dir: dir} do
    write_checksums(dir, Networkex.MixProject.nif_artifacts(@version))

    for args <- [[], ["package"], ["--dry-run", "--yes"], ["--replace"], ["--organization", "a"]] do
      assert publish(args, dir) == :published
      assert_received {:ran, "hex.publish", ^args}
    end
  end

  test "documentation-only publishing and reverts need no checksum file", %{tmp_dir: dir} do
    for args <- [
          ["docs"],
          ["docs", "--dry-run"],
          ["--yes", "docs"],
          ["--revert", @version],
          ["--revert=#{@version}"],
          ["docs", "--revert", @version],
          # Every switch of Hex's task, so that none is mistaken for a positional argument.
          ["--organisation", "acme", "docs"],
          ["--organization", "acme", "docs"],
          ["--no-progress", "docs"],
          ["--progress", "docs"],
          ["--replace", "--dry-run", "docs"],
          ["--no-yes", "docs"]
        ] do
      assert publish(args, dir, files: []) == :published
      assert_received {:ran, "hex.publish", ^args}
    end
  end

  test "publishing a package without the checksum file is refused", %{tmp_dir: dir} do
    for args <- [
          [],
          ["package"],
          ["--dry-run", "--yes"],
          ["--replace"],
          ["--organization", "a"],
          # An organization named "docs" is a package publish, not the docs subcommand.
          ["--organization", "docs"],
          ["--organisation", "docs"],
          ["--organisation=docs"],
          ["--no-progress"],
          ["--progress", "package"]
        ] do
      message = refused(args, dir)
      assert message =~ "#{@checksum} is missing"
      assert message =~ "RELEASING.md"
    end
  end

  test "arguments Hex would not accept are checked as a package publish", %{tmp_dir: dir} do
    # Hex refuses them itself; until then the guard assumes the most it could publish.
    for args <- [["--unknown", "docs"], ["docs", "--organisation"], ["docs", "package"]] do
      assert refused(args, dir) =~ "#{@checksum} is missing"
    end
  end

  test "a checksum file the package does not list is refused", %{tmp_dir: dir} do
    write_checksums(dir, Networkex.MixProject.nif_artifacts(@version))

    message = refused(["--dry-run"], dir, files: ~w(lib mix.exs))
    assert message =~ "not in the package files"
    assert message =~ "new command"
  end

  test "a checksum file of another version is refused", %{tmp_dir: dir} do
    write_checksums(dir, Networkex.MixProject.nif_artifacts("0.2.0"))

    message = refused([], dir)
    assert message =~ "v#{@version}"
    assert message =~ "libnetworkex_native-v#{@version}-nif-2.17-aarch64-apple-darwin.so.tar.gz"
    assert message =~ "libnetworkex_native-v0.2.0-nif-2.17-aarch64-apple-darwin.so.tar.gz"
  end

  test "an incomplete or extended checksum file is refused", %{tmp_dir: dir} do
    [_ | eleven] = expected = Networkex.MixProject.nif_artifacts(@version)

    write_checksums(dir, eleven)
    assert refused([], dir) =~ "missing"

    extra = "libnetworkex_native-v#{@version}-nif-2.17-riscv64.so.tar.gz"
    write_checksums(dir, [extra | expected])
    assert refused([], dir) =~ "unexpected"
  end

  test "a checksum file that is not a map of SHA-256 checksums is refused", %{tmp_dir: dir} do
    path = Path.join(dir, @checksum)
    [name | _] = Networkex.MixProject.nif_artifacts(@version)

    for contents <- [
          "",
          "%{}\n",
          "[1, 2]\n",
          "%{\"#{name}\" => :ok}\n",
          "%{\"#{name}\" => \"sha256:abc\"}\n",
          "%{\n"
        ] do
      File.write!(path, contents)
      assert refused([], dir) =~ @checksum
    end
  end

  test "pre-release versions build from source and need no checksum file", %{tmp_dir: dir} do
    assert publish([], dir, version: "0.4.0-rc.1", files: []) == :published
    assert_received {:ran, "hex.publish", []}
  end

  test "the expected artifacts are the NIFs Networkex.Native downloads" do
    # rustler_precompiled's own naming (`nifs_from_metadata/1` is what its download task uses),
    # applied to the targets and NIF versions that Networkex.Native declares.
    metadata =
      Map.merge(Networkex.Native.precompiled(), %{
        base_url: "https://example.invalid/download",
        basename: "networkex_native",
        version: @version
      })

    {:ok, nifs} = RustlerPrecompiled.nifs_from_metadata(metadata)
    names = nifs |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    assert Enum.sort(Networkex.MixProject.nif_artifacts(@version)) == names
    assert length(names) == 12
  end

  test "the release workflow builds and checks the NIFs the guard expects" do
    workflow = File.read!(Path.expand("../../.github/workflows/release.yml", __DIR__))

    # The build matrix (`nif` and every `job` target) and the release job's NIF_VERSIONS and
    # NIF_TARGETS, from which it derives the artifact names it accepts.
    [nifs] = Regex.run(~r/^ +nif: \[(.*)\]$/m, workflow, capture: :all_but_first)
    matrix_nifs = ~r/"([^"]+)"/ |> Regex.scan(nifs, capture: :all_but_first) |> List.flatten()
    matrix_targets = Regex.scan(~r/^ +- \{ target: ([^,]+),/m, workflow, capture: :all_but_first)
    [env_nifs] = Regex.run(~r/^ +NIF_VERSIONS: "(.*)"$/m, workflow, capture: :all_but_first)

    [env_targets] =
      Regex.run(~r/^ +NIF_TARGETS: >-\n((?: {8,}\S.*\n)+)/m, workflow, capture: :all_but_first)

    expected = Enum.sort(Networkex.MixProject.nif_artifacts(@version))

    for {nifs, targets} <- [
          {matrix_nifs, List.flatten(matrix_targets)},
          {String.split(env_nifs), String.split(env_targets)}
        ] do
      assert expected == Enum.sort(artifacts(nifs, targets))
    end
  end

  # The workflow's naming: rustler_precompiled's, as nif_artifacts/1.
  defp artifacts(nifs, targets) do
    for nif <- nifs, target <- targets do
      if target =~ "windows",
        do: "networkex_native-v#{@version}-nif-#{nif}-#{target}.dll.tar.gz",
        else: "libnetworkex_native-v#{@version}-nif-#{nif}-#{target}.so.tar.gz"
    end
  end
end
