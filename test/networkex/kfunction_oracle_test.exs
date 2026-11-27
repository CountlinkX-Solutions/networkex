defmodule Networkex.KFunctionOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference, Shapefile}

  @fixture Reference.load!("network/kfunction.json")["cases"]
  @data Path.expand("../reference/data", __DIR__)

  setup_all do
    ntw = Network.new(Shapefile.read_lines(Path.join(@data, "streets.shp")))

    patterns =
      Map.new(["schools", "crimes"], fn name ->
        {name, Network.snap(ntw, Shapefile.read_points(Path.join(@data, "#{name}.shp")))}
      end)

    %{ntw: ntw, patterns: patterns}
  end

  defp pairs(rows), do: Enum.map(rows, &List.to_tuple/1)

  test "arcs are drawn in spaghetti's order of first appearance", %{ntw: ntw} do
    assert Enum.map(Network.arc_draw_order(ntw), &Tuple.to_list/1) == @fixture["arc_order"]
  end

  for {sim, i} <- Enum.with_index(@fixture["simulate"]) do
    @sim sim
    test "simulate_observations #{i} (#{sim["count"]} draws) replays spaghetti", %{ntw: ntw} do
      pp = Network.simulate_observations(ntw, @sim["count"], positions: @sim["positions"])
      assert pp.arcs == pairs(@sim["arcs"])
      Reference.assert_close(flat(pp.snapped), List.flatten(@sim["coords"]), 1.0e-9)
      Reference.assert_close(flat(pp.dist_to_vertex), List.flatten(@sim["to_vertex"]), 1.0e-9)
      assert pp.dist_snapped == List.duplicate(0.0, @sim["count"])
    end
  end

  for {case_, i} <- Enum.with_index(@fixture["global_auto_k"]) do
    @case case_
    test "GlobalAutoK #{i}: #{case_["pattern"]}, #{case_["nsteps"]} steps, threshold #{case_["threshold"]}",
         %{ntw: ntw, patterns: patterns} do
      c = @case

      opts =
        [
          nsteps: c["nsteps"],
          permutations: c["permutations"],
          threshold: c["threshold"],
          simulations: c["simulations"]
        ] ++ if(c["upperbound_option"], do: [upperbound: c["upperbound_option"]], else: [])

      k = Network.global_auto_k(ntw, patterns[c["pattern"]], opts)
      Reference.assert_close([k.intensity, k.upperbound], [c["lam"], c["upperbound"]], 1.0e-12)
      Reference.assert_close(k.xaxis, c["xaxis"], 1.0e-9)
      Reference.assert_close(k.observed, c["observed"], 1.0e-9)
      Reference.assert_close(List.flatten(k.simulated), List.flatten(c["sim"]), 1.0e-9)
      Reference.assert_close(k.upper_envelope, c["upper"], 1.0e-9)
      Reference.assert_close(k.lower_envelope, c["lower"], 1.0e-9)
    end
  end

  defp flat(pairs), do: Enum.flat_map(pairs, &Tuple.to_list/1)
end
