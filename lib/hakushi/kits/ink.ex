defmodule Hakushi.Kits.Ink do
  @moduledoc """
  The kit of ink: drawing on the paper with a pen, over anything on the
  canvas (annotate, sketch, circle a node, write by hand), with a
  highlighter, an eraser of whole strokes, and a lasso that selects
  strokes and nodes alike.

      <.canvas id="board" graph={@graph} kits={[Hakushi.Kits.Notes, Hakushi.Kits.Ink]} on_change={&save/2} />

  The canvas gets a bar of the kit's tools (`c:Hakushi.Kit.tools/1`):
  the pointer, the pen and the highlighter with their colours and widths,
  the eraser and the lasso. The pen's line is smoothed as it is drawn,
  thinner and thicker with a stylus's pressure, and sharp at any zoom;
  when the pen lifts, its points are simplified and the stroke is a node.

  A stroke is a node of type `"ink-stroke"`: its box is around the line,
  and its data is the line's points, relative to the box:

      %{
        "tool" => "pen",
        "color" => "ink",
        "size" => 4,
        "points" => [[12.5, 8, 0.42], [14, 9.5, 0.5], ...]
      }

  A point is `[x, y, pressure]`, the pressure from 0 to 1 (`0.5` for a
  mouse). The colours are `colors/0`, the tools `"pen"` and
  `"highlighter"`. A stroke moves, goes in a group (drawn over a frame,
  it is in it), copies, deletes and undoes as any node, through the
  rules and `on_change`; it has no handles, so no edges.

  On a shared canvas, the others see a stroke as it is drawn: it goes
  in the person's awareness, as a drag does, and becomes a change when
  the pen lifts. An agent draws with `draw_on_canvas`
  (`Hakushi.Issho.tools/0`), and the people see its pen go.
  """

  use Hakushi.Kit

  alias Hakushi.Ink

  @colors ~w(ink red orange yellow green blue violet)
  @tools %{
    "pen" => %{sizes: [2, 4, 8], size: 4, color: "ink"},
    "highlighter" => %{sizes: [12, 20, 32], size: 20, color: "yellow"}
  }
  # The most points of a stroke: the browser simplifies a stroke to a few
  # hundred; more are thinned.
  @max_points 2_000
  @max_size 64

  @doc "The colours of ink, in the order of the bar."
  @spec colors() :: [String.t()]
  def colors, do: @colors

  @impl true
  def name, do: "ink"

  @impl true
  def title(messages), do: messages["kitInk"]

  @impl true
  def icon, do: "pen"

  @impl true
  def types, do: ["ink-stroke"]

  # Ink is drawn with the tools of the bar on the canvas, not dropped.
  @impl true
  def elements(_messages), do: []

  @impl true
  def new_node(_item, _at, _messages), do: nil

  @impl true
  def tools(messages) do
    [
      %{tool: "pen", mode: "draw", label: messages["inkPen"], icon: "pen", key: "p"}
      |> Map.merge(options("pen")),
      %{
        tool: "highlighter",
        mode: "draw",
        label: messages["inkHighlighter"],
        icon: "highlighter",
        key: "h"
      }
      |> Map.merge(options("highlighter")),
      %{
        tool: "eraser",
        mode: "erase",
        label: messages["inkEraser"],
        icon: "eraser",
        key: "e",
        types: types()
      },
      %{tool: "lasso", mode: "lasso", label: messages["inkLasso"], icon: "lasso", key: "l"}
    ]
  end

  defp options(tool) do
    %{sizes: sizes, size: size, color: color} = @tools[tool]
    %{colors: @colors, sizes: sizes, size: size, color: color, flat: tool == "highlighter"}
  end

  @impl true
  def drawn(tool, params, _messages) do
    case stroke(params["points"], tool: tool, color: params["color"], size: params["size"]) do
      {:ok, node} -> node
      :error -> nil
    end
  end

  @doc """
  A stroke's node, from its points on the canvas (`[x, y, pressure]` or
  `[x, y]`): its box around them, and its points relative to it. Gives
  `{:ok, node}`, or `:error` for points or a tool it does not draw.

  Options: `:tool` (`"pen"`, the default, or `"highlighter"`), `:color`
  (one of `colors/0`) and `:size` (the line's width at a pressure of
  0.5), each the tool's own unless given.

      {:ok, node} = Hakushi.Kits.Ink.stroke([[0, 0], [40, 10], [80, 0]], color: "red")
  """
  @spec stroke([Ink.point()], keyword()) :: {:ok, map()} | :error
  def stroke(points, opts \\ []) do
    tool = opts[:tool] || "pen"

    with %{} = defaults <- @tools[tool],
         {:ok, points} <- points(points) do
      color = if opts[:color] in @colors, do: opts[:color], else: defaults.color
      size = size(opts[:size], defaults.size)
      flat = tool == "highlighter"
      reach = Ink.reach(size, flat) + 1
      {xs, ys} = {Enum.map(points, &Enum.at(&1, 0)), Enum.map(points, &Enum.at(&1, 1))}
      {x, y} = {tenth(Enum.min(xs) - reach), tenth(Enum.min(ys) - reach)}

      {:ok,
       %{
         type: "ink-stroke",
         x: x,
         y: y,
         width: tenth(Enum.max(xs) + reach - x),
         height: tenth(Enum.max(ys) + reach - y),
         data: %{
           "tool" => tool,
           "color" => color,
           "size" => size,
           "points" => Enum.map(points, fn [px, py, p] -> [tenth(px - x), tenth(py - y), p] end)
         }
       }}
    else
      _other -> :error
    end
  end

  defp points(list) when is_list(list) and list != [] do
    if Enum.all?(list, &point?/1) do
      {:ok, list |> thin() |> Enum.map(&pressured/1)}
    else
      :error
    end
  end

  defp points(_other), do: :error

  defp point?([x, y]) when is_number(x) and is_number(y), do: true
  defp point?([x, y, p]) when is_number(x) and is_number(y) and is_number(p), do: true
  defp point?(_other), do: false

  defp pressured([x, y]), do: [x, y, 0.5]

  defp pressured([x, y, p]),
    do: [x, y, p |> max(0) |> min(1) |> Kernel.*(100) |> round() |> Kernel./(100)]

  # A stroke of more points than a stroke has: every so many of them, and
  # its last.
  defp thin(list) do
    count = length(list)

    if count <= @max_points do
      list
    else
      every = div(count + @max_points - 2, @max_points - 1)
      Enum.take_every(list, every) ++ [List.last(list)]
    end
  end

  defp size(size, _default) when is_number(size) and size > 0, do: min(size, @max_size)
  defp size(_size, default), do: default

  defp tenth(n), do: Float.round(n * 1.0, 1)

  @impl true
  def label(_node, messages), do: messages["drawing"]

  @impl true
  def node(assigns) do
    data = assigns.node.data
    tool = get(data, "tool") || "pen"
    size = get(data, "size") || 4
    points = get(data, "points") || []
    flat = tool == "highlighter"

    assigns =
      assign(assigns,
        tool: tool,
        color: get(data, "color") || "ink",
        width: assigns.node.width || 1,
        height: assigns.node.height || 1,
        outline: Ink.outline(points, size, flat),
        line: Ink.centerline(points),
        aim: max(size, 12)
      )

    ~H"""
    <svg
      class="hakushi-ink"
      data-tool={@tool}
      data-color={@color}
      data-hakushi-near
      width={@width}
      height={@height}
      viewBox={"0 0 #{@width} #{@height}"}
      aria-hidden="true"
    >
      <path class="hakushi-ink-aim" d={@line} stroke-width={@aim} />
      <path class="hakushi-ink-line" d={@outline} />
    </svg>
    """
  end

  @impl true
  def edit(_action, _params, _data), do: :error
end
