defmodule Networkex.NativeTest do
  use ExUnit.Case, async: true

  test "the NIF library loads and reports the ABI version the Elixir layer expects" do
    assert Networkex.Native.nif_version() == 2
  end

  test "the core decodes the f64 wire format" do
    {bin, 3} = Networkex.Input.to_f64_binary([1.5, -2, 4])
    assert Networkex.Native.sum_f64(bin) == {:ok, 3.5}
    assert {:error, message} = Networkex.Native.sum_f64(<<0::72>>)
    assert message =~ "multiple of 8"
  end

  describe "building the NIF from source" do
    alias Networkex.Native.Build

    @release [env: nil, config: nil, version: "0.3.0", checksum_file?: true]

    test "a release with its checksum file downloads the precompiled NIF" do
      refute Build.force?(@release)
    end

    test "NETWORKEX_BUILD set to 1 or true forces a source build" do
      assert Build.force?(Keyword.put(@release, :env, "1"))
      assert Build.force?(Keyword.put(@release, :env, "true"))
      refute Build.force?(Keyword.put(@release, :env, "0"))
      refute Build.force?(Keyword.put(@release, :env, ""))
    end

    test "rustler_precompiled's force_build config for :networkex forces a source build" do
      assert Build.force?(Keyword.put(@release, :config, true))
      refute Build.force?(Keyword.put(@release, :config, false))
    end

    test "a pre-release or a package without the checksum file builds from source" do
      assert Build.force?(Keyword.put(@release, :version, "0.4.0-rc.1"))
      assert Build.force?(Keyword.put(@release, :checksum_file?, false))
    end
  end
end
