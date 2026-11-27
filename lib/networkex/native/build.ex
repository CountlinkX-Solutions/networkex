defmodule Networkex.Native.Build do
  @moduledoc false
  # Whether Networkex.Native builds the NIF from source instead of downloading the precompiled
  # one. Networkex.Native calls it while it compiles, with the values it read:
  #
  #   * `:env` - the NETWORKEX_BUILD environment variable ("1" or "true" force a source build);
  #   * `:config` - `config :rustler_precompiled, :force_build, networkex: true`, the setting
  #     rustler_precompiled itself documents and suggests when a download fails;
  #   * `:version` - the package version (pre-releases have no precompiled NIFs);
  #   * `:checksum_file?` - whether the package ships its checksum file (a checkout does not).

  @spec force?(keyword()) :: boolean()
  def force?(opts) do
    Keyword.fetch!(opts, :env) in ["1", "true"] or
      Keyword.fetch!(opts, :config) == true or
      Version.parse!(Keyword.fetch!(opts, :version)).pre != [] or
      not Keyword.fetch!(opts, :checksum_file?)
  end
end
