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
    * `"hakushi:edit"` with `node`, `action` and the action's params: a
      change of a kit's node by its controls (`Hakushi.Kit`), whose data
      the kit gives.
    * `"hakushi:undo"` and `"hakushi:redo"`: the person's own changes,
      undone and done again as new changes, which the server checks again.
    * `"hakushi:peer"`, on a shared canvas: the person's cursor, the nodes
      they selected and the nodes they drag, for the others.

  On a shared canvas (`live`), the component is a session of an Issho
  room (`Hakushi.Issho`): its changes go to the room's document, and the
  room's events come back to it through `update/2`.
  """

  use Phoenix.LiveComponent

  alias Phoenix.LiveView.{JS, TagEngine}

  alias Hakushi.{Change, Commit, Graph, Kit, Messages, Node, Rules}

  # Issho is optional: a canvas without `live` never calls it.
  @compile {:no_warn_undefined, [Issho.Live, Hakushi.Issho]}

  # The changes of each person that undo can take back.
  @undo_limit 100
  # The most nodes one paste, duplicate or selection may name.
  @max_items 5_000
  # The colours of the people of a shared canvas with none of their own.
  @palette ~w(#e84a1c #2563eb #059669 #9333ea #d97706 #db2777 #0891b2 #65a30d)

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       graph: nil,
       given: nil,
       version: 0,
       shared: nil,
       undo: [],
       redo: [],
       clipboard: nil,
       people: [],
       follow: true,
       notice: nil,
       notice_seq: 0,
       configured: false
     )}
  end

  @impl true
  def update(%{issho: event}, socket), do: {:ok, receive_event(socket, event)}

  def update(%{hakushi_push: {event, payload}}, socket) do
    {:ok, push_event(socket, event, Map.put(payload, "canvas", socket.assigns.id))}
  end

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

        socket.assigns.shared ->
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
      {{instance, topic}, true} ->
        Hakushi.Live.ensure_mounted!(id)
        share(socket, instance, topic, graph)

      {{_instance, _topic}, false} ->
        Hakushi.Live.ensure_mounted!(id)
        reset(socket, graph)

      {nil, _connected} ->
        reset(socket, graph)
    end
  end

  defp start(_socket, other) do
    raise ArgumentError, "a canvas's graph must be a Hakushi.Graph, got: #{inspect(other)}"
  end

  # A shared canvas: a session of the room, and the room's document (this
  # canvas's graph, rules and on_change if it opens it first). A canvas the
  # room refuses shows why, and stays read-only on the graph it was given.
  defp share(socket, instance, topic, graph) do
    spec =
      Hakushi.Issho.spec(graph, socket.assigns.rules, socket.assigns.on_change, socket.assigns.id)

    with {:ok, _session} <- Issho.Live.join(instance, actor(socket), topic),
         {:ok, snapshot} <-
           Issho.Live.open(topic, topic, spec: spec, notify: {__MODULE__, socket.assigns.id}) do
      socket
      |> assign(shared: topic, version: snapshot["revision"])
      |> assign_people(people(topic))
      |> reset(snapshot["state"])
    else
      {:error, reason} ->
        socket
        |> assign(readonly: true, notice: Messages.reason(socket.assigns.messages, reason))
        |> reset(graph)
    end
  end

  # The actor of the room: the canvas's user, or someone anonymous.
  defp actor(socket) do
    case socket.assigns.user do
      nil -> %{id: "anonymous:" <> new_id()}
      user -> %{id: own_id(socket), name: Map.get(user, :name) || Map.get(user, "name")}
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

  # -- Events of the room -------------------------------------------------

  # A transaction of the room's document: its changes, in revision order.
  defp receive_event(socket, {"tx", _document, %{"revision" => revision, "ops" => changes}}) do
    if revision == socket.assigns.version + 1,
      do: socket |> apply_changes(changes) |> assign(:version, revision),
      else: resync(socket)
  end

  defp receive_event(socket, {"presence_diff", topic, _diff}),
    do: assign_people(socket, people(topic))

  # The others' cursors, selections and drags, as the browser draws them.
  defp receive_event(socket, {"aware", _topic, %{"states" => states}}) do
    own = own_id(socket)

    Enum.reduce(states, socket, fn
      {_session, %{"key" => ^own}}, socket ->
        socket

      {_session, %{"key" => person, "state" => state}}, socket ->
        push_event(
          socket,
          "hakushi:peer",
          Map.merge(state, %{"canvas" => socket.assigns.id, "person" => person})
        )
    end)
  end

  defp receive_event(socket, {"bye", _topic, reason}) do
    socket
    |> assign(shared: nil, readonly: true)
    |> assign(:notice, Messages.reason(socket.assigns.messages, bye_reason(reason)))
  end

  defp receive_event(socket, _event), do: socket

  defp apply_changes(socket, changes) do
    Enum.reduce_while(changes, socket, fn change, socket ->
      case Graph.apply(socket.assigns.graph, change) do
        {:ok, graph, change, _inverse} -> {:cont, show(socket, graph, change)}
        {:error, _reason, _id} -> {:halt, resync(socket)}
      end
    end)
  end

  defp bye_reason("revoked"), do: :revoked
  defp bye_reason("unauthorized"), do: :unauthorized
  defp bye_reason(_other), do: :failed

  # The changes came out of order (a node of a cluster that fell behind):
  # the room's graph, whole.
  defp resync(%{assigns: %{shared: topic}} = socket) when is_binary(topic) do
    case Issho.Live.read(topic, topic) do
      {:ok, %{"state" => graph, "revision" => revision}} ->
        socket |> assign(:version, revision) |> reset(graph)

      {:error, _reason} ->
        socket
    end
  end

  defp resync(socket), do: socket

  # The people of the room, each once, as the canvas draws them.
  defp people(topic) do
    for {key, %{metas: [meta | _]}} <- Issho.Live.people(topic) do
      %{
        "id" => key,
        "name" => meta["name"],
        "color" => meta["color"] || color(key),
        "avatar" => meta["avatar"]
      }
    end
  end

  @doc false
  def color(id), do: Enum.at(@palette, :erlang.phash2(id, length(@palette)))

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

    case new_node(socket.assigns, item, {x, y}) do
      nil ->
        {:reply, %{"ok" => false}, socket}

      node ->
        node = node |> with_id() |> Node.new() |> in_group(socket.assigns.graph, params["parent"])
        socket |> commit(Change.add([node]), true) |> reply(%{"select" => [node.id]})
    end
  end

  def handle_event("hakushi:edit", %{"node" => id, "action" => action} = params, socket)
      when is_binary(id) and is_binary(action) do
    with %Node{} = node <- Graph.node(socket.assigns.graph, id),
         kit when kit != nil <- Kit.for_type(socket.assigns.kits, node.type),
         {:ok, data} <- kit.edit(action, params, Kit.stringify(node.data)) do
      if data == node.data,
        do: {:reply, %{"ok" => true}, socket},
        else: socket |> commit(Change.update(nodes: [%{id: id, data: data}]), true) |> reply()
    else
      _refused -> {:reply, %{"ok" => false}, socket}
    end
  end

  def handle_event("hakushi:undo", _params, socket),
    do: step(socket, :undo, :redo, "nothingToUndo")

  def handle_event("hakushi:redo", _params, socket),
    do: step(socket, :redo, :undo, "nothingToRedo")

  # Issho's awareness sends the room one frame of what changed every 50 ms,
  # whatever the browser sends.
  def handle_event("hakushi:peer", params, %{assigns: %{shared: topic}} = socket)
      when is_binary(topic) and is_map(params) do
    # Merged: the LiveView's other components in the room keep their keys.
    Issho.Live.merge(topic, peer_state(params))
    {:noreply, socket}
  end

  def handle_event("hakushi:peer", _params, socket), do: {:noreply, socket}

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

  # A change, here or through the room of a shared canvas: the one place
  # where the two differ. A person's own change (`record`) goes on their
  # undo list. On a shared canvas, its inverse is of the graph this canvas
  # has; the change itself shows when the room sends it back.
  defp commit(socket, %Change{} = change, record) do
    change = if record, do: %{change | by: person(socket)}, else: change

    result =
      case socket.assigns.shared do
        nil ->
          Commit.run(socket.assigns.graph, change, %{
            rules: socket.assigns.rules,
            on_change: socket.assigns.on_change,
            canvas: socket.assigns.id
          })

        topic ->
          with {:ok, _graph, _change, inverse} <-
                 Commit.check_and_apply(socket.assigns.graph, change, socket.assigns.rules),
               {:ok, _receipt} <- Issho.Live.transact(topic, topic, [change]) do
            {:ok, inverse}
          end
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
  defp peer_state(params) do
    %{
      "cursor" => numbers(params["cursor"], 2),
      "selected" => params |> Map.get("selected", []) |> ids_only(),
      # What the person's canvas shows (its top left corner, width and height,
      # in the canvas's terms), for those who follow them.
      "view" => numbers(params["view"], 4),
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
            class="hakushi-node"
            data-id={node.id}
            data-type={node.type}
            data-x={node.x}
            data-y={node.y}
            data-width={node.width}
            data-height={node.height}
            data-locked={node.locked && "true"}
            data-resizable={resizable?(@node_slots, @kits, node) && "true"}
            data-group={slot_flag?(@node_slots, node, :group) && "true"}
            data-parent={node.parent}
            style={node_style(node)}
            tabindex="-1"
            role="group"
            aria-roledescription={@messages["node"]}
            aria-label={@node_label.(node)}
          >
            <.node_content
              slots={@node_slots}
              kits={@kits}
              node={node}
              readonly={@readonly}
              canvas={@id}
              target={@myself}
              messages={@messages}
            />
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
      Map.take(assigns, [:node, :canvas, :readonly, :target, :messages]),
      {__MODULE__, __ENV__.function, __ENV__.file, __ENV__.line}
    )
  end

  defp resizable?(slots, kits, node) do
    case {Enum.find(slots, &(&1[:type] == node.type)), Kit.for_type(kits, node.type)} do
      {nil, kit} when kit != nil -> Kit.resizable?(kit, node.type)
      _slot -> slot_flag?(slots, node, :resizable)
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
      "follow" => assigns.follow,
      "newNode" => assigns.new_node != nil or assigns.kits != [],
      "wheel" => Atom.to_string(assigns.wheel),
      "refit" => assigns.refit,
      "layout" => Atom.to_string(assigns.layout),
      "exportable" => assigns.export,
      "live" => assigns.live != nil,
      "user" => own_id(%{assigns: assigns}),
      "messages" => assigns.messages,
      "locale" => assigns.locale
    }
  end
end
