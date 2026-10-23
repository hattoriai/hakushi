defmodule Hakushi.Ink do
  @moduledoc """
  The geometry of a stroke of ink (`Hakushi.Kits.Ink`): its outline, as
  the `d` of an SVG path, whose width follows the pen's pressure.

  The browser draws a stroke in progress with the same outline (the
  bundle's `ink.ts`): the stroke a person sees as they draw it, and the
  node it becomes when the pen lifts, are the same shape.

  A point is `[x, y, pressure]`, the pressure from 0 to 1 (`0.5` for a
  pointer with none, a mouse); `[x, y]` is a point of no pressure.
  """

  @flat 0.5

  @typedoc "A point of a stroke: `[x, y, pressure]` or `[x, y]`."
  @type point :: [number()]

  @doc """
  The outline of a stroke: the points on each side of its line, as far
  from it as the pressure says (thinner with less), joined by curves
  through their middles, with a round cap at each end. `flat` (a
  highlighter) keeps one width.
  """
  @spec outline([point()], number(), boolean()) :: String.t()
  def outline(points, size, flat \\ false) do
    points = distinct(points)
    radius = fn point -> radius(point, size, flat) end

    case points do
      [] ->
        ""

      [[x, y | _] = point] ->
        r = radius.(point)
        rr = fmt(r)

        "M#{fmt(x - r)} #{fmt(y)}A#{rr} #{rr} 0 1 0 #{fmt(x + r)} #{fmt(y)}" <>
          "A#{rr} #{rr} 0 1 0 #{fmt(x - r)} #{fmt(y)}Z"

      points ->
        sides(points, radius)
    end
  end

  defp sides(points, radius) do
    pts = List.to_tuple(points)
    n = tuple_size(pts)

    {left, right, _tangent} =
      Enum.reduce(0..(n - 1), {[], [], {1, 0}}, fn i, {left, right, tangent} ->
        [ax, ay | _] = elem(pts, max(0, i - 1))
        [bx, by | _] = elem(pts, min(n - 1, i + 1))
        {dx, dy} = {bx - ax, by - ay}
        length = :math.sqrt(dx * dx + dy * dy)
        {tx, ty} = if length > 0, do: {dx / length, dy / length}, else: tangent
        [x, y | _] = point = elem(pts, i)
        r = radius.(point)
        {[{x - ty * r, y + tx * r} | left], [{x + ty * r, y - tx * r} | right], {tx, ty}}
      end)

    left = left |> Enum.reverse() |> List.to_tuple()
    right = right |> Enum.reverse() |> List.to_tuple()
    finish = fmt(radius.(elem(pts, n - 1)))
    start = fmt(radius.(elem(pts, 0)))

    IO.iodata_to_binary([
      "M",
      at(elem(left, 0)),
      for(i <- 1..(n - 2)//1, do: ["Q", at(elem(left, i)), " ", at(mid(left, i, i + 1))]),
      ["L", at(elem(left, n - 1)), "A#{finish} #{finish} 0 0 0 ", at(elem(right, n - 1))],
      for(i <- (n - 2)..1//-1, do: ["Q", at(elem(right, i)), " ", at(mid(right, i, i - 1))]),
      ["L", at(elem(right, 0)), "A#{start} #{start} 0 0 0 ", at(elem(left, 0)), "Z"]
    ])
  end

  defp mid(side, a, b) do
    {ax, ay} = elem(side, a)
    {bx, by} = elem(side, b)
    {(ax + bx) / 2, (ay + by) / 2}
  end

  defp at({x, y}), do: [fmt(x), " ", fmt(y)]

  @doc "The line through a stroke's points, as the `d` of an SVG path: to aim at it."
  @spec centerline([point()]) :: String.t()
  def centerline(points) do
    points
    |> Enum.with_index()
    |> Enum.map_join(fn {[x, y | _], i} ->
      "#{if i == 0, do: "M", else: "L"}#{fmt(x)} #{fmt(y)}"
    end)
  end

  @doc "How far a stroke's outline reaches from its points: the most it is wide, halved."
  @spec reach(number(), boolean()) :: number()
  def reach(size, true), do: size / 2
  def reach(size, false), do: size * 0.75

  @doc """
  A number as a path writes it: to a tenth, halves away from zero, without
  a `.0` (as the browser writes it).
  """
  @spec fmt(number()) :: String.t()
  def fmt(value) do
    tenths = round(abs(value) * 10)
    sign = if value < 0 and tenths != 0, do: "-", else: ""

    case rem(tenths, 10) do
      0 -> sign <> Integer.to_string(div(tenths, 10))
      r -> sign <> Integer.to_string(div(tenths, 10)) <> "." <> Integer.to_string(r)
    end
  end

  defp radius(_point, size, true), do: size / 2
  defp radius([_x, _y, p | _], size, false) when is_number(p), do: size / 2 * (0.5 + clamp(p))
  defp radius(_point, size, false), do: size / 2 * (0.5 + @flat)

  defp clamp(p), do: p |> max(0) |> min(1)

  # Points that follow one another at the same place are one.
  defp distinct(points) do
    points
    |> Enum.reduce([], fn
      [x, y | _] = point, [[lx, ly | _] | _] = acc ->
        if abs(lx - x) > 0.01 or abs(ly - y) > 0.01, do: [point | acc], else: acc

      point, [] ->
        [point]
    end)
    |> Enum.reverse()
  end
end
