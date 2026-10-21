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
      canvas's `new_node` function.
    * `"hakushi:undo"` and `"hakushi:redo"`: the person's own changes,
      undone and done again as new changes, which the server checks again.
    * `"hakushi:peer"`, on a shared canvas: the person's cursor, the nodes
      they selected and the nodes they drag, for the others.
  """

  use Phoenix.LiveComponent

  alias Phoenix.LiveView.JS

  alias Hakushi.{Change, Commit, Graph, Messages, Node, Room, Rules}

  # The changes of each person that undo can take back.
  @undo_limit 100
  # The most nodes one paste, duplicate or selection may name.
  @max_items 5_000
  # The least time between two broadcasts of a person's cursor, in ms.
  @peer_interval 40

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       graph: nil,
       given: nil,
       version: 0,
       room: nil,
       undo: [],
       redo: [],
       clipboard: nil,
       people: [],
       notice: nil,
       notice_seq: 0,
       configured: false
     )}
  end

  @impl true
  def update(%{hakushi: message}, socket), do: {:ok, receive_message(socket, message)}

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

    socket =
      cond do
        not socket.assigns.configured ->
          start(socket, assigns.graph)

        socket.assigns.room ->
          socket

        assigns.graph != socket.assigns.given ->
          socket |> assign(:given, assigns.graph) |> replace(assigns.graph)

        true ->
          socket
      end

    {:ok, socket}
  end

  defp start(socket, %Graph{} = graph) do
    id = socket.assigns.id

    socket =
      socket
      |> assign(configured: true, given: graph)
      |> stream_configure(:nodes, dom_id: &node_dom_id(id, &1.id))
      |> stream_configure(:edges, dom_id: &edge_dom_id(id, &1.id))

    case {socket.assigns.live, connected?(socket)} do
      {{pubsub, topic}, true} ->
        Hakushi.Live.ensure_mounted!(id)
        if Hakushi.Live.register(topic, id) == :new, do: Phoenix.PubSub.subscribe(pubsub, topic)

        {:ok, room, graph, version, people} =
          Room.join(%{
            topic: topic,
            pubsub: pubsub,
            graph: graph,
            rules: socket.assigns.rules,
            on_change: socket.assigns.on_change,
            canvas: id,
            user: socket.assigns.user
          })

        socket
        |> assign(room: room, version: version)
        |> assign_people(people)
        |> reset(graph)

      {{_pubsub, _topic}, false} ->
        Hakushi.Live.ensure_mounted!(id)
        reset(socket, graph)

      {nil, _connected} ->
        reset(socket, graph)
    end
  end

  defp start(_socket, other) do
    raise ArgumentError, "a canvas's graph must be a Hakushi.Graph, got: #{inspect(other)}"
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

  # -- Messages of the room ------------------------------------------------

  defp receive_message(socket, {:changed, version, change}) do
    if version == socket.assigns.version + 1 do
      case Graph.apply(socket.assigns.graph, change) do
        {:ok, graph, change, _inverse} ->
          socket |> assign(:version, version) |> show(graph, change)

        {:error, _reason, _id} ->
          resync(socket)
      end
    else
      resync(socket)
    end
  end

  defp receive_message(socket, {:people, people}), do: assign_people(socket, people)

  defp receive_message(socket, {:peer, person, state}) do
    if person == own_id(socket),
      do: socket,
      else:
        push_event(
          socket,
          "hakushi:peer",
          Map.merge(state, %{"canvas" => socket.assigns.id, "person" => person})
        )
  end

  defp receive_message(socket, _message), do: socket

  # The changes came out of order (a node of a cluster that fell behind):
  # the room's graph, whole.
  defp resync(%{assigns: %{live: {_pubsub, topic}}} = socket) do
    case Room.graph(topic) do
      nil -> socket
      graph -> reset(socket, graph)
    end
  end

  defp assign_people(socket, people) do
    own = own_id(socket)
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

  # -- Events of the browser -----------------------------------------------

  @impl true
  def handle_event(event, _params, %{assigns: %{readonly: true}} = socket)
      when event != "hakushi:peer" do
    {:reply, %{"error" => Messages.reason(socket.assigns.messages, :readonly)}, socket}
  end

  def handle_event("hakushi:change", params, socket) when is_map(params) do
    case Change.from_client(params) do
      {:ok, change} -> reply(commit(socket, change, true))
      :error -> {:reply, %{"error" => Messages.reason(socket.assigns.messages, :failed)}, socket}
    end
  end

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

    case socket.assigns.new_node && socket.assigns.new_node.(item, {x, y}) do
      nil ->
        {:reply, %{"ok" => false}, socket}

      node ->
        node = node |> with_id() |> Node.new()
        socket |> commit(Change.add([node]), true) |> reply(%{"select" => [node.id]})
    end
  end

  def handle_event("hakushi:undo", _params, socket),
    do: step(socket, :undo, :redo, "nothingToUndo")

  def handle_event("hakushi:redo", _params, socket),
    do: step(socket, :redo, :undo, "nothingToRedo")

  def handle_event("hakushi:peer", params, %{assigns: %{live: {pubsub, topic}}} = socket)
      when is_map(params) do
    # The browser sends at most one every 50 ms; a browser that sends more
    # is not broadcast to the others more often than that.
    now = System.monotonic_time(:millisecond)
    key = {__MODULE__, :peer, socket.assigns.id}

    last = Process.get(key)

    if is_nil(last) or now - last >= @peer_interval do
      Process.put(key, now)

      Phoenix.PubSub.broadcast_from(
        pubsub,
        self(),
        topic,
        {:hakushi, topic, {:peer, own_id(socket), peer_state(params)}}
      )
    end

    {:noreply, socket}
  end

  def handle_event("hakushi:peer", _params, socket), do: {:noreply, socket}

  # The nodes of the ids, with the edges between them.
  defp copy(graph, ids) do
    ids = ids |> Enum.filter(&is_binary/1) |> Enum.take(@max_items) |> MapSet.new()
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

    nodes = Enum.map(nodes, &%{&1 | id: ids[&1.id], x: &1.x + dx, y: &1.y + dy, locked: false})

    edges =
      Enum.map(edges, fn edge ->
        %{edge | id: new_id(), source: ids[edge.source], target: ids[edge.target]}
      end)

    socket
    |> commit(Change.add(nodes, edges), true)
    |> reply(%{"select" => Enum.map(nodes, & &1.id)})
  end

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
  defp stepped({socket, {:ok, inverse}}, change, to) do
    {node_ids, _edge_ids} = Change.ids(change)
    select = if change.op == :delete, do: [], else: node_ids
    {:reply, %{"ok" => true, "select" => select}, update(socket, to, &[inverse | &1])}
  end

  defp stepped({socket, {:error, message}}, _change, _to),
    do: {:reply, %{"error" => message}, socket}

  defp reply(result, extra \\ %{})

  defp reply({socket, {:ok, _inverse}}, extra),
    do: {:reply, Map.merge(%{"ok" => true}, extra), socket}

  defp reply({socket, {:error, message}}, _extra), do: {:reply, %{"error" => message}, socket}

  # A change, through the room of a shared canvas or here. A person's own
  # change (`record`) goes on their undo list.
  defp commit(socket, %Change{} = change, record) do
    change = if record, do: %{change | by: person(socket)}, else: change

    result =
      case socket.assigns.room do
        nil ->
          case Commit.run(socket.assigns.graph, change, %{
                 rules: socket.assigns.rules,
                 on_change: socket.assigns.on_change,
                 canvas: socket.assigns.id
               }) do
            {:ok, graph, change, inverse} -> {:ok, graph, change, inverse}
            {:error, reason} -> {:error, reason}
          end

        room ->
          Room.commit(room, change)
      end

    case result do
      {:ok, graph, change, inverse} ->
        socket = socket |> show(graph, change) |> clear_notice() |> remember(record, inverse)
        {socket, {:ok, inverse}}

      {:ok, inverse} ->
        {socket |> clear_notice() |> remember(record, inverse), {:ok, inverse}}

      {:error, reason} ->
        message = Messages.reason(socket.assigns.messages, reason)

        {socket |> assign(notice: message, notice_seq: socket.assigns.notice_seq + 1),
         {:error, message}}
    end
  end

  defp remember(socket, false, _inverse), do: socket

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
  defp peer_state(params) do
    %{
      "cursor" =>
        case params["cursor"] do
          [x, y] when is_number(x) and is_number(y) -> [x, y]
          _other -> nil
        end,
      "selected" => params |> Map.get("selected", []) |> ids_only(),
      "dragging" =>
        params
        |> Map.get("dragging", [])
        |> List.wrap()
        |> Enum.take(@max_items)
        |> Enum.filter(
          &match?([id, x, y] when is_binary(id) and is_number(x) and is_number(y), &1)
        )
    }
  end

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
    assigns = assign(assigns, :config, JSON.encode!(config(assigns)))

    ~H"""
    <div
      id={@id}
      class={["hakushi", @class]}
      phx-mounted={JS.ignore_attributes(["style", "data-ui-*"])}
      data-background={@background}
      role="application"
      tabindex="0"
      aria-roledescription={@messages["canvas"]}
      aria-label={@label}
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
            class="hakushi-node"
            data-id={node.id}
            data-type={node.type}
            data-x={node.x}
            data-y={node.y}
            data-width={node.width}
            data-height={node.height}
            data-locked={node.locked && "true"}
            data-resizable={resizable?(@node_slots, node) && "true"}
            style={node_style(node)}
            tabindex="-1"
            role="group"
            aria-roledescription={@messages["node"]}
            aria-label={@node_label.(node)}
          >
            <.node_content slots={@node_slots} node={node} />
          </div>
        </div>
        <div id={@id <> "-labels"} class="hakushi-labels" phx-update="ignore"></div>
      </div>
      <div id={@id <> "-edge-data"} phx-update="stream" hidden>
        <i
          :for={{dom_id, edge} <- @streams.edges}
          id={dom_id}
          data-id={edge.id}
          data-source={edge.source}
          data-source-handle={edge.source_handle}
          data-target={edge.target}
          data-target-handle={edge.target_handle}
          data-path={edge.path}
          data-label={edge.label}
          data-marker={edge.marker}
          data-animated={edge.animated && "true"}
        ></i>
      </div>
      <div :if={@people != []} class="hakushi-people" data-hakushi-people>
        <span
          :for={person <- @people}
          class="hakushi-person"
          data-person={person["id"]}
          title={person["name"]}
          style={"--hakushi-person: #{person["color"]}"}
        >
          <%= if @person_slot != [] do %>
            {render_slot(@person_slot, person)}
          <% else %>
            <img :if={person["avatar"]} src={person["avatar"]} alt="" />
            <span :if={!person["avatar"]}>{initials(person["name"] || person["id"])}</span>
          <% end %>
        </span>
      </div>
      <div
        :if={@empty_slot != [] and map_size(@graph.nodes) == 0}
        class="hakushi-empty"
      >
        {render_slot(@empty_slot)}
      </div>
      <div id={@id <> "-ui"} class="hakushi-ui" phx-update="ignore"></div>
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

  defp node_style(node) do
    size =
      if node.width,
        do: "width: #{node.width}px; height: #{node.height}px;",
        else: ""

    "translate: #{node.x}px #{node.y}px; #{size}"
  end

  defp slot_for(slots, node),
    do: Enum.find(slots, &(&1[:type] == node.type)) || Enum.find(slots, &is_nil(&1[:type]))

  defp resizable?(slots, node) do
    case slot_for(slots, node) do
      nil -> false
      slot -> slot[:resizable] == true
    end
  end

  defp node_content(assigns) do
    slots = assigns.slots
    node = assigns.node

    assigns =
      assign(
        assigns,
        :slot,
        Enum.find(slots, &(&1[:type] == node.type)) || Enum.find(slots, &is_nil(&1[:type]))
      )

    ~H"""
    <%= if @slot do %>
      {render_slot([@slot], @node)}
    <% else %>
      <.default_node node={@node} />
    <% end %>
    """
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

  defp config(assigns) do
    %{
      "rules" => Rules.to_client(assigns.rules),
      "grid" => assigns.grid,
      "snap" => assigns.snap,
      "minimap" => assigns.minimap,
      "controls" => assigns.controls,
      "fit" => assigns.fit,
      "minZoom" => assigns.min_zoom,
      "maxZoom" => assigns.max_zoom,
      "readonly" => assigns.readonly,
      "newNode" => assigns.new_node != nil,
      "wheel" => Atom.to_string(assigns.wheel),
      "live" => assigns.live != nil,
      "user" => own_id(%{assigns: assigns}),
      "messages" => assigns.messages,
      "locale" => assigns.locale
    }
  end
end
