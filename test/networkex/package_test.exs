defmodule Networkex.PackageTest do
  # The Hex package must carry the notices and license texts that its code needs (NOTICE refers
  # to them), while the example data redistributed in the repository stays out of it.
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  @license_texts ~w(
    LICENSES/BSD-3-Clause-libpysal.txt
    LICENSES/BSD-3-Clause-spaghetti.txt
    LICENSES/PSF-2.0.txt
  )

  # The files that name license texts by path.
  @referrers ~w(
    NOTICE
    THIRD_PARTY_NOTICES.md
    RELEASING.md
    .github/workflows/release.yml
    test/reference/data/README.md
    notebooks/data/geodanet/README.md
    notebooks/data/snow/README.md
  )

  # The files Hex packs: an entry of `files` is a file, or a directory taken with its contents.
  defp package_files do
    Mix.Project.config()[:package][:files]
    |> Enum.flat_map(fn entry ->
      path = Path.join(@root, entry)

      if File.dir?(path),
        do: Path.wildcard(Path.join(path, "**"), match_dot: true),
        else: [path]
    end)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, @root))
  end

  # The code is Apache-2.0, with portions derived from CPython (PSF-2.0) and spaghetti
  # (BSD-3-Clause), all of them in networkex_core; see NOTICE.
  @licenses ["Apache-2.0", "PSF-2.0", "BSD-3-Clause"]

  test "the package declares the licenses of all its code" do
    assert Mix.Project.config()[:package][:licenses] == @licenses
  end

  test "networkex_core declares the same licenses as the package" do
    manifest = File.read!(Path.join(@root, "native/networkex_core/Cargo.toml"))

    assert [_, expression] = Regex.run(~r/^license = "([^"]+)"$/m, manifest),
           "native/networkex_core/Cargo.toml declares no license of its own"

    assert Enum.sort(String.split(expression, " AND ")) == Enum.sort(@licenses)
  end

  test "the package ships the notices and every license text" do
    files = package_files()

    for file <- ["LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md" | @license_texts] do
      assert file in files, "#{file} is not in the package"
    end

    assert Enum.sort(Path.wildcard(Path.join(@root, "LICENSES/*"))) ==
             Enum.map(@license_texts, &Path.join(@root, &1))
  end

  test "every license text named in the notices, the data READMEs and the release exists" do
    for referrer <- @referrers do
      named = Regex.scan(~r{LICENSES/[A-Za-z0-9.-]+\.txt}, File.read!(Path.join(@root, referrer)))

      for [path] <- named do
        assert path in @license_texts, "#{referrer} names #{path}, which does not exist"
      end
    end
  end

  test "the example data and the fixtures are not packaged" do
    data = ~w(.shp .shx .dbf .prj .xml .geojson .json .livemd)

    for file <- package_files() do
      refute String.starts_with?(file, ["test/", "notebooks/"]), "#{file} is in the package"
      refute Path.extname(file) in data, "#{file} is in the package"
    end
  end
end
