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

  attr :rules, :any,
    default: [],
    doc: "the rules of the edges, see `Hakushi.Rules`; they win over the rules of the kits"

  attr :kits, :list,
    default: [],
    doc: """
    kits (`Hakushi.Kit`) whose nodes the canvas draws, makes and edits by itself: \
    `[Hakushi.Kits.Schema]`; see the [Kits](kits.md) guide\
    """

  attr :live, :any,
    default: nil,
    doc:
      "`{issho, topic}`: a canvas that everyone in the Issho room `topic` shares, see `Hakushi.Issho`"

  attr :user, :map,
    default: nil,
    doc:
      "the person, on a shared canvas: a map with an `:id`, and a `:name`, `:color` and `:avatar`"

  attr :background, :atom,
    default: nil,
    values: [nil, :dots, :lines, :cross, :none],
    doc: """
    the paper: dots, lines (graph paper), crosses, or none; the default is the first kit's \
    (`c:Hakushi.Kit.canvas/0`), else dots\
    """

  attr :grid, :integer,
    default: nil,
    doc: "the size of a square of the paper, in pixels at 100%; the default is a kit's, else 20"

  attr :snap, :boolean,
    default: nil,
    doc: "when `true`, nodes snap to the paper's grid; the default is a kit's, else `false`"

  attr :wheel, :atom,
    default: :pan,
    values: [:pan, :zoom, :scroll],
    doc: """
    what the mouse wheel does: pan (and zoom with ⌘ or Ctrl), zoom, or scroll the page (and zoom \
    with ⌘, Ctrl or a pinch), for a canvas in a page that scrolls, as an embed\
    """

  attr :fit, :boolean, default: true, doc: "when `true`, the canvas opens on all of its nodes"

  attr :refit, :boolean,
    default: false,
    doc: """
    when `true`, the canvas shows all of its nodes again when its box changes size, as an embed \
    that goes full screen and back\
    """

  attr :min_zoom, :float, default: 0.1, doc: "the smallest zoom"
  attr :max_zoom, :float, default: 4.0, doc: "the largest zoom"

  attr :minimap, :boolean,
    default: true,
    doc: "when `true`, an overview of the canvas in a corner"

  attr :controls, :boolean,
    default: true,
    doc: "when `true`, buttons to zoom, fit, tidy up, undo and redo, and to download the canvas"

  attr :layout, :atom,
    default: nil,
    values: [nil, :right, :down],
    doc: """
    the way the tidy up (⇧L, the controls) lays the nodes out: in layers from left to right, \
    or from top to bottom (the default is a kit's, else `:right`); see \
    [Layout and export](layout.md)\
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
    assigns = with_kits(assigns)

    ~H"""
    <.live_component
      module={Hakushi.Canvas}
      id={@id}
      graph={@graph}
      on_change={@on_change}
      new_node={@new_node}
      rules={@rules}
      kits={@kits}
      live={@live}
      user={@user}
      background={@background}
      grid={@grid}
      snap={@snap}
      wheel={@wheel}
      fit={@fit}
      refit={@refit}
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

  # The paper, the tidy up and the rules: the app's, then its kits', then
  # Hakushi's own.
  defp with_kits(%{kits: kits} = assigns) do
    prefs = Hakushi.Kit.canvas_prefs(kits)

    rules =
      case assigns.rules do
        rules when is_list(rules) -> Keyword.merge(Keyword.get(prefs, :rules, []), rules)
        rules -> rules
      end

    assign(assigns,
      background: pick(assigns.background, prefs[:background], :dots),
      grid: pick(assigns.grid, prefs[:grid], 20),
      snap: pick(assigns.snap, prefs[:snap], false),
      layout: pick(assigns.layout, prefs[:layout], :right),
      rules: rules
    )
  end

  defp pick(nil, nil, default), do: default
  defp pick(nil, kit, _default), do: kit
  defp pick(given, _kit, _default), do: given

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

  @doc """
  Renders the items of kits, outside a canvas: one for each element of
  each kit (a table, a step, a note), which people drag onto the canvas,
  or click (or Enter) to put one in its middle. See `canvas_item/1`.

      <.kit_items for="model" kits={[Hakushi.Kits.Schema]} />
  """
  attr :for, :string, required: true, doc: "the id of the canvas"
  attr :kits, :list, required: true, doc: "the canvas's kits"
  attr :locale, :string, default: nil, doc: "the locale of the words, as the canvas's"
  attr :messages, :map, default: nil, doc: "words that replace the built-in ones"
  attr :class, :any, default: nil
  attr :rest, :global

  def kit_items(assigns) do
    assigns = assign(assigns, :words, words(assigns))

    ~H"""
    <div class={["hakushi-kit-items", @class]} role="group" aria-label={@words["addToCanvas"]} {@rest}>
      <%= for kit <- @kits, element <- kit.elements(@words) do %>
        <.canvas_item
          for={@for}
          item={kit.name() <> ":" <> element.item}
          class="hakushi-kit-item"
          title={Hakushi.Kit.word(@words, "addItem", element.label)}
        >
          <Hakushi.Icons.icon name={element.icon} size={14} />
          <span>{element.label}</span>
        </.canvas_item>
      <% end %>
    </div>
    """
  end

  defp words(assigns),
    do:
      Hakushi.Messages.for_locale(
        assigns.locale || Application.get_env(:hakushi, :locale, "en"),
        assigns.messages || %{}
      )

  @doc """
  Renders a canvas in a frame of its own, for a page that has other
  things than the canvas: a document (a Kotoba embed), a card, a panel.
  The frame has a bar with the canvas's icon and title, the items of its
  kits (`kit_items/1`), the app's own actions, and a button that takes it
  full screen and back.

      <.canvas_embed title={@diagram.title} for="diagram" kits={@kits} full={@full} on_full={JS.push("full")}>
        <.canvas id="diagram" graph={@diagram.graph} kits={@kits} wheel={:scroll} refit />
      </.canvas_embed>

  The frame takes the height of its parent (`--hakushi-embed-height`
  when the parent has none). Give its canvas `wheel={:scroll}`, so that
  the wheel scrolls the page around it, and `refit`, so that it shows all
  of its nodes when it goes full screen and back.

  The frame does not go full screen by itself: `on_full` is the app's
  (a `Phoenix.LiveView.JS` command or an event name), and `full` says
  which way the button goes. A Kotoba embed gives both (see the
  [Kits](kits.md) guide).
  """
  attr :title, :string, required: true, doc: "the canvas's title"
  attr :icon, :string, default: "shapes", doc: "a name of `Hakushi.Icons`"
  attr :subtitle, :string, default: nil, doc: "words after the title, as the kind of canvas"
  attr :for, :string, default: nil, doc: "the id of the canvas, for the items of `kits`"
  attr :kits, :list, default: [], doc: "the kits whose items the bar has"
  attr :readonly, :boolean, default: false, doc: "when `true`, the bar has no items"
  attr :full, :boolean, default: false, doc: "whether the frame is full screen now"

  attr :on_full, :any,
    default: nil,
    doc: "the `phx-click` of the full screen button; none without it"

  attr :locale, :string, default: nil, doc: "the locale of the words, as the canvas's"
  attr :messages, :map, default: nil, doc: "words that replace the built-in ones"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :heading,
    doc: "the app's own heading in place of the title, as a field to rename the canvas"

  slot :actions, doc: "the app's own buttons, before the full screen button"
  slot :inner_block, required: true, doc: "the canvas"

  def canvas_embed(assigns) do
    assigns = assign(assigns, :words, words(assigns))

    ~H"""
    <section
      class={["hakushi-embed", @class]}
      data-full={@full && "true"}
      aria-label={@title}
      {@rest}
    >
      <header class="hakushi-embed-bar">
        <span class="hakushi-embed-icon"><Hakushi.Icons.icon name={@icon} /></span>
        <%= if @heading != [] do %>
          {render_slot(@heading)}
        <% else %>
          <span class="hakushi-embed-title">{@title}</span>
        <% end %>
        <span :if={@subtitle} class="hakushi-embed-subtitle">{@subtitle}</span>
        <.kit_items
          :if={!@readonly and @kits != [] and @for}
          for={@for}
          kits={@kits}
          locale={@locale}
          messages={@messages}
        />
        <span class="hakushi-embed-actions">
          {render_slot(@actions)}
          <button
            :if={@on_full}
            type="button"
            class="hakushi-embed-button"
            data-hakushi-full
            phx-click={@on_full}
            aria-label={if @full, do: @words["exitFullScreen"], else: @words["fullScreen"]}
            title={if @full, do: @words["exitFullScreen"], else: @words["fullScreen"]}
          >
            <Hakushi.Icons.icon name={if @full, do: "minimize", else: "maximize"} />
          </button>
        </span>
      </header>
      <div class="hakushi-embed-body">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
