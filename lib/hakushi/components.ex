defmodule Hakushi.Components do
  @moduledoc """
  Function components for the canvas.

      import Hakushi.Components

      <.canvas id="schema" graph={@graph} on_change={&Schema.change/2}>
        <:node type="table" :let={node}>
          <div class="table">
            <h3>{node.data.name}</h3>
            <div :for={column <- node.data.columns} class="relative">
              <.handle id={column.name} kind={:target} side={:left} />
              {column.name}
              <.handle id={column.name} kind={:source} side={:right} />
            </div>
          </div>
        </:node>
      </.canvas>

  `canvas/1` needs the `Hakushi` hook in the LiveSocket and the Hakushi
  CSS (see the README).
  """

  use Phoenix.Component

  @doc """
  Renders a canvas: an endless sheet that people pan and zoom, with the
  nodes of `graph` on it, drawn by the `:node` slots, and its edges.

  People move nodes by dragging them (or with the arrow keys), select
  them with a click, Shift and a box, connect them by dragging from a
  handle to a handle (or with C, see the [Navigation](navigation.md)
  guide), delete them with Delete, and copy, paste, duplicate, undo and
  redo with the usual keys. Each change goes to the server, which checks
  it (`rules`, then `on_change`) before anyone sees it, and takes it back
  in the browser when it refuses it.

  ## Nodes

  A `:node` slot draws the nodes of its `type`; a `:node` slot without
  a `type` draws the others. The slot gets the `Hakushi.Node`, and draws
  it from its `data`, with the handles where edges start and end
  (`handle/1`). A canvas with no `:node` slot draws each node as a box
  with its label.

  A node is drawn once, and again when it changes: a change of its
  `data` (a change `:update`, or a new `graph`) draws it again; a change
  of the LiveView's own assigns does not.

  ## The graph

  Without `live`, the canvas keeps its own copy of `graph`, which its
  changes change. Give it a new `graph` (after the app's own change, say)
  and it shows what changed. With `live`, the graph is the room's (see
  `Hakushi.Issho`): make the app's changes with `Hakushi.Live.change/2`
  or `Hakushi.Issho.change/3`.
  """
  attr :id, :string, required: true, doc: "the id of the canvas"
  attr :graph, Hakushi.Graph, required: true, doc: "the nodes and edges, a `Hakushi.Graph`"

  attr :on_change, :any,
    default: nil,
    doc: """
    `fn change, context -> :ok | {:error, reason} end`: the app's own check of each change, and \
    where it saves it. `context` has the `graph` before the change and the `result` after it, \
    the `user` and the `canvas`. See the [Changes](changes.md) guide.\
    """

  attr :new_node, :any,
    default: nil,
    doc: """
    `fn item, {x, y} -> node | nil end`: the node for an item dropped on the canvas \
    (`canvas_item/1`), or for a double click on the sheet (`item` is `nil`). A node with no \
    `id` gets one.\
    """

  attr :rules, :list, default: [], doc: "the rules of the edges, see `Hakushi.Rules`"

  attr :live, :any,
    default: nil,
    doc:
      "`{issho, topic}`: a canvas that everyone in the Issho room `topic` shares, see `Hakushi.Issho`"

  attr :user, :map,
    default: nil,
    doc:
      "the person, on a shared canvas: a map with an `:id`, and a `:name`, `:color` and `:avatar`"

  attr :background, :atom,
    default: :dots,
    values: [:dots, :lines, :cross, :none],
    doc: "the paper: dots, lines (graph paper), crosses, or none"

  attr :grid, :integer, default: 20, doc: "the size of a square of the paper, in pixels at 100%"
  attr :snap, :boolean, default: false, doc: "when `true`, nodes snap to the paper's grid"

  attr :wheel, :atom,
    default: :pan,
    values: [:pan, :zoom],
    doc: "what the mouse wheel does: pan (and zoom with ⌘ or Ctrl), or zoom"

  attr :fit, :boolean, default: true, doc: "when `true`, the canvas opens on all of its nodes"
  attr :min_zoom, :float, default: 0.1, doc: "the smallest zoom"
  attr :max_zoom, :float, default: 4.0, doc: "the largest zoom"

  attr :minimap, :boolean,
    default: true,
    doc: "when `true`, an overview of the canvas in a corner"

  attr :controls, :boolean,
    default: true,
    doc: "when `true`, buttons to zoom, fit, tidy up, undo and redo, and to download the canvas"

  attr :layout, :atom,
    default: :right,
    values: [:right, :down],
    doc: """
    the way the tidy up (⇧L, the controls) lays the nodes out: in layers from left to right, \
    or from top to bottom; see [Layout and export](layout.md)\
    """

  attr :export, :boolean,
    default: true,
    doc: "when `true`, a button of the controls downloads the canvas as an image"

  attr :readonly, :boolean,
    default: false,
    doc: "when `true`, people pan, zoom and select, and change nothing"

  attr :follow, :boolean,
    default: true,
    doc:
      "on a shared canvas: `false` for a canvas that takes no part in following, though its room's other blocks do: its avatars follow no one, it shows no one followed, and its view does not move when the room follows someone"

  attr :label, :string, default: nil, doc: "the name of the canvas, for screen readers"

  attr :node_label, :any,
    default: &Hakushi.Canvas.label/1,
    doc: """
    `fn node -> text end`: the name of a node for screen readers; the default is its data's \
    `label` or `name`, or its id\
    """

  attr :locale, :string,
    default: nil,
    doc:
      "the locale of the canvas's own words; the default is `config :hakushi, locale:`, else \"en\""

  attr :messages, :map,
    default: nil,
    doc: "words that replace the built-in ones, see `Hakushi.Messages`"

  attr :class, :any, default: nil, doc: "classes for the canvas element"
  attr :rest, :global, doc: "attributes for the canvas element"

  slot :node, doc: "draws the nodes of a type (`:let` gets the `Hakushi.Node`)" do
    attr :type, :string, doc: "the type of the nodes it draws; none for every other type"
    attr :resizable, :boolean, doc: "when `true`, people resize these nodes by their corners"

    attr :group, :boolean,
      doc:
        "when `true`, these nodes hold others: a node dropped on one goes in it, see [Groups](groups.md)"
  end

  slot :person,
    doc:
      "draws a person on a shared canvas (`:let` gets a map with \"id\", \"name\", \"color\", \"avatar\")"

  slot :empty, doc: "shows on a canvas without nodes"

  def canvas(assigns) do
    ~H"""
    <.live_component
      module={Hakushi.Canvas}
      id={@id}
      graph={@graph}
      on_change={@on_change}
      new_node={@new_node}
      rules={@rules}
      live={@live}
      user={@user}
      background={@background}
      grid={@grid}
      snap={@snap}
      wheel={@wheel}
      fit={@fit}
      min_zoom={@min_zoom}
      max_zoom={@max_zoom}
      minimap={@minimap}
      layout={@layout}
      export={@export}
      controls={@controls}
      readonly={@readonly}
      follow={@follow}
      label={@label}
      node_label={@node_label}
      locale={@locale || Application.get_env(:hakushi, :locale, "en")}
      overrides={@messages}
      class={@class}
      rest={@rest}
      node_slots={@node}
      person_slot={@person}
      empty_slot={@empty}
    />
    """
  end

  @doc """
  Renders a handle: a point of a node where edges start (`:source`), end
  (`:target`), or both.

  A handle sits on a `side` of its nearest positioned ancestor: the node,
  or an element of it with `position: relative`, as a row of a table
  whose edges start at the row.

      <div :for={column <- node.data.columns} class="relative">
        {column.name}
        <.handle id={column.name} side={:right} type={column.type} />
      </div>

  A node may have several handles with one `id`, on different sides (a
  row with a handle at each end): an edge meets the one nearest its
  other end, so the line takes the short way whichever side the other
  node is on.

  `type` and `accepts` say what connects to what: a handle connects to a
  handle that `accepts` its `type` (any, when `accepts` is `nil`). While
  a person draws an edge, the handles it may end on show, and no others.
  """
  attr :id, :string,
    default: nil,
    doc: "the id of the handle in its node, the edges' `source_handle` or `target_handle`"

  attr :kind, :atom,
    default: :both,
    values: [:source, :target, :both],
    doc: "where edges start (`:source`), end (`:target`), or both"

  attr :side, :atom,
    default: :right,
    values: [:left, :right, :top, :bottom],
    doc: "the side it sits on"

  attr :type, :string, default: nil, doc: "what its edges carry, for `accepts`"
  attr :accepts, :list, default: nil, doc: "the types it takes; `nil` for any"
  attr :max, :integer, default: nil, doc: "the most edges it has; `nil` for any number"
  attr :label, :string, default: nil, doc: "its name, for screen readers"
  attr :class, :any, default: nil
  attr :rest, :global

  def handle(assigns) do
    ~H"""
    <span
      class={["hakushi-handle", @class]}
      data-handle={@id}
      data-kind={@kind}
      data-side={@side}
      data-type={@type}
      data-accepts={@accepts && Enum.join(@accepts, " ")}
      data-max={@max}
      aria-label={@label}
      {@rest}
    ></span>
    """
  end

  @doc """
  Renders an item that people drag onto a canvas, outside it: a palette
  of the things the canvas makes. Dropped on the canvas, it becomes the
  node that the canvas's `new_node` gives for `item`. Enter or a click
  puts it in the middle of the canvas, for the keyboard and for a touch
  screen.

      <.canvas_item for="schema" item="table">New table</.canvas_item>
  """
  attr :for, :string, required: true, doc: "the id of the canvas"
  attr :item, :string, required: true, doc: "what it makes, for `new_node`"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def canvas_item(assigns) do
    ~H"""
    <div
      class={["hakushi-item", @class]}
      role="button"
      tabindex="0"
      data-hakushi-item={@item}
      data-hakushi-for={@for}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
