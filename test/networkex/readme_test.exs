defmodule Networkex.ReadmeTest do
  # The README quickstart is written as `iex>` examples, so it runs as doctests and the code a
  # reader copies is the code the suite checks.
  use ExUnit.Case, async: true

  @readme Path.expand("../../README.md", __DIR__)

  doctest_file(@readme)

  test "the README quickstart is made of doctests" do
    quickstart =
      @readme
      |> File.read!()
      |> String.split(~r/^## /m)
      |> Enum.find(&String.starts_with?(&1, "Quickstart"))

    assert quickstart, "README.md has no Quickstart section"
    assert quickstart =~ ~r/^iex> /m, "the README quickstart has no iex> examples"
  end
end
