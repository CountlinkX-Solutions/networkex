defmodule Networkex.PathsOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference, Shapefile}

  @fixture Reference.load!("network/paths.json")["cases"]
  @data Path.expand("../reference/data", __DIR__)

  setup_all do
    streets = Network.new(Shapefile.read_lines(Path.join(@data, "streets.shp")))
    schools = Network.snap(streets, Shapefile.read_points(Path.join(@data, "schools.shp")))

    crimes =
      Network.snap(
        streets,
        Shapefile.read_points(Path.join(@data, "crimes.shp")) |> Enum.take(40)
      )

    lattice =
      Network.new(Enum.map(@fixture["lattice"], fn l -> Enum.map(l, &List.to_tuple/1) end))

    pts = Network.snap(lattice, Enum.map(@fixture["lattice_points"], &List.to_tuple/1))

    %{
      "schools" => {streets, schools, nil},
      "crimes_to_schools" => {streets, crimes, schools},
      "lattice" => {lattice, pts, nil}
    }
  end

  defp flat(points), do: Enum.flat_map(points, &Tuple.to_list/1)

  defp length_of(path) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{a, b}, {c, d}] -> :math.sqrt((a - c) ** 2 + (b - d) ** 2) end)
    |> Enum.sum()
  end

  # On the lattice many routes have exactly the same length and the route taken depends on the
  # order equally distant vertices are settled in (spaghetti iterates a Python set): there the
  # path must have the same ends and length; elsewhere it must be spaghetti's.
  defp assert_path(got, want, "lattice") do
    assert {hd(got), List.last(got)} == {hd(want), List.last(want)}
    assert_in_delta length_of(got), length_of(want), 1.0e-9
  end

  defp assert_path(got, want, _name), do: Reference.assert_close(flat(got), flat(want), 1.0e-9)

  for c <- @fixture["cases"] do
    @c c
    test "shortest paths: #{c["name"]} (#{length(c["paths"])})", ctx do
      {ntw, orig, dest} = ctx[@c["name"]]
      paths = Network.shortest_paths(ntw, orig, dest)
      assert length(paths) == length(@c["paths"])

      for {got, want} <- Enum.zip(paths, @c["paths"]) do
        assert got.pair == List.to_tuple(want["pair"])
        assert got.via == if(want["via"], do: List.to_tuple(want["via"]), else: :same_arc)
        assert_path(got.path, Enum.map(want["path"], &List.to_tuple/1), @c["name"])
      end
    end
  end
end
