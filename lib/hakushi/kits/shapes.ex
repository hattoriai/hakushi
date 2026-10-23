defmodule Hakushi.Kits.Shapes do
  @moduledoc """
  The kit of plain shapes: rectangles, ellipses, diamonds, triangles, text
  and lines, for diagrams, wireframes and whiteboards with no `:node` slot
  of the app's.

      <.canvas id="board" graph={@graph} kits={[Hakushi.Kits.Shapes]} on_change={&save/2} />

  The canvas gets a bar of the kit's tools (`c:Hakushi.Kit.tools/1`): a
  shape is drawn by dragging on the paper with its tool (Shift for a
  square or a circle), text by a click, and a line from a point to a
  point. A line from a shape to a shape is an edge between them, which
  follows them; a line elsewhere is a node of its own.

  A shape is a node of type `"shape"`, which resizes by its corners and
  sides, rotates by its knob, takes text on a double click (centred, and
  wrapped), and has a handle on each side for edges. Its data is its
  kind, its text and its style:

      %{
        "kind" => "rect",       # "rect", "ellipse", "diamond", "triangle" or "text"
        "text" => "Ship it",
        "fill" => "blue",       # a colour of colors/0, or "none"
        "stroke" => "ink",
        "width" => 2,           # the width of the stroke: 1, 2 or 4
        "dash" => false,
        "radius" => 8,          # a rectangle's corners: 0 or 8
        "size" => "m",          # the text's: "s", "m" or "l"
        "align" => "center",    # the text's: "left", "center" or "right"
        "rotation" => 0         # in degrees
      }

  A line is a node of type `"shape-line"`, whose data is its ends,
  relative to its box, and its style (`"stroke"`, `"width"`, `"dash"`, and
  `"arrow"`: `"end"`, `"both"` or `"none"`):

      %{"from" => [8, 8], "to" => [180, 64], "stroke" => "ink", "width" => 2, "arrow" => "end"}

  The style of the shapes selected changes from a panel over them
  (`c:Hakushi.Kit.styles/1`), in one change.

  ## The colours

  The colours are the theme's (`--hakushi-shape-<name>`, see the Theming
  guide): a fill is a tint of its colour, a stroke the colour itself. An
  app adds its own, by name, with their custom properties:

      config :hakushi, Hakushi.Kits.Shapes, colors: ["brand"]

      .hakushi { --hakushi-shape-brand: #e84a1c; }

  ## Markdown

  The shapes are a Mermaid flowchart: a rectangle a box (`["..."]`, or
  `("...")` with round corners), an ellipse a circle (`(("..."))`), a
  diamond a rhombus (`{"..."}`), a triangle a trapezoid (`[/"..."\\]`),
  text a box of the class `text`, with the edges between them. The
  style and the place of each are kept in comments, so that the canvas
  comes back as it was. Lines of their own are not in it.
  """

  use Hakushi.Kit

  alias Hakushi.{Graph, Mermaid}

  @kinds ~w(rect ellipse diamond triangle text)
  @colors ~w(ink gray blue green yellow red violet)
  @widths [1, 2, 4]
  @sizes ~w(s m l)
  @aligns ~w(left center right)
  @arrows ~w(end both none)
  @text_max 2_000
  # A shape drawn by a click, or smaller than this, has this size.
  @min 8
  @defaults %{
    "rect" => {160, 96},
    "ellipse" => {140, 96},
    "diamond" => {140, 112},
    "triangle" => {140, 112},
    "text" => {180, 40}
  }

  @doc """
  The colours of shapes: the theme's, then the app's
  (`config :hakushi, Hakushi.Kits.Shapes, colors: [...]`).
  """
  @spec colors() :: [String.t()]
  def colors do
    own = Application.get_env(:hakushi, __MODULE__, []) |> Keyword.get(:colors, [])
    Enum.uniq(@colors ++ Enum.map(own, &to_string/1))
  end

  @doc "The kinds of shapes."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @impl true
  def name, do: "shapes"

  @impl true
  def title(messages), do: messages["kitShapes"]

  @impl true
  def icon, do: "shapes"

  @impl true
  def types, do: ["shape", "shape-line"]

  # Shapes are drawn with the tools of the bar on the canvas; a rectangle
  # may be dropped from the kit's items too.
  @impl true
  def elements(messages),
    do: [%{item: "rect", label: messages["shapeRect"], icon: "square"}]

  @impl true
  def new_node("rect", {x, y}, _messages), do: shape("rect", [x, y, 0, 0], %{})
  def new_node(_item, _at, _messages), do: nil

  @impl true
  def resizable?("shape"), do: true
  def resizable?(_type), do: false

  @impl true
  def tools(messages) do
    [
      %{tool: "rect", mode: "box", label: messages["shapeRect"], icon: "square", key: "r"},
      %{tool: "ellipse", mode: "box", label: messages["shapeEllipse"], icon: "circle", key: "o"},
      %{tool: "diamond", mode: "box", label: messages["shapeDiamond"], icon: "diamond", key: "d"},
      %{
        tool: "triangle",
        mode: "box",
        label: messages["shapeTriangle"],
        icon: "triangle",
        key: nil
      },
      %{tool: "text", mode: "box", label: messages["shapeText"], icon: "type", key: "t"},
      %{tool: "line", mode: "line", label: messages["shapeLine"], icon: "arrow", key: "l"}
    ]
  end

  @impl true
  def styles(messages) do
    colors = Enum.map(colors(), &%{value: &1, label: color_label(messages, &1)})
    none = %{value: "none", label: messages["styleNone"]}

    [
      %{key: "fill", label: messages["styleFill"], kind: "color", options: [none | colors]},
      %{key: "stroke", label: messages["styleStroke"], kind: "color", options: [none | colors]},
      %{
        key: "width",
        label: messages["styleWidth"],
        kind: "width",
        options: Enum.map(@widths, &%{value: &1, label: word(messages, "styleWidthN", "#{&1}")})
      },
      %{
        key: "dash",
        label: messages["styleDash"],
        kind: "choice",
        options: [
          %{value: false, label: messages["styleSolid"]},
          %{value: true, label: messages["styleDashed"]}
        ]
      },
      %{
        key: "radius",
        label: messages["styleCorners"],
        kind: "choice",
        options: [
          %{value: 0, label: messages["styleSharp"]},
          %{value: 8, label: messages["styleRound"]}
        ]
      },
      %{
        key: "size",
        label: messages["styleTextSize"],
        kind: "choice",
        options: [
          %{value: "s", label: "S"},
          %{value: "m", label: "M"},
          %{value: "l", label: "L"}
        ]
      },
      %{
        key: "align",
        label: messages["styleAlign"],
        kind: "choice",
        options: [
          %{value: "left", label: messages["styleLeft"]},
          %{value: "center", label: messages["styleCenter"]},
          %{value: "right", label: messages["styleRight"]}
        ]
      },
      %{
        key: "arrow",
        label: messages["styleArrow"],
        kind: "choice",
        options: [
          %{value: "end", label: "→"},
          %{value: "both", label: "↔"},
          %{value: "none", label: "—"}
        ]
      }
    ]
  end

  defp color_label(messages, name),
    do: messages["color" <> String.capitalize(name)] || String.capitalize(name)

  @impl true
  def drawn("line", %{"points" => [[x1, y1], [x2, y2]]} = params, _messages)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    {:ok, node} = line({x1, y1}, {x2, y2}, style(params["style"], line_defaults()))
    node
  end

  def drawn(kind, %{"box" => [x, y, w, h]} = params, _messages)
      when kind in @kinds and is_number(x) and is_number(y) and is_number(w) and is_number(h) do
    shape(kind, [x, y, w, h], params["style"])
  end

  def drawn(_tool, _params, _messages), do: nil

  @doc """
  A shape's node, at a box of the canvas (`[x, y, width, height]`; a box
  smaller than a few pixels gets the kind's size), with its style (the
  keys of the moduledoc; the kind's own unless given) and its `"text"`.

      Hakushi.Kits.Shapes.shape("diamond", [0, 0, 140, 112], %{"text" => "Paid?"})
  """
  @spec shape(String.t(), [number()], map() | nil) :: map()
  def shape(kind, [x, y, w, h], style) when kind in @kinds do
    {dw, dh} = @defaults[kind]
    {w, h} = if abs(w) < @min or abs(h) < @min, do: {dw, dh}, else: {abs(w), abs(h)}
    style = style || %{}

    data =
      kind
      |> shape_defaults()
      |> Map.merge(%{"kind" => kind, "text" => text(get(style, "text"))})
      |> then(&style(style, &1))

    %{type: "shape", x: round1(x), y: round1(y), width: round1(w), height: round1(h), data: data}
  end

  @doc """
  A line's node, from a point of the canvas to another, with its style
  (`"stroke"`, `"width"`, `"dash"`, `"arrow"`). Gives `{:ok, node}`.
  """
  @spec line({number(), number()}, {number(), number()}, map()) :: {:ok, map()}
  def line({x1, y1}, {x2, y2}, style \\ %{}) do
    pad = 12
    {x, y} = {min(x1, x2) - pad, min(y1, y2) - pad}

    {:ok,
     %{
       type: "shape-line",
       x: round1(x),
       y: round1(y),
       width: round1(abs(x2 - x1) + pad * 2),
       height: round1(abs(y2 - y1) + pad * 2),
       data:
         style
         |> style(line_defaults())
         |> Map.merge(%{
           "from" => [round1(x1 - x), round1(y1 - y)],
           "to" => [round1(x2 - x), round1(y2 - y)]
         })
     }}
  end

  defp shape_defaults("text"),
    do: %{
      "fill" => "none",
      "stroke" => "none",
      "width" => 2,
      "dash" => false,
      "radius" => 0,
      "size" => "m",
      "align" => "left",
      "rotation" => 0
    }

  defp shape_defaults(_kind),
    do: %{
      "fill" => "blue",
      "stroke" => "blue",
      "width" => 2,
      "dash" => false,
      "radius" => 8,
      "size" => "m",
      "align" => "center",
      "rotation" => 0
    }

  defp line_defaults,
    do: %{"stroke" => "ink", "width" => 2, "dash" => false, "arrow" => "end"}

  # The keys of a style that are good, over the data's.
  defp style(style, data) when is_map(style) do
    Enum.reduce(style, data, fn {key, value}, data ->
      case valid(to_string(key), value) do
        {:ok, key, value} -> Map.put(data, key, value)
        :error -> data
      end
    end)
  end

  defp style(_style, data), do: data

  defp valid(key, value) when key in ["fill", "stroke"] and is_binary(value) do
    if value == "none" or value in colors(), do: {:ok, key, value}, else: :error
  end

  defp valid("width", value) when value in @widths, do: {:ok, "width", value}
  defp valid("dash", value) when is_boolean(value), do: {:ok, "dash", value}
  defp valid("radius", value) when value in [0, 8], do: {:ok, "radius", value}
  defp valid("size", value) when value in @sizes, do: {:ok, "size", value}
  defp valid("align", value) when value in @aligns, do: {:ok, "align", value}
  defp valid("arrow", value) when value in @arrows, do: {:ok, "arrow", value}

  defp valid("rotation", value) when is_number(value),
    do: {:ok, "rotation", value |> round() |> Integer.mod(360)}

  defp valid(_key, _value), do: :error

  defp text(text) when is_binary(text), do: text |> String.slice(0, @text_max)
  defp text(_text), do: ""

  # To a tenth, and a whole number when it is one.
  defp round1(n) do
    r = Float.round(n * 1.0, 1)
    if r == trunc(r), do: trunc(r), else: r
  end

  @impl true
  def edit("text", %{"value" => value}, data) when is_binary(value),
    do: {:ok, Map.put(data, "text", text(String.trim_trailing(value)))}

  def edit("style", %{"style" => style}, data) when is_map(style) do
    # Only the keys of the node's kind: a line has no fill, a shape no arrow.
    keys =
      if Map.has_key?(data, "from"),
        do: ~w(stroke width dash arrow),
        else: ~w(fill stroke width dash radius size align)

    {:ok, style(Map.take(style, keys), data)}
  end

  def edit("rotate", %{"value" => value}, data) when is_number(value),
    do: {:ok, style(%{"rotation" => value}, data)}

  def edit(_action, _params, _data), do: :error

  @impl true
  def label(%{type: "shape-line"}, messages), do: messages["shapeLine"]

  def label(node, messages) do
    kind = get(node.data, "kind") || "rect"
    word = messages["shape" <> String.capitalize(kind)] || kind

    case get(node.data, "text") do
      text when is_binary(text) and text != "" -> "#{word}: #{text}"
      _none -> word
    end
  end

  @impl true
  def node(%{node: %{type: "shape-line"}} = assigns) do
    data = assigns.node.data

    assigns =
      assign(assigns,
        from: get(data, "from") || [0, 0],
        to: get(data, "to") || [0, 0],
        stroke: get(data, "stroke") || "ink",
        width: get(data, "width") || 2,
        dash: get(data, "dash") == true,
        arrow: get(data, "arrow") || "end",
        box_width: assigns.node.width || 1,
        box_height: assigns.node.height || 1,
        marker: "#{assigns.canvas}-shape-arrow-#{assigns.node.id}"
      )

    ~H"""
    <svg
      class="hakushi-shape-line"
      data-hakushi-style={JSON.encode!(%{stroke: @stroke, width: @width, dash: @dash, arrow: @arrow})}
      width={@box_width}
      height={@box_height}
      viewBox={"0 0 #{@box_width} #{@box_height}"}
      style={"--hakushi-shape-stroke: #{color(@stroke)}"}
      aria-hidden="true"
    >
      <defs>
        <marker id={@marker} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M0,0L10,5L0,10z" />
        </marker>
      </defs>
      <line class="hakushi-shape-line-aim" x1={Enum.at(@from, 0)} y1={Enum.at(@from, 1)} x2={Enum.at(@to, 0)} y2={Enum.at(@to, 1)} />
      <line
        class="hakushi-shape-line-stroke"
        x1={Enum.at(@from, 0)}
        y1={Enum.at(@from, 1)}
        x2={Enum.at(@to, 0)}
        y2={Enum.at(@to, 1)}
        stroke-width={@width}
        stroke-dasharray={@dash && "#{@width * 4} #{@width * 3}"}
        marker-end={@arrow in ["end", "both"] && "url(##{@marker})"}
        marker-start={@arrow == "both" && "url(##{@marker})"}
      />
    </svg>
    """
  end

  def node(assigns) do
    kind = get(assigns.node.data, "kind") || "rect"
    # The node's data over its kind's: a shape of an older or a hand-made graph has them all.
    data = kind |> shape_defaults() |> Map.merge(Hakushi.Kit.stringify(assigns.node.data))
    {dw, dh} = @defaults[kind] || {160, 96}
    stroke_width = if data["stroke"] == "none", do: 0, else: data["width"]

    assigns =
      assign(assigns,
        kind: kind,
        text: data["text"] || "",
        fill: data["fill"],
        stroke: data["stroke"],
        stroke_width: stroke_width,
        dash: data["dash"] == true,
        radius: data["radius"],
        size: data["size"],
        align: data["align"],
        rotation: data["rotation"],
        w: assigns.node.width || dw,
        h: assigns.node.height || dh,
        inset: stroke_width / 2,
        style: Map.take(data, style_keys(kind))
      )

    ~H"""
    <div
      class="hakushi-shape"
      data-kind={@kind}
      data-hakushi-rotate
      data-hakushi-style={JSON.encode!(@style)}
      style={"--hakushi-rotation: #{@rotation}deg; --hakushi-shape-fill: #{tint(@fill)}; --hakushi-shape-stroke: #{color(@stroke)}"}
    >
      <svg :if={@kind != "text"} class="hakushi-shape-outline" viewBox={"0 0 #{@w} #{@h}"} preserveAspectRatio="none" aria-hidden="true">
        <.outline
          kind={@kind}
          w={@w}
          h={@h}
          inset={@inset}
          radius={@radius}
          stroke_width={@stroke_width}
          dash={@dash}
        />
      </svg>
      <div
        class="hakushi-shape-text"
        data-hakushi-text={@text}
        data-size={@size}
        data-align={@align}
        data-empty={@text == "" && "true"}
      >{@text}</div>
      <.handle :if={@kind != "text"} side={:top} />
      <.handle :if={@kind != "text"} side={:right} />
      <.handle :if={@kind != "text"} side={:bottom} />
      <.handle :if={@kind != "text"} side={:left} />
    </div>
    """
  end

  # The style a kind of shape has: corners for a rectangle; a text, no
  # stroke of its own.
  defp style_keys("rect"), do: ~w(fill stroke width dash radius size align)
  defp style_keys("text"), do: ~w(fill size align)
  defp style_keys(_kind), do: ~w(fill stroke width dash size align)

  attr :kind, :string, required: true
  attr :w, :any, required: true
  attr :h, :any, required: true
  attr :inset, :any, required: true
  attr :radius, :any, required: true
  attr :stroke_width, :any, required: true
  attr :dash, :boolean, required: true

  defp outline(%{kind: "ellipse"} = assigns) do
    ~H"""
    <ellipse
      cx={@w / 2}
      cy={@h / 2}
      rx={max(@w / 2 - @inset, 0)}
      ry={max(@h / 2 - @inset, 0)}
      stroke-width={@stroke_width}
      stroke-dasharray={@dash && "#{@stroke_width * 4} #{@stroke_width * 3}"}
    />
    """
  end

  defp outline(%{kind: kind} = assigns) when kind in ["diamond", "triangle"] do
    {w, h, i} = {assigns.w, assigns.h, assigns.inset}

    points =
      case kind do
        "diamond" -> [{w / 2, i}, {w - i, h / 2}, {w / 2, h - i}, {i, h / 2}]
        "triangle" -> [{w / 2, i}, {w - i, h - i}, {i, h - i}]
      end

    assigns = assign(assigns, :points, Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end))

    ~H"""
    <polygon
      points={@points}
      stroke-width={@stroke_width}
      stroke-linejoin="round"
      stroke-dasharray={@dash && "#{@stroke_width * 4} #{@stroke_width * 3}"}
    />
    """
  end

  defp outline(assigns) do
    ~H"""
    <rect
      x={@inset}
      y={@inset}
      width={max(@w - @stroke_width, 0)}
      height={max(@h - @stroke_width, 0)}
      rx={@radius}
      stroke-width={@stroke_width}
      stroke-dasharray={@dash && "#{@stroke_width * 4} #{@stroke_width * 3}"}
    />
    """
  end

  # A colour of the theme's, or none.
  defp color("none"), do: "transparent"
  defp color(name), do: "var(--hakushi-shape-#{name}, var(--hakushi-text))"

  # A fill: a tint of its colour on the surface, or none.
  defp tint("none"), do: "transparent"

  defp tint(name),
    do:
      "color-mix(in oklab, #{color(name)} var(--hakushi-shape-tint, 16%), var(--hakushi-surface))"

  @impl true
  def to_markdown(graph) do
    case Enum.filter(Graph.nodes(graph), &(&1.type == "shape")) do
      [] ->
        nil

      shapes ->
        ids = Mermaid.ids(shapes)
        edges = Enum.filter(Graph.edges(graph), &(ids[&1.source] && ids[&1.target]))
        extra = Map.new(shapes, &{&1.id, Map.delete(Hakushi.Kit.stringify(&1.data), "text")})

        body =
          ["flowchart LR"] ++
            Enum.map(shapes, &"  #{ids[&1.id]}#{mermaid_shape(&1)}") ++
            Enum.map(edges, &edge_line(&1, ids)) ++
            ["  classDef text fill:none,stroke:none"] ++
            [Mermaid.places(shapes, ids, extra), Mermaid.edge_places(edges, ids)]

        Mermaid.fence(name(), Enum.join(body, "\n"))
    end
  end

  defp edge_line(edge, ids) do
    case edge.label do
      nil -> "  #{ids[edge.source]} --> #{ids[edge.target]}"
      label -> "  #{ids[edge.source]} -->|#{Mermaid.label(label)}| #{ids[edge.target]}"
    end
  end

  defp mermaid_shape(node) do
    text = Mermaid.label(get(node.data, "text") || "")

    case get(node.data, "kind") do
      "ellipse" -> "((#{text}))"
      "diamond" -> "{#{text}}"
      "triangle" -> "[/#{text}\\]"
      "text" -> "[#{text}]:::text"
      _rect -> if get(node.data, "radius") == 0, do: "[#{text}]", else: "(#{text})"
    end
  end

  @impl true
  def from_markdown(text) do
    with {:ok, nodes, edges} <- Mermaid.flowchart(text) do
      places = Mermaid.read_places(text)

      shapes = Enum.map(nodes, &read_shape(&1, places[&1.m] || %{}))

      graph = Mermaid.graph(shapes, Mermaid.read_edges(text) || edges, places)
      {:ok, sized(graph, Map.new(shapes, &{&1.m, {&1.width, &1.height}}), places)}
    end
  end

  # A node of the flowchart as a shape: its kind and style as they were
  # kept, else as its Mermaid shape says.
  defp read_shape(node, kept) do
    kind = kept["kind"] || kind_of(node)
    {w, h} = @defaults[kind] || {160, 96}

    data =
      kind
      |> shape_defaults()
      |> Map.merge(%{"kind" => kind, "text" => node.text || ""})
      |> then(&style(Map.drop(kept, ~w(m id x y w h parent kind)), &1))

    data =
      if kept == %{} and kind == "rect",
        do: Map.put(data, "radius", corners(node.shape)),
        else: data

    %{m: node.m, type: "shape", data: data, width: w, height: h}
  end

  # A box a person wrote: round corners for `(...)`, sharp for `[...]`.
  defp corners(:round), do: 8
  defp corners(_shape), do: 0

  defp kind_of(%{class: "text"}), do: "text"
  defp kind_of(%{shape: :circle}), do: "ellipse"
  defp kind_of(%{shape: :rhombus}), do: "diamond"
  defp kind_of(%{shape: :trapezoid}), do: "triangle"
  defp kind_of(_node), do: "rect"

  # A shape with no size kept has its kind's.
  defp sized(graph, sizes, places) do
    by_id = Map.new(places, fn {m, place} -> {place["id"] || m, m} end)

    Enum.reduce(Graph.nodes(graph), graph, fn
      %{width: nil} = node, graph ->
        {w, h} = sizes[by_id[node.id] || node.id] || {160, 96}
        %{graph | nodes: Map.put(graph.nodes, node.id, %{node | width: w, height: h})}

      _node, graph ->
        graph
    end)
  end
end
