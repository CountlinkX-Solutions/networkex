defmodule Networkex.Shapefile do
  @moduledoc false
  # Minimal Shapefile readers for the test data (polylines and points, no M or Z).

  def read_lines(path) do
    for <<3::little-32, _box::binary-size(32), parts::little-32, points::little-32, rest::binary>> <-
          records(path) do
      <<starts::binary-size(parts * 4), coords::binary-size(points * 16)>> = rest
      starts = for <<s::little-32 <- starts>>, do: s
      pts = for <<x::little-float-64, y::little-float-64 <- coords>>, do: {x, y}

      starts
      |> Enum.zip(Enum.drop(starts, 1) ++ [points])
      |> Enum.map(fn {a, b} -> Enum.slice(pts, a, b - a) end)
    end
    |> Enum.concat()
  end

  def read_points(path) do
    for <<1::little-32, x::little-float-64, y::little-float-64>> <- records(path), do: {x, y}
  end

  defp records(path) do
    <<_header::binary-size(100), body::binary>> = File.read!(path)
    parse(body, [])
  end

  defp parse(<<_n::big-32, len::big-32, content::binary-size(len * 2), rest::binary>>, acc),
    do: parse(rest, [content | acc])

  defp parse(<<>>, acc), do: Enum.reverse(acc)
end
