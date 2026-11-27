defmodule Networkex.KFunctionTest do
  use ExUnit.Case, async: true

  alias Networkex.Network

  # A 10 x 10 lattice of unit blocks.
  @lines Enum.flat_map(0..10, fn i ->
           [for(j <- 0..10, do: {j, i}), for(j <- 0..10, do: {i, j})]
         end)

  setup_all do
    %{ntw: Network.new(@lines)}
  end

  test "simulated observations lie on the network and are reproducible by seed", %{ntw: ntw} do
    a = Network.simulate_observations(ntw, 50, seed: 42)
    assert a == Network.simulate_observations(ntw, 50, seed: 42)
    refute a == Network.simulate_observations(ntw, 50, seed: 43)
    assert a.points == a.snapped and a.dist_snapped == List.duplicate(0.0, 50)

    for {{x, y}, {i, j}, {di, dj}} <- Enum.zip([a.snapped, a.arcs, a.dist_to_vertex]) do
      assert x == Float.round(x) or y == Float.round(y)
      assert_in_delta di + dj, 1.0, 1.0e-9
      assert i < j
    end
  end

  test "explicit positions place observations along the arcs in draw order", %{ntw: ntw} do
    [first | _] = Network.arc_draw_order(ntw)
    pp = Network.simulate_observations(ntw, 2, positions: [0.25, 0.0])
    assert pp.arcs == [first, first]
    assert pp.dist_to_vertex == [{0.75, 0.25}, {1.0, 0.0}]

    assert_raise ArgumentError, fn -> Network.simulate_observations(ntw, 2, positions: [1.0]) end

    assert_raise ArgumentError, fn ->
      Network.simulate_observations(ntw, 1, positions: [1.0e6])
    end
  end

  test "a uniform pattern stays inside its envelope", %{ntw: ntw} do
    pp = Network.simulate_observations(ntw, 60, seed: 1)
    k = Network.global_auto_k(ntw, pp, nsteps: 8, permutations: 19, seed: 2, threshold: 0.0)

    assert k ==
             Network.global_auto_k(ntw, pp, nsteps: 8, permutations: 19, seed: 2, threshold: 0.0)

    assert length(k.simulated) == 19 and Enum.all?(k.simulated, &(length(&1) == 8))
    assert k.seed == 2
    drawn = Network.global_auto_k(ntw, pp, nsteps: 8, permutations: 3)
    assert is_integer(drawn.seed)
    assert drawn == Network.global_auto_k(ntw, pp, nsteps: 8, permutations: 3, seed: drawn.seed)
    assert_in_delta k.intensity, 60 / 220, 1.0e-12
    assert hd(k.xaxis) == 0.0 and List.last(k.xaxis) == k.upperbound

    # threshold 0 keeps the raw maximum as the upper envelope (and 0 as the lower).
    for {obs, up} <- Enum.zip(tl(k.observed), tl(k.upper_envelope)), do: assert(obs <= up * 1.5)
    assert Enum.all?(k.lower_envelope, &(&1 == 0.0))
  end

  test "a clustered pattern rises above the envelope at short distances", %{ntw: ntw} do
    clustered = Network.snap(ntw, for(i <- 1..30, do: {0.02 * i, 0.0}))

    k =
      Network.global_auto_k(ntw, clustered,
        nsteps: 5,
        permutations: 19,
        seed: 3,
        upperbound: 2.0,
        threshold: 0.0
      )

    assert Enum.at(k.observed, 1) > Enum.at(k.upper_envelope, 1)
  end

  test "options are validated", %{ntw: ntw} do
    pp = Network.simulate_observations(ntw, 5, seed: 1)

    for opts <- [
          [nsteps: 0],
          [permutations: -1],
          [threshold: "x"],
          [upperbound: -1],
          [simulations: []],
          [seed: 1.5],
          [bogus: 1]
        ] do
      assert_raise ArgumentError, fn -> Network.global_auto_k(ntw, pp, opts) end
    end

    assert_raise ArgumentError, fn -> Network.global_auto_k(ntw, pp, simulations: [[1.0]]) end
  end
end
