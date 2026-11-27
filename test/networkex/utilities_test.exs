defmodule Networkex.UtilitiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Networkex.Network

  @square [[{0, 0}, {2, 0}, {2, 1}, {0, 1}, {0, 0}]]

  test "splitting keeps the network length and snaps again" do
    ntw = Network.new(@square)
    split = Network.split_arcs(ntw, 0.5)
    assert length(split.arcs) == 12
    assert_in_delta Enum.sum(split.arc_lengths), 6.0, 1.0e-12
    assert split.graph.edges != []
    pp = Network.snap(split, [{0.3, -0.1}])
    assert pp.arcs == [{0, 4}]

    assert length(Network.split_arcs(ntw, 3, by: :count).arcs) == 12
    assert Network.split_arcs(ntw, 5).arcs == ntw.arcs
  end

  test "split options are validated" do
    ntw = Network.new(@square)

    for {split, opts} <- [
          {0, []},
          {-1.0, []},
          {:infinity, []},
          {"1", []},
          {1, [by: :count]},
          {2.5, [by: :count]},
          {1, [by: :x]},
          {1, [x: 1]}
        ] do
      assert_raise ArgumentError, fn -> Network.split_arcs(ntw, split, opts) end
    end

    for max_arcs <- [0, -1, 1.5, nil, :infinity] do
      assert_raise ArgumentError, ~r/:max_arcs must be a positive integer/, fn ->
        Network.split_arcs(ntw, 0.5, max_arcs: max_arcs)
      end
    end
  end

  test "splits that do not fit a float or a 32-bit count are argument errors" do
    ntw = Network.new([[{0, 0}, {1, 0}]])

    # 10^400 has no float; counts above 2^32 - 1 used to saturate in the NIF.
    for {split, opts, message} <- [
          {10 ** 400, [], ~r/the split distance must be a positive number of at most/},
          {10 ** 400, [by: :count], ~r/the split count must be an integer from 2 to 4294967295/},
          {2 ** 32, [by: :count], ~r/from 2 to 4294967295/},
          {2 ** 33, [by: :count], ~r/from 2 to 4294967295/}
        ] do
      assert_raise ArgumentError, message, fn -> Network.split_arcs(ntw, split, opts) end
    end

    # The largest float (2^1024 - 2^971), as an integer, is a distance longer than every arc.
    max_float = 2 ** 1024 - 2 ** 971
    assert max_float == trunc(:math.pow(2, 1023) * (2 - :math.pow(2, -52)))
    assert Network.split_arcs(ntw, max_float).arcs == ntw.arcs

    assert_raise ArgumentError, ~r/at most 1.7976931348623157e308/, fn ->
      Network.split_arcs(ntw, max_float + 1)
    end

    assert_raise ArgumentError, ~r/up to 8589934592 arcs, above max_arcs/, fn ->
      Network.split_arcs(Network.new(@square), 2 ** 31 - 1, by: :count)
    end
  end

  test "the NIF refuses a split count that is not a 32-bit integer of at least 2" do
    %Network{ref: ref} = Network.new([[{0, 0}, {1, 0}]])

    for count <- [2.0 ** 33, 2.5, -1.0, 1.0] do
      assert {:error, message} = Networkex.Native.network_split_arcs(ref, {"count", count}, 10)
      assert message =~ ~r/split count must be an integer from 2 to 4294967295|at least 2/
    end
  end

  test "lengths that overflow a float are argument errors" do
    # The coordinates are finite, their difference is not.
    assert_raise ArgumentError, ~r/is too long: its length overflows a float/, fn ->
      Network.new([[{-1.0e308, 0}, {1.0e308, 0}]])
    end

    # Each arc is finite, the network is not.
    assert_raise ArgumentError, ~r/its total length overflows a float/, fn ->
      Network.new([[{0, 0}, {1.0e308, 0}], [{0, 1}, {1.0e308, 1}]])
    end
  end

  describe "the size of a split" do
    # The arcs of @square are 2, 1, 2 and 1 long. The count allows each arc that is cut one
    # piece more than its length gives.

    test "a tiny split distance is refused at once instead of allocating the pieces" do
      ntw = Network.new(@square)

      # 2^-30 makes 2 * 2^31 + 2 * 2^30 pieces (and 4 to spare), some 6.4 billion arcs.
      {microseconds, error} =
        :timer.tc(fn ->
          assert_raise ArgumentError, fn -> Network.split_arcs(ntw, :math.pow(2, -30)) end
        end)

      assert error.message ==
               "the split would make up to 6442450948 arcs, above max_arcs (250000)"

      assert microseconds < 1_000_000
    end

    test "the default max_arcs is 250_000" do
      ntw = Network.new([[{0, 0}, {250_000, 0}]])

      assert_raise ArgumentError, ~r/up to 250001 arcs, above max_arcs \(250000\)/, fn ->
        Network.split_arcs(ntw, 1)
      end
    end

    test "max_arcs bounds the counted arcs, a split of exactly that many included" do
      ntw = Network.new(@square)

      for {split, opts, arcs, counted} <- [
            {0.5, [], 12, 16},
            {1.5, [], 6, 8},
            {3, [by: :count], 12, 16}
          ] do
        assert length(Network.split_arcs(ntw, split, [max_arcs: counted] ++ opts).arcs) == arcs

        message = "the split would make up to #{counted} arcs, above max_arcs (#{counted - 1})"

        assert_raise ArgumentError, message, fn ->
          Network.split_arcs(ntw, split, [max_arcs: counted - 1] ++ opts)
        end
      end
    end

    test "a split never returns more arcs than max_arcs, its tiny last pieces included" do
      # A tenth of 1 added ten times is 0.9999999999999999: as in spaghetti, the split ends in
      # an eleventh piece of about 1.1e-16.
      ntw = Network.new([[{0, 0}, {1, 0}]])

      assert_raise ArgumentError, ~r/up to 11 arcs, above max_arcs \(10\)/, fn ->
        Network.split_arcs(ntw, 10, by: :count, max_arcs: 10)
      end

      split = Network.split_arcs(ntw, 10, by: :count, max_arcs: 11)
      assert length(split.arcs) == 11
      assert Enum.min(split.arc_lengths) < 1.0e-15
    end

    property "a split that returns has at most max_arcs arcs" do
      check all(
              lines <- list_of(line(), min_length: 1, max_length: 3),
              split <- one_of([tuple({integer(2..40), constant(:count)}), distance()]),
              max_runs: 300
            ) do
        {value, by} = split
        ntw = Network.new(lines)
        arcs = length(Network.split_arcs(ntw, value, by: by).arcs)

        # One arc fewer than the result must be refused, never returned.
        if arcs > 1 do
          assert_raise ArgumentError, ~r/above max_arcs/, fn ->
            Network.split_arcs(ntw, value, by: by, max_arcs: arcs - 1)
          end
        end
      end
    end

    test "max_arcs is at most 2^26" do
      ntw = Network.new(@square)

      assert Network.split_arcs(ntw, 0.5, max_arcs: 2 ** 26).arcs ==
               Network.split_arcs(ntw, 0.5).arcs

      for max_arcs <- [2 ** 26 + 1, 2 ** 80] do
        assert_raise ArgumentError, ~r/positive integer up to 67108864/, fn ->
          Network.split_arcs(ntw, 0.5, max_arcs: max_arcs)
        end
      end
    end
  end

  defp line do
    gen all(points <- list_of(point(), min_length: 2, max_length: 4)) do
      points
    end
  end

  defp point do
    gen all(x <- float(min: 0.0, max: 100.0), y <- float(min: 0.0, max: 100.0)) do
      {x, y}
    end
  end

  defp distance do
    gen all(d <- float(min: 0.5, max: 30.0)) do
      {d, :distance}
    end
  end

  test "extracting a component keeps its arcs and renumbers its vertices" do
    ntw = Network.new([[{0, 0}, {1, 0}], [{5, 5}, {6, 5}, {6, 6}]])
    {c, ids} = Network.extract_component(ntw, 1)
    assert ids == [2, 3, 4]
    assert c.arcs == [{0, 1}, {1, 2}]
    assert c.vertices == [{5.0, 5.0}, {6.0, 5.0}, {6.0, 6.0}]
    assert c.network.fully_connected
    assert_raise ArgumentError, fn -> Network.extract_component(ntw, 2) end
  end

  test "a spanning tree has no cycles and a tree is returned unchanged" do
    tree = Network.spanning_tree(Network.new(@square))
    assert length(tree.arcs) == length(tree.vertices) - 1
    assert Enum.sum(tree.arc_lengths) == 4.0
    assert Enum.sum(Network.spanning_tree(Network.new(@square), maximum: true).arc_lengths) == 5.0
    assert Network.spanning_tree(tree) == tree
    assert_raise ArgumentError, fn -> Network.spanning_tree(tree, maximum: 1) end
  end

  test "lattices" do
    lines = Network.regular_lattice({0, 0, 3, 3}, 2, exterior: true)
    ntw = Network.new(lines)
    assert length(ntw.vertices) == 16 and length(ntw.arcs) == 24
    assert length(Network.regular_lattice({0, 0, 3, 3}, 2)) == 12
    assert_raise ArgumentError, fn -> Network.regular_lattice({0, 0, 1, 1}, 1, nv: 0) end
    assert_raise FunctionClauseError, fn -> Network.regular_lattice({0, 0, 1}, 1) end
  end
end
