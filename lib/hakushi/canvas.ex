defmodule Hakushi.Canvas do
  @moduledoc """
  The LiveComponent behind `Hakushi.Components.canvas/1`.

  Render the canvas with `canvas/1`, not with this module: it is public
  for its events, which the browser sends and `Hakushi.Test` sends in
  tests.

  The component keeps the canvas's graph (`Hakushi.Graph`), and sends the
  browser its nodes and edges as streams: a change sends the nodes and
  edges it touches, and no others, so a canvas of thousands of nodes
  sends a moved node, not the canvas.

  The browser sends:

    * `"hakushi:change"`, a change of a person: a move, a resize, an edge,
      a delete, an edge's label (see `Hakushi.Change`). The reply is
      `%{"ok" => true}`, or `%{"error" => reason}` for a change the server
      refused, which the browser takes back.
    * `"hakushi:copy"` with `nodes`: the nodes to paste later, and the
      edges between them, kept on the server.
    * `"hakushi:paste"` with `x` and `y` (or none): a copy of them, at
      that place of the canvas (or next to the nodes).
    * `"hakushi:duplicate"` with `nodes`: a copy of the nodes, next to
      them.
    * `"hakushi:drop"` with `item`, `x` and `y`: a new node, made by the
      canvas's `new_node` function, or by a kit for a kit's item
      (`"schema:table"`).
    * `"hakushi:draw"` with `tool` (`"ink:pen"`), `points`, `color`,
      `size` and `parent`: a line drawn with a kit's tool, which the kit
      makes a node of (`c:Hakushi.Kit.drawn/3`).
    * `"hakushi:edit"` with `node`, `action` and the action's params: a
      change of a kit's node by its controls (`Hakushi.Kit`), whose data
      the kit gives.
    * `"hakushi:undo"` and `"hakushi:redo"`: the person's own changes,
      undone and done again as new changes, which the server checks again.
    * `"hakushi:select"` with `nodes` and `edges`: what the person
      selected, for the canvas's `on_select`.
    * `"hakushi:menu"` with `kind`, `nodes`, `edges` and `at`: the items
      of the canvas's `menu` for them (`Hakushi.Menu`), and
      `"hakushi:menu-pick"` with an item's `id` too: the person chose it.
    * `"hakushi:open"` with `node`: the person opened it (its slot
      `opens`), for the canvas's `on_open`; `"hakushi:up"`: they went
      up, for its `on_up`.
    * `"hakushi:viewport"` with `box` (`[x, y, width, height]`) and `zoom`:
      where the person's view came to rest, for the canvas's
      `on_viewport`.
    * `"hakushi:peer"`, on a shared canvas: the person's cursor, the nodes
      they selected, the nodes they drag and the line they draw (`ink`),
      for the others.

  On a shared canvas (`issho`), the component is a session of an Issho
  room (`Hakushi.Issho`): its changes go to the room's document, and the
  room's events come back to it through `update/2`.
  """

  use Phoenix.LiveComponent

  require Logger

  alias Phoenix.LiveView.{JS, TagEngine}

  alias Hakushi.{Change, Commit, Graph, Kit, Messages, Node, Paper, Rules}
  alias Hakushi.Issho.Actions

  # Issho is optional: a canvas without `issho` never calls it.
  @compile {:no_warn_undefined,
            [
              Issho.Live,
              Issho.Actor,
              Issho.Awareness,
              Issho.Join,
              Hakushi.Issho,
              Hakushi.Issho.Actions
            ]}

  # The changes of each person that undo can take back.
  @undo_limit 100
  # The most nodes one paste, duplicate or selection may name.
  @max_items 5_000
  # The most points of a line being drawn that go to the others.
  @max_ink_points 1_500
  # The most files on their way at once (uploads and addresses pasted).
  @max_files 50
  # The colours of the people of a shared canvas with none of their own.
  @palette ~w(#e84a1c #2563eb #059669 #9333ea #d97706 #db2777 #0891b2 #65a30d)

  @algorithms [:layered, :force, :grid]

  @doc false
  # A canvas's `layout`, as `{algorithm, direction}`.
  @spec layout!(term()) :: {:layered | :force | :grid, :right | :down}
  def layout!(direction) when direction in [:right, :down], do: {:layered, direction}
  def layout!(algorithm) when algorithm in @algorithms, do: {algorithm, :right}

  def layout!({algorithm, direction} = layout)
      when algorithm in @algorithms and direction in [:right, :down],
      do: layout

  def layout!(other) do
    raise ArgumentError,
          "a canvas's layout is :right, :down, :layered, :force, :grid or {:layered, :down}, got: #{inspect(other)}"
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       graph: nil,
       given: nil,
       version: 0,
       epoch: nil,
       shared: nil,
       room: nil,
       join: nil,
       show_people: true,
       undo: [],
       redo: [],
       clipboard: nil,
       people: [],
       follow: true,
       notice: nil,
       notice_seq: 0,
       configured: false,
       arrange: false,
       tidy: false,
       places: %{},
       marks: %{nodes: %{}, edges: %{}},
       spotlight: nil,
       diff: %{nodes: %{}, edges: %{}}
     )}
  end

  @impl true
  def update(%{issho: event}, socket), do: {:ok, receive_event(socket, event)}

  def update(%{hakushi_push: {event, payload}}, socket) do
    {:ok, push_event(socket, event, Map.put(payload, "canvas", socket.assigns.id))}
  end

  def update(%{hakushi_mark: mark}, socket), do: {:ok, put_marks(socket, mark)}

  def update(%{hakushi_change: %Change{} = change}, socket) do
    {socket, _result} = commit(socket, %{change | by: nil}, false)
    {:ok, socket}
  end

  def update(assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:graph]))

    socket =
      assign(
        socket,
        :messages,
        Messages.for_locale(socket.assigns.locale, socket.assigns.overrides)
      )

    socket = assign(socket, :rules, Rules.new(assigns[:rules] || socket.assigns[:rules]))

    compare = socket.assigns[:compare]

    socket =
      cond do
        compare != nil ->
          compared(socket, compare, assigns.graph)

        not socket.assigns.configured ->
          start(socket, assigns.graph)

        socket.assigns.shared ->
          socket

        assigns.graph != socket.assigns.given ->
          socket |> assign(:given, assigns.graph) |> replace(assigns.graph)

        true ->
          socket
      end

    {:ok, socket}
  end

  # A canvas that compares (`compare`): its graph, with what the old one
  # had and it has not (the nodes and edges removed, shown as ghosts), and
  # what each node and edge is to the old (`diff`). Shown whole again when
  # either changes.
  defp compared(socket, old, %Graph{} = graph) do
    if socket.assigns.configured and socket.assigns.given == {old, graph} do
      socket
    else
      {shown, diff} = overlay(old, graph)
      socket = assign(socket, given: {old, graph}, diff: diff)

      if socket.assigns.configured,
        do: reset(socket, shown),
        else: start(socket, shown)
    end
  end

  @doc false
  # The graph and the old one together, and what each node and edge of it
  # is to the old: :added, :removed, :changed or :moved (as
  # Hakushi.Graph.compare/2 says it).
  @spec overlay(Graph.t(), Graph.t()) :: {Graph.t(), %{nodes: map(), edges: map()}}
  def overlay(%Graph{} = old, %Graph{} = graph) do
    compared = Graph.compare(old, graph)
    removed = MapSet.new(compared.removed.nodes)

    ghosts =
      for id <- compared.removed.nodes do
        node = Graph.node(old, id)
        parent = node.parent
        kept = parent && (Map.has_key?(graph.nodes, parent) or MapSet.member?(removed, parent))
        %{node | locked: true, parent: if(kept, do: parent)}
      end

    ghost_edges = Enum.map(compared.removed.edges, &Graph.edge(old, &1))

    shown =
      Graph.new(
        nodes: Graph.nodes(graph) ++ ghosts,
        edges: Graph.edges(graph) ++ ghost_edges,
        paper: graph.paper
      )

    statuses = fn ids, status -> Map.new(ids, &{&1, status}) end

    nodes =
      statuses.(compared.moved, :moved)
      |> Map.merge(statuses.(Map.keys(compared.changed.nodes), :changed))
      |> Map.merge(statuses.(compared.added.nodes, :added))
      |> Map.merge(statuses.(compared.removed.nodes, :removed))

    edges =
      statuses.(Map.keys(compared.changed.edges), :changed)
      |> Map.merge(statuses.(compared.added.edges, :added))
      |> Map.merge(statuses.(compared.removed.edges, :removed))

    {shown, %{nodes: nodes, edges: edges}}
  end

  defp start(socket, %Graph{} = graph) do
    id = socket.assigns.id

    socket =
      socket
      |> assign(configured: true, given: graph)
      |> stream_configure(:nodes, dom_id: &node_dom_id(id, &1.id))
      |> stream_configure(:edges, dom_id: &edge_dom_id(id, &1.id))
      |> allow_files()

    case {socket.assigns.join, connected?(socket)} do
      {%{} = join, true} ->
        Hakushi.Live.ensure_mounted!(id)
        share(socket, join, graph)

      {%{}, false} ->
        Hakushi.Live.ensure_mounted!(id)
        reset(socket, graph)

      {nil, _connected} ->
        reset(socket, graph)
    end
  end

  defp start(_socket, other) do
    raise ArgumentError, "a canvas's graph must be a Hakushi.Graph, got: #{inspect(other)}"
  end

  # The files of a kit that takes them (Hakushi.Kits.Images): an upload of
  # the canvas's own, which the browser sends as the person drops, pastes
  # or picks them.
  defp allow_files(socket) do
    Enum.each(socket.assigns.kits, &Kit.check!/1)

    case Kit.uploader(socket.assigns.kits) do
      nil ->
        assign(socket, :uploader, nil)

      kit ->
        socket
        |> assign(:uploader, kit)
        |> allow_upload(
          :hakushi_files,
          Keyword.merge(kit.upload(), auto_upload: true, progress: &file_progress/3)
        )
    end
  end

  # A shared canvas: a session of the document's room, and the document
  # (this canvas's graph, rules and on_change if it opens it first). A
  # canvas the room refuses shows why, and stays read-only on the graph it
  # was given.
  defp share(socket, join, graph) do
    spec =
      Hakushi.Issho.spec(graph, socket.assigns.rules, socket.assigns.on_change, socket.assigns.id)

    # A read-only canvas is a viewer of the room: it shares its person's
    # cursor and changes nothing.
    # An arrange-only canvas moves the room's nodes, so it writes.
    readonly = socket.assigns.readonly or join.can == :read
    arrange = socket.assigns.arrange and join.can != :read
    can = if readonly and not arrange, do: :read, else: :write
    opts = Keyword.put(Issho.Join.grant_opts(join), :can, can)
    room = join.room

    with {:ok, _session} <- Issho.Live.join(join.instance, actor(socket), room, opts),
         {:ok, snapshot} <-
           Issho.Live.open(room, join.document,
             spec: spec,
             notify: {__MODULE__, socket.assigns.id}
           ) do
      socket
      |> assign(shared: join.document, room: room)
      |> assign(version: snapshot["revision"], epoch: snapshot["epoch"])
      |> assign(readonly: readonly, arrange: arrange)
      |> assign_people(people(room))
      |> reset(snapshot["state"])
    else
      {:error, reason} ->
        socket
        |> assign(
          readonly: true,
          arrange: false,
          notice: Messages.reason(socket.assigns.messages, reason)
        )
        |> reset(graph)
    end
  end

  # The actor of the room: the canvas's user, as the app's Issho.Actor says
  # them (their key, name, avatar and colour, the same in every room of
  # the page), or someone anonymous.
  defp actor(socket) do
    case socket.assigns.user do
      nil ->
        %{id: "anonymous:" <> new_id()}

      %{id: _} = user ->
        user

      user ->
        %{
          id: own_id(socket),
          name: user["name"],
          avatar: user["avatar"],
          color: user["color"]
        }
    end
  end

  # The whole graph, anew: at mount, and when a shared canvas lost track.
  defp reset(socket, graph) do
    socket
    |> assign(:graph, graph)
    |> stream(:nodes, Graph.nodes(graph), reset: true)
    |> stream(:edges, Graph.edges(graph), reset: true)
  end

  # A new graph from the LiveView: what changed, and nothing else.
  defp replace(socket, graph) do
    diff = Graph.diff(socket.assigns.graph, graph)

    socket =
      Enum.reduce(
        diff.deleted_edges,
        socket,
        &stream_delete_by_dom_id(&2, :edges, edge_dom_id(&2.assigns.id, &1))
      )

    socket =
      Enum.reduce(
        diff.deleted_nodes,
        socket,
        &stream_delete_by_dom_id(&2, :nodes, node_dom_id(&2.assigns.id, &1))
      )

    socket = Enum.reduce(diff.nodes, socket, &stream_insert(&2, :nodes, &1))
    socket = Enum.reduce(diff.edges, socket, &stream_insert(&2, :edges, &1))
    assign(socket, :graph, graph)
  end

  # A change that applied: its nodes and edges, to the browser.
  defp show(socket, graph, %Change{} = change) do
    socket = assign(socket, :graph, graph)
    {node_ids, edge_ids} = Change.ids(change)

    case change.op do
      :delete ->
        socket =
          Enum.reduce(
            edge_ids,
            socket,
            &stream_delete_by_dom_id(&2, :edges, edge_dom_id(&2.assigns.id, &1))
          )

        Enum.reduce(
          node_ids,
          socket,
          &stream_delete_by_dom_id(&2, :nodes, node_dom_id(&2.assigns.id, &1))
        )

      _other ->
        socket = Enum.reduce(node_ids, socket, &stream_insert(&2, :nodes, Graph.node(graph, &1)))
        Enum.reduce(edge_ids, socket, &stream_insert(&2, :edges, Graph.edge(graph, &1)))
    end
  end

  # -- Marks ----------------------------------------------------------------

  # The app's marks (Hakushi.Live.mark/3): what the nodes and edges are
  # now, kept here and drawn on them, never in the graph. A node or an
  # edge whose mark changed is sent again.
  defp put_marks(socket, :clear) do
    %{marks: marks, spotlight: lit} = socket.assigns
    {lit_nodes, lit_edges} = lit_ids(lit)

    socket
    |> assign(marks: %{nodes: %{}, edges: %{}}, spotlight: nil)
    |> resend(:nodes, Map.keys(marks.nodes) ++ lit_nodes)
    |> resend(:edges, Map.keys(marks.edges) ++ lit_edges)
  end

  defp put_marks(socket, {:spotlight, lit}) do
    {old_nodes, old_edges} = lit_ids(socket.assigns.spotlight)
    {new_nodes, new_edges} = lit_ids(lit)

    socket
    |> assign(:spotlight, lit)
    |> resend(:nodes, old_nodes ++ new_nodes)
    |> resend(:edges, old_edges ++ new_edges)
  end

  defp put_marks(socket, {kind, ids, mark}) when kind in [:nodes, :edges] do
    marks = Enum.reduce(ids, socket.assigns.marks[kind], &merge_mark(&2, &1, mark))

    socket
    |> assign(:marks, Map.put(socket.assigns.marks, kind, marks))
    |> resend(kind, ids)
  end

  defp merge_mark(marks, id, nil), do: Map.delete(marks, id)

  defp merge_mark(marks, id, mark) do
    case marks
         |> Map.get(id, %{})
         |> Map.merge(mark)
         |> Map.reject(fn {_k, v} -> is_nil(v) end) do
      empty when map_size(empty) == 0 -> Map.delete(marks, id)
      merged -> Map.put(marks, id, merged)
    end
  end

  defp lit_ids(nil), do: {[], []}
  defp lit_ids(%{nodes: nodes, edges: edges}), do: {MapSet.to_list(nodes), MapSet.to_list(edges)}

  defp resend(socket, :nodes, ids) do
    graph = socket.assigns.graph

    for id <- Enum.uniq(ids), node = Graph.node(graph, id), reduce: socket do
      socket -> stream_insert(socket, :nodes, node)
    end
  end

  defp resend(socket, :edges, ids) do
    graph = socket.assigns.graph

    for id <- Enum.uniq(ids), edge = Graph.edge(graph, id), reduce: socket do
      socket -> stream_insert(socket, :edges, edge)
    end
  end

  # -- Events of the room -------------------------------------------------

  # A transaction of the room's document: its changes, in revision order.
  # The canvas hears them before it reads the graph it starts from, so one
  # it has already is skipped; after one it missed, or of a document that
  # started again (another epoch), the room's graph.
  defp receive_event(socket, {"tx", _document, %{"revision" => revision, "ops" => changes} = tx}) do
    %{version: version, epoch: epoch} = socket.assigns

    cond do
      tx["epoch"] != epoch -> resync(socket)
      revision <= version -> socket
      revision == version + 1 -> socket |> apply_changes(changes) |> assign(:version, revision)
      true -> resync(socket)
    end
  end

  defp receive_event(socket, {"presence_diff", topic, _diff}),
    do: assign_people(socket, people(topic))

  # The others' cursors, selections and drags, as the browser draws them.
  # A person may have other sessions in the room than a canvas's (Issho's
  # pointers of a page of the room): of those, only whether their pointer
  # is on this canvas, which that page's pointers draw. A canvas's own keys
  # are under its document, in the state's `blocks`.
  defp receive_event(socket, {"aware", _room, %{"states" => states}}) do
    own = room_key(socket)
    doc = socket.assigns.shared

    Enum.reduce(states, socket, fn
      {_session, %{"key" => ^own}}, socket ->
        socket

      {_session, %{"key" => person, "state" => %{} = state}}, socket ->
        case Issho.Awareness.block(state, doc) do
          block when map_size(block) > 0 -> peer(socket, person, state, block)
          _none -> paged(socket, person, state, doc)
        end

      _other, socket ->
        socket
    end)
  end

  defp receive_event(socket, {"bye", _topic, reason}) do
    socket
    |> assign(shared: nil, readonly: true, arrange: false)
    |> assign(:notice, Messages.reason(socket.assigns.messages, bye_reason(reason)))
  end

  defp receive_event(socket, _event), do: socket

  # The person's canvas state as the browser draws it: Issho's keys (their
  # motion) and the canvas's own.
  defp peer(socket, person, state, block) do
    push_event(
      socket,
      "hakushi:peer",
      state
      |> Map.delete("blocks")
      |> Map.merge(%{"selected" => [], "dragging" => []})
      |> Map.merge(Map.delete(block, "seen"))
      |> Map.merge(%{"canvas" => socket.assigns.id, "person" => person})
    )
  end

  defp paged(socket, person, state, doc) do
    paged = match?(%{"doc" => ^doc}, state["pointer"])

    push_event(socket, "hakushi:peer", %{
      "canvas" => socket.assigns.id,
      "person" => person,
      "paged" => paged
    })
  end

  defp apply_changes(socket, changes) do
    Enum.reduce_while(changes, socket, fn change, socket ->
      case Graph.apply(socket.assigns.graph, change) do
        {:ok, graph, change, _inverse} ->
          {:cont, socket |> show(graph, change) |> notify({:changed, change, graph})}

        {:error, _reason, _id} ->
          {:halt, resync(socket)}
      end
    end)
  end

  defp bye_reason("revoked"), do: :revoked
  defp bye_reason("unauthorized"), do: :unauthorized
  defp bye_reason(_other), do: :failed

  # The changes came out of order (a node of a cluster that fell behind):
  # the room's graph, whole.
  defp resync(%{assigns: %{shared: doc, room: room}} = socket) when is_binary(doc) do
    case Issho.Live.read(room, doc) do
      {:ok, %{"state" => graph, "revision" => revision} = snapshot} ->
        socket |> assign(version: revision, epoch: snapshot["epoch"]) |> reset(graph)

      {:error, _reason} ->
        socket
    end
  end

  defp resync(socket), do: socket

  # The people of the room, each once, as the canvas draws them: in their
  # colour, else the one Issho's theme gives them (the same as in the
  # page's other lists), else Hakushi's.
  defp people(topic) do
    for {key, %{metas: [meta | _]}} <- Issho.Live.people(topic) do
      %{
        "id" => key,
        "name" => meta["name"],
        "color" => meta["color"] || palette(meta["palette"], key),
        "avatar" => meta["avatar"]
      }
    end
  end

  defp palette(index, key) when is_integer(index),
    do: "var(--issho-person-#{index}, #{color(key)})"

  defp palette(_index, key), do: color(key)

  @doc false
  def color(id), do: Enum.at(@palette, :erlang.phash2(id, length(@palette)))

  defp assign_people(socket, people) do
    own = room_key(socket)
    others = Enum.reject(people, &(&1["id"] == own))

    socket
    |> assign(:people, others)
    |> push_event("hakushi:people", %{"canvas" => socket.assigns.id, "people" => others})
  end

  defp own_id(socket) do
    case socket.assigns.user do
      nil -> nil
      user -> to_string(Map.get(user, :id) || Map.get(user, "id"))
    end
  end

  # This person's key in the room: the app's Issho.Actor's (`"user:4"`).
  defp room_key(socket) do
    case socket.assigns.user do
      %{id: _} = user -> Issho.Actor.key(user)
      _other -> own_id(socket)
    end
  end

  # -- Events of the browser -----------------------------------------------

  # What the person selected, for the app's on_select: the ids the canvas
  # has, no more of them than a canvas has.
  @impl true
  def handle_event("hakushi:select", params, socket) when is_map(params) do
    %{graph: graph, on_select: on_select, id: id} = socket.assigns

    nodes = params |> Map.get("nodes") |> ids_only() |> Enum.filter(&Graph.node(graph, &1))
    edges = params |> Map.get("edges") |> ids_only() |> Enum.filter(&Graph.edge(graph, &1))
    selection = %{canvas: id, nodes: nodes, edges: edges}
    if on_select, do: on_select.(selection)

    {:noreply, notify(socket, {:selected, selection})}
  end

  # Where the person's view came to rest, for the app's on_viewport: the
  # part of the canvas on their screen, and the zoom.
  def handle_event("hakushi:viewport", params, socket) when is_map(params) do
    with [x, y, width, height] when width > 0 and height > 0 <- numbers(params["box"], 4),
         zoom when is_number(zoom) and zoom > 0 <- params["zoom"] do
      viewport = %{
        canvas: socket.assigns.id,
        x: x,
        y: y,
        width: width,
        height: height,
        zoom: zoom
      }

      if socket.assigns.on_viewport, do: socket.assigns.on_viewport.(viewport)
      {:noreply, notify(socket, {:viewport, viewport})}
    else
      _other -> {:noreply, socket}
    end
  end

  # The menu of a right click (Hakushi.Menu): the app's items for what is
  # under the pointer, as the person may choose them; the ids of the app's
  # own are kept, which a choice must be one of.
  def handle_event("hakushi:menu", params, socket) when is_map(params) do
    %{menu: menu, id: id, graph: graph} = socket.assigns
    target = Hakushi.Menu.target(params, id, graph)

    items =
      case menu do
        none when none in [nil, false] -> []
        true -> Hakushi.Menu.defaults(target)
        fun when is_function(fun, 1) -> fun.(target)
      end

    can = %{
      messages: socket.assigns.messages,
      readonly: socket.assigns.readonly,
      arrange: socket.assigns[:arrange] == true
    }

    {items, offered} = Hakushi.Menu.to_client(items, can)
    {:reply, %{"items" => items}, assign(socket, :menu_offered, offered)}
  end

  # An item of the app's own, chosen: its on_menu, and notify.
  def handle_event("hakushi:menu-pick", %{"id" => item} = params, socket) when is_binary(item) do
    if MapSet.member?(socket.assigns[:menu_offered] || MapSet.new(), item) do
      target = Hakushi.Menu.target(params, socket.assigns.id, socket.assigns.graph)
      if socket.assigns.on_menu, do: socket.assigns.on_menu.(item, target)

      {:reply, %{"ok" => true},
       socket |> assign(:menu_offered, MapSet.new()) |> notify({:menu, item, target})}
    else
      {:reply, %{"ok" => false}, socket}
    end
  end

  # A node opened (its slot `opens`): the app's on_open, and notify.
  def handle_event("hakushi:open", %{"node" => id}, socket) when is_binary(id) do
    %{graph: graph, on_open: on_open, node_slots: slots, kits: kits} = socket.assigns
    node = Graph.node(graph, id)

    if node && node_flag?(slots, kits, node, :opens) do
      if on_open, do: on_open.(%{canvas: socket.assigns.id, node: id})
      {:reply, %{"ok" => true}, notify(socket, {:opened, id})}
    else
      {:reply, %{"ok" => false}, socket}
    end
  end

  # Up, out of the canvas: the app's on_up, and notify.
  def handle_event("hakushi:up", _params, socket) do
    if socket.assigns.on_up, do: socket.assigns.on_up.(%{canvas: socket.assigns.id})
    {:reply, %{"ok" => true}, notify(socket, :up)}
  end

  def handle_event(event, params, %{assigns: %{readonly: true}} = socket)
      when event not in ["hakushi:peer", "hakushi:seen"] do
    if socket.assigns[:arrange] and arrangement?(event, params, socket),
      do: arrange(event, params, socket),
      else: {:reply, %{"error" => Messages.reason(socket.assigns.messages, :readonly)}, socket}
  end

  # A paper of the picker: one the canvas offers, a change as any other.
  def handle_event("hakushi:change", %{"op" => "paper", "paper" => paper}, socket) do
    case Paper.from_client(paper, Paper.offered(socket.assigns.papers)) do
      {:ok, paper} -> reply(commit(socket, Change.paper(paper), true))
      :error -> {:reply, %{"error" => Messages.reason(socket.assigns.messages, :failed)}, socket}
    end
  end

  def handle_event("hakushi:change", params, socket) when is_map(params),
    do: client_change(params, socket)

  def handle_event("hakushi:copy", %{"nodes" => ids}, socket) when is_list(ids) do
    {:reply, %{"ok" => true}, assign(socket, :clipboard, copy(socket.assigns.graph, ids))}
  end

  def handle_event("hakushi:paste", params, %{assigns: %{clipboard: {nodes, edges}}} = socket) do
    at =
      case params do
        %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> {x, y}
        _other -> nil
      end

    paste(socket, nodes, edges, at)
  end

  def handle_event("hakushi:paste", _params, socket), do: {:reply, %{"ok" => false}, socket}

  def handle_event("hakushi:duplicate", %{"nodes" => ids}, socket) when is_list(ids) do
    case copy(socket.assigns.graph, ids) do
      {[], _edges} -> {:reply, %{"ok" => false}, socket}
      {nodes, edges} -> paste(socket, nodes, edges, nil)
    end
  end

  def handle_event("hakushi:drop", %{"x" => x, "y" => y} = params, socket)
      when is_number(x) and is_number(y) do
    item = if is_binary(params["item"]), do: params["item"]

    case new_node(socket.assigns, item, {x, y}) do
      nil ->
        {:reply, %{"ok" => false}, socket}

      node ->
        node = node |> with_id() |> Node.new() |> in_group(socket.assigns.graph, params["parent"])
        socket |> commit(Change.add([node]), true) |> reply(%{"select" => [node.id]})
    end
  end

  def handle_event("hakushi:draw", %{"tool" => tool} = params, socket) when is_binary(tool) do
    with [name, kit_tool] <- String.split(tool, ":", parts: 2),
         kit when kit != nil <- Kit.by_name(socket.assigns.kits, name),
         %{} = node <- Kit.drawn(kit, kit_tool, params, socket.assigns.messages) do
      node = node |> with_id() |> Node.new() |> in_group(socket.assigns.graph, params["parent"])
      socket |> commit(Change.add([node]), true) |> reply(%{"drawn" => node.id})
    else
      _refused -> {:reply, %{"ok" => false}, socket}
    end
  end

  # An action on several nodes at once (a style of the panel over the
  # selection): one change, of those a kit takes.
  def handle_event(
        "hakushi:edit",
        %{"nodes" => [_ | _] = ids, "action" => action} = params,
        socket
      )
      when is_binary(action) and length(ids) <= @max_items do
    graph = socket.assigns.graph

    updates =
      for id <- Enum.uniq(ids),
          is_binary(id),
          %Node{} = node <- [Graph.node(graph, id)],
          kit = Kit.for_type(socket.assigns.kits, node.type),
          kit != nil,
          {:ok, data} <- [kit.edit(action, params, Kit.stringify(node.data))],
          data != node.data,
          do: %{id: id, data: data}

    case updates do
      [] -> {:reply, %{"ok" => true}, socket}
      updates -> socket |> commit(Change.update(nodes: updates), true) |> reply()
    end
  end

  def handle_event("hakushi:edit", %{"node" => id, "action" => action} = params, socket)
      when is_binary(id) and is_binary(action) do
    with %Node{} = node <- Graph.node(socket.assigns.graph, id),
         kit when kit != nil <- Kit.for_type(socket.assigns.kits, node.type),
         {:ok, data} <- kit.edit(action, params, Kit.stringify(node.data)) do
      # An edit that moves and resizes its node too (a crop): one change.
      box =
        case numbers(params["box"], 4) do
          [x, y, w, h] when w > 0 and h > 0 -> %{x: x, y: y, width: w, height: h}
          _none -> %{}
        end

      if data == node.data and box == %{},
        do: {:reply, %{"ok" => true}, socket},
        else:
          socket
          |> commit(Change.update(nodes: [Map.merge(%{id: id, data: data}, box)]), true)
          |> reply()
    else
      _refused -> {:reply, %{"ok" => false}, socket}
    end
  end

  # The files of the canvas's upload: those the LiveView refuses (too
  # large, not of a type it takes) go, and the browser takes their
  # placeholders away.
  def handle_event("hakushi:files", _params, socket) do
    {:noreply, drop_refused(socket)}
  end

  # Where the person put a file that uploads: its place, then its node.
  def handle_event("hakushi:place", %{"ref" => ref} = params, socket)
      when is_binary(ref) and byte_size(ref) <= 64 and
             map_size(socket.assigns.places) < @max_files do
    place = %{box: numbers(params["box"], 4), parent: params["parent"]}
    {:reply, %{"ok" => true}, update(socket, :places, &Map.put(&1, ref, place))}
  end

  # An image's address, pasted: the kit makes a node of it, away from the
  # LiveView, and the browser shows a placeholder until it is done.
  def handle_event("hakushi:paste-url", %{"url" => url, "ref" => ref} = params, socket)
      when is_binary(url) and byte_size(url) <= 2_048 and is_binary(ref) and byte_size(ref) <= 64 and
             map_size(socket.assigns.places) < @max_files do
    case socket.assigns[:uploader] do
      nil ->
        {:reply, %{"ok" => false}, socket}

      kit ->
        box = numbers(params["box"], 4)
        messages = socket.assigns.messages
        place = %{box: box, parent: params["parent"]}

        {:reply, %{"ok" => true},
         socket
         |> update(:places, &Map.put(&1, ref, place))
         |> start_async({:hakushi_pasted, ref}, fn -> kit.pasted(url, box, messages) end)}
    end
  end

  def handle_event(event, _params, socket) when event in ["hakushi:place", "hakushi:paste-url"],
    do: {:reply, %{"ok" => false}, socket}

  def handle_event("hakushi:undo", _params, socket),
    do: step(socket, :undo, :redo, "nothingToUndo")

  def handle_event("hakushi:redo", _params, socket),
    do: step(socket, :redo, :undo, "nothingToRedo")

  # Issho's awareness sends the room one frame of what changed every 50 ms,
  # whatever the browser sends.
  def handle_event("hakushi:peer", params, %{assigns: %{shared: doc, room: room}} = socket)
      when is_binary(doc) and is_map(params) do
    # Under the canvas's document: the LiveView's other components in the
    # room keep their keys, and Issho its own. What the person selected is
    # also their place in the room, Issho's own key.
    state = peer_state(params)
    aware = Issho.Live.awareness(room)

    Issho.Live.aware(
      room,
      aware
      |> Issho.Awareness.put_block(doc, state)
      |> selection_place(doc, state["selected"], socket.assigns)
    )

    {:noreply, socket}
  end

  def handle_event("hakushi:peer", _params, socket), do: {:noreply, socket}

  # What the person sees, for the room's agents (`read_canvas`): the
  # nodes on their screen and the nodes each edge passes under there.
  def handle_event("hakushi:seen", params, %{assigns: %{shared: doc, room: room}} = socket)
      when is_binary(doc) and is_map(params) do
    Issho.Live.merge_block(room, doc, %{"seen" => seen(params)})
    {:noreply, socket}
  end

  def handle_event("hakushi:seen", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:hakushi_pasted, ref}, result, socket) do
    result =
      case result do
        {:ok, {:ok, %{} = node}} -> {:ok, node}
        {:ok, {:error, reason}} -> {:error, reason}
        _exit -> {:error, :failed}
      end

    {:noreply, add_file_node(socket, ref, result)}
  end

  # A file's progress, for its placeholder (and the others'); a file done
  # becomes a node.
  defp file_progress(:hakushi_files, %{done?: false} = entry, socket) do
    {:noreply, push_file(socket, entry.ref, %{"progress" => entry.progress})}
  end

  defp file_progress(:hakushi_files, entry, socket) do
    %{uploader: kit, messages: messages} = socket.assigns
    box = get_in(socket.assigns.places, [entry.ref, :box])
    meta = %{name: entry.client_name, content_type: entry.client_type}

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, kit.uploaded(path, meta, box, messages)}
      end)

    {:noreply, add_file_node(socket, entry.ref, result)}
  end

  defp add_file_node(socket, ref, result) do
    {place, places} = Map.pop(socket.assigns.places, ref, %{})
    socket = assign(socket, :places, places)

    with {:ok, %{} = node} <- result,
         node = node |> with_id() |> Node.new() |> in_group(socket.assigns.graph, place[:parent]),
         {socket, {:ok, _inverse, _rewritten}} <- commit(socket, Change.add([node]), true) do
      push_file(socket, ref, %{"id" => node.id})
    else
      {socket, {:error, message}} ->
        push_file(socket, ref, %{"error" => message})

      {:error, reason} ->
        Logger.warning("Hakushi: a file was not added to the canvas: #{inspect(reason)}")
        file_failed(socket, ref, file_error(socket.assigns.messages, reason))
    end
  end

  # A file that did not become a node: its placeholder goes, and the canvas
  # says why.
  defp file_failed(socket, ref, message) do
    socket
    |> assign(notice: message, notice_seq: socket.assigns.notice_seq + 1)
    |> push_file(ref, %{"error" => message})
  end

  defp drop_refused(socket) do
    case socket.assigns[:uploads] do
      %{hakushi_files: %{entries: entries}} ->
        entries |> Enum.reject(& &1.valid?) |> Enum.reduce(socket, &refuse_entry(&2, &1))

      _none ->
        socket
    end
  end

  defp refuse_entry(socket, entry) do
    reason =
      case upload_errors(socket.assigns.uploads.hakushi_files, entry) do
        [reason | _rest] -> reason
        [] -> :failed
      end

    socket
    |> cancel_upload(:hakushi_files, entry.ref)
    |> update(:places, &Map.delete(&1, entry.ref))
    |> file_failed(entry.ref, file_error(socket.assigns.messages, reason))
  end

  defp file_error(messages, reason)
       when reason in [:too_large, :not_accepted, :not_an_image, :not_allowed, :too_many_files],
       do: Messages.reason(messages, reason)

  defp file_error(messages, _reason), do: Messages.reason(messages, :file_failed)

  defp push_file(socket, ref, payload) do
    push_event(
      socket,
      "hakushi:file",
      Map.merge(payload, %{"canvas" => socket.assigns.id, "ref" => ref})
    )
  end

  # The nodes of the ids, and the nodes in them, with the edges between
  # them.
  defp copy(graph, ids) do
    ids = ids |> Enum.filter(&is_binary/1) |> Enum.take(@max_items)
    ids = MapSet.new(ids ++ Enum.flat_map(ids, &Graph.descendants(graph, &1)))
    nodes = Enum.filter(Graph.nodes(graph), &MapSet.member?(ids, &1.id))

    edges =
      Enum.filter(
        Graph.edges(graph),
        &(MapSet.member?(ids, &1.source) and MapSet.member?(ids, &1.target))
      )

    {nodes, edges}
  end

  # Copies with new ids: at a place (their top left corner), or next to
  # the nodes they copy.
  defp paste(socket, [], _edges, _at), do: {:reply, %{"ok" => false}, socket}

  defp paste(socket, nodes, edges, at) do
    {left, top} =
      {nodes |> Enum.map(& &1.x) |> Enum.min(), nodes |> Enum.map(& &1.y) |> Enum.min()}

    {dx, dy} = if at, do: {elem(at, 0) - left, elem(at, 1) - top}, else: {24, 24}
    ids = Map.new(nodes, &{&1.id, new_id()})

    # A copy in a copied group is in the copy of the group; a copy next to
    # its node stays in the node's group; a copy put somewhere is in none.
    nodes =
      Enum.map(nodes, fn node ->
        parent = ids[node.parent] || if(at, do: nil, else: node.parent)
        %{node | id: ids[node.id], x: node.x + dx, y: node.y + dy, locked: false, parent: parent}
      end)

    edges =
      Enum.map(edges, fn edge ->
        %{edge | id: new_id(), source: ids[edge.source], target: ids[edge.target]}
      end)

    socket
    |> commit(Change.add(nodes, edges), true)
    |> reply(%{"select" => Enum.map(nodes, & &1.id)})
  end

  defp client_change(params, socket) do
    case {Change.from_client(params), params["opened"]} do
      # The places of a canvas that tidies as it opens: the person's, which
      # no undo takes back to the pile it opened as.
      {{:ok, %Change{op: :move} = change}, true} ->
        reply(commit(socket, change, :quiet))

      {{:ok, change}, _opened} ->
        reply(commit(socket, change, true))

      {:error, _opened} ->
        {:reply, %{"error" => Messages.reason(socket.assigns.messages, :failed)}, socket}
    end
  end

  # What an arrange-only canvas takes: a move of nodes to other places (not
  # a resize, nor into or out of a group), and the undo and redo of those.
  defp arrangement?("hakushi:change", params, _socket) do
    case Change.from_client(params) do
      {:ok, %Change{op: :move, nodes: places}} ->
        Enum.all?(places, &(Map.keys(&1) -- [:id, :x, :y] == []))

      _other ->
        false
    end
  end

  defp arrangement?(event, _params, socket) when event in ["hakushi:undo", "hakushi:redo"] do
    from = if event == "hakushi:undo", do: :undo, else: :redo

    case Map.fetch!(socket.assigns, from) do
      [%Change{op: :move} | _rest] -> true
      [] -> true
      _other -> false
    end
  end

  defp arrangement?(_event, _params, _socket), do: false

  defp arrange("hakushi:change", params, socket), do: client_change(params, socket)
  defp arrange("hakushi:undo", _params, socket), do: step(socket, :undo, :redo, "nothingToUndo")
  defp arrange("hakushi:redo", _params, socket), do: step(socket, :redo, :undo, "nothingToRedo")

  defp step(socket, from, to, nothing) do
    case Map.fetch!(socket.assigns, from) do
      [] ->
        {:reply, %{"error" => socket.assigns.messages[nothing]}, socket}

      [change | rest] ->
        socket = assign(socket, from, rest)

        socket |> commit(%{change | by: person(socket)}, false) |> stepped(change, to)
    end
  end

  # An undo or a redo that applied goes on the other list, and selects the
  # nodes it brought back or moved.
  defp stepped({socket, {:ok, inverse, rewritten}}, change, to) do
    {node_ids, _edge_ids} = Change.ids(change)
    select = if change.op == :delete, do: [], else: node_ids

    {:reply, rewritten(%{"ok" => true, "select" => select}, rewritten),
     update(socket, to, &[inverse | &1])}
  end

  defp stepped({socket, {:error, message}}, _change, _to),
    do: {:reply, %{"error" => message}, socket}

  defp reply(result, extra \\ %{})

  defp reply({socket, {:ok, _inverse, rewritten}}, extra),
    do: {:reply, rewritten(Map.merge(%{"ok" => true}, extra), rewritten), socket}

  defp reply({socket, {:error, message}}, _extra), do: {:reply, %{"error" => message}, socket}

  # What the canvas tells the app's process (`notify`): `{Hakushi, id,
  # event}`, when it is there.
  defp notify(%{assigns: %{notify: nil}} = socket, _event), do: socket

  defp notify(socket, event) do
    case GenServer.whereis(socket.assigns.notify) do
      nil -> :ok
      to -> send(to, {Hakushi, socket.assigns.id, event})
    end

    socket
  end

  # A change on_change gave back another for: the browser reads again what
  # it showed of the person's.
  defp rewritten(reply, true), do: Map.put(reply, "rewritten", true)
  defp rewritten(reply, false), do: reply

  # A change, here or through the room of a shared canvas: the one place
  # where the two differ. A person's own change (`record`) goes on their
  # undo list (but a `:quiet` one, which is theirs, does not), as it
  # applied: on_change may have given back another in its place. On a
  # shared canvas, its inverse is of the graph this canvas has; the change
  # itself shows when the room sends it back.
  defp commit(socket, %Change{} = change, record) do
    change = if record, do: %{change | by: person(socket)}, else: change

    result =
      case socket.assigns.shared do
        nil ->
          Commit.run(socket.assigns.graph, change, %{
            rules: socket.assigns.rules,
            on_change: socket.assigns.on_change,
            canvas: socket.assigns.id,
            by: change.by && socket.assigns.user
          })

        doc ->
          Hakushi.Issho.take_rewritten()

          with {:ok, _graph, _change, inverse} <-
                 Commit.check_and_apply(socket.assigns.graph, change, socket.assigns.rules),
               {:ok, _receipt} <- Actions.commit(socket.assigns.room, doc, change) do
            shared_inverse(socket, inverse, Hakushi.Issho.take_rewritten())
          end
      end

    case result do
      {:ok, graph, change, inverse, rewritten} ->
        socket =
          socket
          |> show(graph, change)
          |> clear_notice()
          |> remember(record, inverse)
          |> notify({:changed, change, graph})

        {socket, {:ok, inverse, rewritten}}

      {:ok, inverse, rewritten} ->
        {socket |> clear_notice() |> remember(record, inverse), {:ok, inverse, rewritten}}

      {:error, reason} ->
        message = Messages.reason(socket.assigns.messages, reason)

        {socket |> assign(notice: message, notice_seq: socket.assigns.notice_seq + 1),
         {:error, message}}
    end
  end

  # The inverse of the change the room took: the person's, or the one
  # on_change gave back in its place.
  defp shared_inverse(_socket, inverse, nil), do: {:ok, inverse, false}

  defp shared_inverse(socket, inverse, [%Change{} = other]) do
    case Commit.check_and_apply(socket.assigns.graph, other, socket.assigns.rules) do
      {:ok, _graph, _change, inverse} -> {:ok, inverse, true}
      {:error, _reason} -> {:ok, inverse, true}
    end
  end

  defp shared_inverse(_socket, inverse, _others), do: {:ok, inverse, true}

  defp remember(socket, record, _inverse) when record in [false, :quiet], do: socket

  defp remember(socket, true, inverse) do
    assign(socket, undo: Enum.take([inverse | socket.assigns.undo], @undo_limit), redo: [])
  end

  defp clear_notice(%{assigns: %{notice: nil}} = socket), do: socket
  defp clear_notice(socket), do: assign(socket, :notice, nil)

  defp person(socket) do
    case socket.assigns.user do
      nil -> nil
      user -> %{id: own_id(socket), name: Map.get(user, :name) || Map.get(user, "name")}
    end
  end

  # A node dropped in a group is in it, unless new_node put it elsewhere.
  defp in_group(%Node{parent: nil} = node, graph, parent) when is_binary(parent) do
    if Graph.node(graph, parent), do: %{node | parent: parent}, else: node
  end

  defp in_group(node, _graph, _parent), do: node

  defp with_id(%Node{id: nil} = node), do: %{node | id: new_id()}
  defp with_id(%Node{} = node), do: node

  defp with_id(%{} = fields) do
    if Map.get(fields, :id) || Map.get(fields, "id"),
      do: fields,
      else: Map.put(fields, :id, new_id())
  end

  defp with_id(fields) when is_list(fields), do: fields |> Map.new() |> with_id()

  @doc false
  def new_id, do: Base.encode32(:crypto.strong_rand_bytes(5), case: :lower, padding: false)

  # What the others see of a person: numbers and ids, and no more of them
  # than a canvas has.
  # The nodes selected are the person's place (`Hakushi.Issho.Place`): where
  # a comment of the room goes, what Issho's pointers show when their
  # pointer is off the canvas. With none, a place of this canvas goes; one
  # of another component (a text the person types in) stays. Its label
  # says it in a few words, for those who only read it (an agent).
  defp selection_place(aware, doc, [], _assigns) do
    case aware["place"] do
      %{"doc" => ^doc} -> Map.delete(aware, "place")
      _other -> aware
    end
  end

  defp selection_place(aware, doc, ids, assigns) do
    at = if match?([_id], ids), do: %{"node" => hd(ids)}, else: %{"nodes" => ids}

    place =
      case place_label(assigns, ids) do
        nil -> %{"doc" => doc, "at" => at}
        label -> %{"doc" => doc, "at" => at, "label" => label}
      end

    Map.put(aware, "place", place)
  end

  @doc false
  # A selection in a few words: a node's own (`node_words/2`), or how many
  # nodes ("3 nodes"); nil for nodes the canvas does not have. Issho cleans
  # and cuts a label; `at` stays what says where.
  def place_label(%{graph: %Graph{} = graph} = assigns, ids) do
    case for(id <- ids, node = Graph.node(graph, id), do: node) do
      [] -> nil
      [node] -> node_words(assigns, node)
      nodes -> String.replace(assigns.messages["placeLabelNodes"], "{n}", "#{length(nodes)}")
    end
  end

  def place_label(_assigns, _ids), do: nil

  # The app's name of a node, else its words (a title, a text, an image's
  # alt), else its kind ("Drawing", "Note"); never its id.
  defp node_words(assigns, node) do
    words =
      if assigns.node_label == (&__MODULE__.label/1),
        do:
          own_words(node.data) || Kit.label(assigns.kits, node, assigns.messages) ||
            kind(assigns.kits, node, assigns.messages),
        else: assigns.node_label.(node)

    first_words(words)
  end

  @words ~w(title text alt caption description label name)

  defp own_words(data) when is_map(data) do
    Enum.find_value(@words, fn key ->
      case Kit.get(data, key) do
        text when is_binary(text) -> first_words(text)
        _other -> nil
      end
    end)
  end

  defp own_words(_data), do: nil

  # The kit's word for an item of the node's type, as its button says it.
  defp kind(kits, node, messages) do
    with kit when kit != nil <- Kit.for_type(kits, node.type) do
      Enum.find_value(kit.elements(messages), &(&1[:item] == node.type && &1[:label]))
    end
  end

  # One line of whole words, at most 60 characters (Issho's most).
  defp first_words(text) when is_binary(text) do
    words = String.split(text)
    line = Enum.join(words, " ")

    cond do
      line == "" -> nil
      String.length(line) <= 60 -> line
      true -> cut(words)
    end
  end

  defp first_words(_other), do: nil

  defp cut([first | rest]) do
    Enum.reduce_while(rest, String.slice(first, 0, 59), fn word, line ->
      next = line <> " " <> word
      if String.length(next) <= 59, do: {:cont, next}, else: {:halt, line}
    end) <> "…"
  end

  defp peer_state(params) do
    %{
      "cursor" => numbers(params["cursor"], 2),
      "selected" => params |> Map.get("selected", []) |> ids_only(),
      # What the person's canvas shows (its top left corner, width and height,
      # in the canvas's terms), for those who follow them; not `view`, which
      # is Issho's (what their page shows), in the same state.
      "viewport" => numbers(params["viewport"], 4),
      "dragging" =>
        params
        |> Map.get("dragging", [])
        |> List.wrap()
        |> Enum.take(@max_items)
        |> Enum.filter(
          &match?([id, x, y] when is_binary(id) and is_number(x) and is_number(y), &1)
        ),
      "ink" => ink(params["ink"]),
      # The placeholders of the files the person uploads: a box and a
      # progress each.
      "files" =>
        params
        |> Map.get("files", [])
        |> List.wrap()
        |> Enum.take(20)
        |> Enum.map(&numbers(&1, 5))
        |> Enum.reject(&is_nil/1)
    }
  end

  # A line being drawn: a tool's and a colour's names, a width, and its
  # points (numbers), no more of them than a stroke has.
  @doc false
  def ink(%{"tool" => tool, "color" => color, "size" => size, "points" => points})
      when is_binary(tool) and byte_size(tool) <= 40 and is_binary(color) and is_number(size) and
             size > 0 and is_list(points) do
    points = points |> Enum.take(@max_ink_points) |> Enum.filter(&ink_point?/1)

    if Regex.match?(~r/\A[a-z0-9-]{1,24}\z/, color) and points != [],
      do: %{"tool" => tool, "color" => color, "size" => min(size, 64), "points" => points}
  end

  def ink(_other), do: nil

  defp ink_point?([x, y, p]), do: is_number(x) and is_number(y) and is_number(p)
  defp ink_point?(_other), do: false

  # What a person sees, checked: a node's box is four numbers, an edge's
  # `under` the ids of nodes; at most 200 of each.
  defp seen(params) do
    nodes =
      for {id, box} <- Map.get(params, "nodes") |> map_or_empty() |> Enum.take(200),
          is_binary(id),
          box = numbers(box, 4),
          into: %{},
          do: {id, box}

    edges =
      for {id, %{"under" => under}} <-
            Map.get(params, "edges") |> map_or_empty() |> Enum.take(200),
          is_binary(id),
          under = under |> ids_only() |> Enum.take(50),
          under != [],
          into: %{},
          do: {id, %{"under" => under}}

    %{"nodes" => nodes, "edges" => edges}
  end

  defp map_or_empty(map) when is_map(map), do: map
  defp map_or_empty(_other), do: %{}

  # A list of `count` numbers, or nil.
  defp numbers(list, count) when is_list(list) and length(list) == count,
    do: if(Enum.all?(list, &is_number/1), do: list)

  defp numbers(_other, _count), do: nil

  defp ids_only(list) when is_list(list),
    do: list |> Enum.filter(&is_binary/1) |> Enum.take(@max_items)

  defp ids_only(_other), do: []

  # -- Rendering -------------------------------------------------------------

  @doc false
  def node_dom_id(canvas, id), do: canvas <> "-n-" <> Base.url_encode64(id, padding: false)

  @doc false
  def edge_dom_id(canvas, id), do: canvas <> "-e-" <> Base.url_encode64(id, padding: false)

  @impl true
  def render(assigns) do
    assigns = assigns |> with_paper() |> then(&assign(&1, :config, JSON.encode!(config(&1))))

    ~H"""
    <div
      id={@id}
      class={["hakushi", @class]}
      phx-mounted={JS.ignore_attributes(["style", "data-ui-*"])}
      data-background={@paper_background}
      data-tidy={@tidy && "true"}
      data-spotlight={@spotlight && "true"}
      data-compare={@compare && "true"}
      role="application"
      tabindex="0"
      aria-roledescription={@messages["canvas"]}
      aria-label={@label}
      data-issho-doc={@shared}
      data-issho-cursor={@shared && "own"}
      {@rest}
    >
      <%!-- The hook has an element of its own: LiveView locks the element of
           a hook while its events wait for their replies, and a lock on the
           canvas would hold back the server's patches of its nodes. --%>
      <div
        id={@id <> "-hook"}
        class="hakushi-hook"
        phx-hook="Hakushi"
        phx-target={@myself}
        phx-update="ignore"
        data-config={@config}
        hidden
      >
      </div>
      <div id={@id <> "-viewport"} class="hakushi-viewport" phx-update="ignore">
        <div class="hakushi-background"></div>
      </div>
      <div id={@id <> "-world"} class="hakushi-world" phx-mounted={JS.ignore_attributes(["style"])}>
        <svg id={@id <> "-svg"} class="hakushi-edges" phx-update="ignore" aria-hidden="true"></svg>
        <div id={@id <> "-nodes"} class="hakushi-nodes" phx-update="stream">
          <div
            :for={{dom_id, node} <- @streams.nodes}
            id={dom_id}
            class={["hakushi-node", mark(@marks.nodes, node.id, :class)]}
            data-id={node.id}
            data-type={node.type}
            data-x={node.x}
            data-y={node.y}
            data-width={node.width}
            data-height={node.height}
            data-locked={node.locked && "true"}
            data-resizable={node_flag?(@node_slots, @kits, node, :resizable) && "true"}
            data-group={node_flag?(@node_slots, @kits, node, :group) && "true"}
            data-opens={node_flag?(@node_slots, @kits, node, :opens) && "true"}
            data-parent={node.parent}
            data-mark-status={mark(@marks.nodes, node.id, :status)}
            data-mark-highlight={mark(@marks.nodes, node.id, :highlight) && "true"}
            data-mark-dim={mark(@marks.nodes, node.id, :dim) && "true"}
            data-lit={lit?(@spotlight, :nodes, node.id) && "true"}
            data-diff={@diff.nodes[node.id]}
            title={mark(@marks.nodes, node.id, :title)}
            style={node_style(node) <> mark_color(@marks.nodes, node.id)}
            tabindex="-1"
            role="group"
            aria-roledescription={@messages["node"]}
            aria-label={node_label(@node_label, @kits, @messages, node)}
          >
            <.node_content
              slots={@node_slots}
              kits={@kits}
              node={node}
              readonly={@readonly}
              drag_out={@drag_out}
              canvas={@id}
              target={@myself}
              messages={@messages}
            />
            <span :if={mark(@marks.nodes, node.id, :badge)} class="hakushi-mark-badge">
              {mark(@marks.nodes, node.id, :badge)}
            </span>
            <span
              :if={mark(@marks.nodes, node.id, :progress)}
              class="hakushi-mark-progress"
              role="progressbar"
              aria-valuemin="0"
              aria-valuemax="100"
              aria-valuenow={round(mark(@marks.nodes, node.id, :progress) * 100)}
            >
              <span style={"width: #{mark(@marks.nodes, node.id, :progress) * 100}%"}></span>
            </span>
          </div>
        </div>
        <%!-- The edges of the selected nodes, and a selected edge, above
             the nodes: the whole of each, where it goes under another node. --%>
        <svg id={@id <> "-svg-raised"} class="hakushi-edges hakushi-edges-raised" phx-update="ignore" aria-hidden="true"></svg>
        <div id={@id <> "-labels"} class="hakushi-labels" phx-update="ignore"></div>
        <%!-- The edges' data, which the browser draws them by; with an
             :edge_label slot, each one's label too, which it places on
             the edge (the style and data-ui-* are the browser's). --%>
        <div id={@id <> "-edge-data"} class="hakushi-edge-data" phx-update="stream">
          <i
            :for={{dom_id, edge} <- @streams.edges}
            id={dom_id}
            class={@edge_label_slot != [] && "hakushi-edge-label hakushi-edge-label-own"}
            phx-mounted={@edge_label_slot != [] && JS.ignore_attributes(["style", "data-ui-*"])}
            data-id={edge.id}
            data-edge={edge.id}
            data-source={edge.source}
            data-source-handle={edge.source_handle}
            data-target={edge.target}
            data-target-handle={edge.target_handle}
            data-path={edge.path}
            data-label={edge.label}
            data-marker={edge.marker}
            data-animated={edge.animated && "true"}
            data-points={edge.points != [] && Enum.map_join(edge.points, " ", fn [x, y] -> "#{x},#{y}" end)}
            data-mark-status={mark(@marks.edges, edge.id, :status)}
            data-mark-highlight={mark(@marks.edges, edge.id, :highlight) && "true"}
            data-mark-color={mark_color_value(@marks.edges, edge.id)}
            data-mark-dim={mark(@marks.edges, edge.id, :dim) && "true"}
            data-mark-title={mark(@marks.edges, edge.id, :title)}
            data-lit={lit?(@spotlight, :edges, edge.id) && "true"}
            data-diff={@diff.edges[edge.id]}
          >{if @edge_label_slot != [], do: render_slot(@edge_label_slot, edge)}</i>
        </div>
      </div>

      <div :if={@people != [] and @show_people} class="hakushi-people" data-hakushi-people>
        <.dynamic_tag
          :for={person <- @people}
          tag_name={if @follow, do: "button", else: "span"}
          {if @follow, do: %{type: "button"}, else: %{}}
          class="hakushi-person"
          data-person={person["id"]}
          data-issho-follow-control={@follow}
          title={person["name"]}
          aria-label={@follow && "Follow #{person["name"] || person["id"]}"}
          phx-mounted={JS.ignore_attributes(["aria-pressed"])}
          style={"--hakushi-person: #{person["color"]}"}
        >
          <%= if @person_slot != [] do %>
            {render_slot(@person_slot, person)}
          <% else %>
            <img :if={person["avatar"]} src={person["avatar"]} alt="" />
            <span :if={!person["avatar"]}>{initials(person["name"] || person["id"])}</span>
          <% end %>
        </.dynamic_tag>
      </div>
      <div
        :if={@empty_slot != [] and map_size(@graph.nodes) == 0}
        class="hakushi-empty"
      >
        {render_slot(@empty_slot)}
      </div>
      <div id={@id <> "-ui"} class="hakushi-ui" phx-update="ignore"></div>
      <form
        :if={@uploader && !@readonly}
        id={@id <> "-files"}
        class="hakushi-files"
        phx-change="hakushi:files"
        phx-submit="hakushi:files"
        phx-target={@myself}
        hidden
      >
        <.live_file_input upload={@uploads.hakushi_files} tabindex="-1" data-hakushi-files />
      </form>
      <div
        class="hakushi-notice"
        role="status"
        data-seq={@notice_seq}
        data-hakushi-notice={@notice && "true"}
      >
        {@notice}
      </div>
    </div>
    """
  end

  # A new node: a kit's for its items (`"schema:table"`), and for a double
  # click when the app makes none of its own; else the app's `new_node`.
  defp new_node(%{kits: kits, new_node: fun, messages: messages}, item, at) do
    with [name, kit_item] <- item && String.split(item, ":", parts: 2),
         kit when kit != nil <- Kit.by_name(kits, name) do
      kit.new_node(kit_item, at, messages)
    else
      _other ->
        cond do
          fun -> fun.(item, at)
          item == nil and kits != [] -> hd(kits).new_node(nil, at, messages)
          true -> nil
        end
    end
  end

  # The paper the canvas shows: its graph's, else its own attributes'.
  defp with_paper(%{graph: graph} = assigns) do
    paper = (graph && graph.paper) || %{}

    assign(assigns,
      paper_background: paper[:background] || to_string(assigns.background),
      paper_grid: paper[:grid] || assigns.grid
    )
  end

  # The papers of the picker, for a person who may change the paper, in
  # the canvas's words.
  defp papers(%{readonly: true}), do: []

  defp papers(assigns) do
    for %{name: name, label: label} <- Paper.offered(assigns.papers) do
      %{"name" => name, "label" => label || paper_label(assigns.messages, name)}
    end
  end

  defp paper_label(messages, name) do
    key = "paper" <> String.capitalize(name)
    messages[key] || name |> String.replace("-", " ") |> String.capitalize()
  end

  defp mark(marks, id, key) do
    case marks do
      %{^id => mark} -> Map.get(mark, key)
      _none -> nil
    end
  end

  defp lit?(nil, _kind, _id), do: false
  defp lit?(lit, kind, id), do: MapSet.member?(Map.fetch!(lit, kind), id)

  # A highlight of a colour of the app's own: the mark's colour.
  defp mark_color_value(marks, id) do
    case mark(marks, id, :highlight) do
      color when is_binary(color) -> color
      _other -> nil
    end
  end

  defp mark_color(marks, id) do
    case mark_color_value(marks, id) do
      nil -> ""
      color -> " --hakushi-mark: #{color};"
    end
  end

  defp node_style(node) do
    size =
      if node.width,
        do: "width: #{node.width}px; height: #{node.height}px;",
        else: ""

    "translate: #{node.x}px #{node.y}px; #{size}"
  end

  defp slot_for(slots, node),
    do: Enum.find(slots, &(&1[:type] == node.type)) || Enum.find(slots, &is_nil(&1[:type]))

  defp slot_flag?(slots, node, flag) do
    case slot_for(slots, node) do
      nil -> false
      slot -> slot[flag] == true
    end
  end

  # The app's slot for the node's type, then a kit's, then the app's slot
  # without a type, then a box with the node's label.
  defp node_content(assigns) do
    %{slots: slots, kits: kits, node: node} = assigns

    assigns =
      assign(assigns,
        slot: Enum.find(slots, &(&1[:type] == node.type)),
        kit: Kit.for_type(kits, node.type),
        any: Enum.find(slots, &is_nil(&1[:type]))
      )

    ~H"""
    <%= cond do %>
      <% @slot -> %>
        {render_slot([@slot], @node)}
      <% @kit -> %>
        <.kit_node
          kit={@kit}
          node={@node}
          canvas={@canvas}
          readonly={@readonly}
          drag_out={@drag_out}
          target={@target}
          messages={@messages}
        />
      <% @any -> %>
        {render_slot([@any], @node)}
      <% true -> %>
        <.default_node node={@node} />
    <% end %>
    """
  end

  # A kit's node component, called as a component (with change tracking).
  defp kit_node(assigns) do
    TagEngine.component(
      Function.capture(assigns.kit, :node, 1),
      Map.take(assigns, [:node, :canvas, :readonly, :drag_out, :target, :messages]),
      {__MODULE__, __ENV__.function, __ENV__.file, __ENV__.line}
    )
  end

  # A node's `resizable` or `group`: its slot's, else its kit's.
  defp node_flag?(slots, kits, node, flag) do
    case {Enum.find(slots, &(&1[:type] == node.type)), Kit.for_type(kits, node.type)} do
      {nil, kit} when kit != nil and flag == :resizable -> Kit.resizable?(kit, node.type)
      {nil, kit} when kit != nil and flag == :group -> Kit.group?(kit, node.type)
      _slot -> slot_flag?(slots, node, flag)
    end
  end

  defp default_node(assigns) do
    ~H"""
    <div class="hakushi-default-node">
      <Hakushi.Components.handle kind={:target} side={:left} />
      {label(@node)}
      <Hakushi.Components.handle kind={:source} side={:right} />
    </div>
    """
  end

  # The app's name of a node, else its kit's (a stroke is "Drawing"), else
  # the default's.
  defp node_label(fun, kits, messages, node) do
    if fun == (&__MODULE__.label/1),
      do: Kit.label(kits, node, messages) || fun.(node),
      else: fun.(node)
  end

  @doc false
  def label(%Node{data: data, id: id}) when is_map(data) do
    Map.get(data, :label) || Map.get(data, "label") || Map.get(data, :name) ||
      Map.get(data, "name") || id
  end

  def label(%Node{id: id}), do: id

  defp initials(name) do
    name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  # What the browser takes as files: the kit's upload, and whether an
  # address pasted is one.
  defp files_config(%{uploader: kit, readonly: false}) when kit != nil do
    %{
      "kit" => kit.name(),
      "accept" => Keyword.get(kit.upload(), :accept, []),
      "urls" => Kit.exports?(kit, :pasted, 3)
    }
  end

  defp files_config(_assigns), do: nil

  defp config(assigns) do
    %{
      "rules" => Rules.to_client(assigns.rules),
      "grid" => assigns.paper_grid,
      "background" => assigns.paper_background,
      "snap" => assigns.snap,
      "minimap" => assigns.minimap,
      "controls" => assigns.controls,
      "fit" => if(assigns.fit == :readable, do: "readable", else: assigns.fit),
      "minZoom" => assigns.min_zoom,
      "maxZoom" => assigns.max_zoom,
      "readonly" => assigns.readonly,
      "arrange" => assigns[:arrange] == true,
      "follow" => assigns.follow,
      "newNode" => assigns.new_node != nil or assigns.kits != [],
      "wheel" => Atom.to_string(assigns.wheel),
      "refit" => assigns.refit,
      "tidy" => assigns.tidy,
      "layout" => Atom.to_string(elem(assigns.layout, 1)),
      "algorithm" => Atom.to_string(elem(assigns.layout, 0)),
      "exportable" => assigns.export,
      "reportSelect" => assigns.on_select != nil or assigns.notify != nil,
      "reportView" => assigns.on_viewport != nil or assigns.notify != nil,
      "menu" => assigns.menu != nil and assigns.menu != false,
      "up" => assigns.on_up != nil,
      "clientTools" => Enum.map(assigns.client_tools, &to_string/1),
      "live" => assigns.join != nil,
      "user" => own_id(%{assigns: assigns}),
      "tools" => Kit.tools(assigns.kits, assigns.messages),
      "styles" => if(assigns.readonly, do: [], else: Kit.styles(assigns.kits, assigns.messages)),
      "papers" => papers(assigns),
      "files" => files_config(assigns),
      "paperGrids" => Paper.grids(),
      "messages" => assigns.messages,
      "locale" => assigns.locale
    }
  end
end
