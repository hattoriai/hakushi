defmodule Hakushi.Graph do
  @moduledoc """
  The nodes and edges of a canvas.

      graph =
        Hakushi.Graph.new(
          nodes: [
            %{id: "users", type: "table", x: 0, y: 0, data: %{name: "users"}},
            %{id: "orders", type: "table", x: 320, y: 40, data: %{name: "orders"}}
          ],
          edges: [%{source: "orders", source_handle: "user_id", target: "users", target_handle: "id"}]
        )

  A graph keeps the order of its nodes, which is the order in which they
  are drawn: a node drawn later is over the ones before it. New nodes go
  last.

  `apply/2` applies a `Hakushi.Change` and gives back the change that
  undoes it; the canvas uses it for every change, and so can the app, to
  keep its own copy of the graph or to save it.

  `paper` is the canvas's paper when it has one of its own (people chose
  it with the canvas's picker, or the app did): a `Hakushi.Paper`, or `nil`
  for the canvas's `background` and `grid`.
  """

  alias Hakushi.{Change, Edge, Node, Paper}

  defstruct nodes: %{}, edges: %{}, node_order: [], edge_order: [], paper: nil

  @type t :: %__MODULE__{
          nodes: %{Node.id() => Node.t()},
          edges: %{Edge.id() => Edge.t()},
          node_order: [Node.id()],
          edge_order: [Edge.id()],
          paper: Paper.t() | nil
        }

  @typedoc "Why a change does not apply."
  @type reason :: :missing | :exists | :locked | :dangling | :nested

  @doc """
  Makes a graph of `nodes` and `edges`: `Hakushi.Node`s and
  `Hakushi.Edge`s, or maps and keyword lists for `Hakushi.Node.new/1` and
  `Hakushi.Edge.new/1`, and its `paper` (see `Hakushi.Paper.new/1`).
  Raises on two nodes or two edges with one id, and on an edge to a node
  the graph does not have.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    nodes = opts |> Keyword.get(:nodes, []) |> Enum.map(&Node.new/1)
    edges = opts |> Keyword.get(:edges, []) |> Enum.map(&Edge.new/1)
    paper = opts |> Keyword.get(:paper) |> Paper.new()

    case put_all(%__MODULE__{paper: paper}, nodes, edges) do
      {:ok, graph} -> graph
      {:error, reason, id} -> raise ArgumentError, "#{describe(reason)}: #{inspect(id)}"
    end
  end

  defp describe(:exists), do: "two nodes or two edges have the same id"
  defp describe(:dangling), do: "an edge joins a node that the graph does not have"

  @doc "The nodes, in the order they are drawn."
  @spec nodes(t()) :: [Node.t()]
  def nodes(%__MODULE__{nodes: nodes, node_order: order}),
    do: Enum.map(order, &Map.fetch!(nodes, &1))

  @doc "The edges, in the order they were made."
  @spec edges(t()) :: [Edge.t()]
  def edges(%__MODULE__{edges: edges, edge_order: order}),
    do: Enum.map(order, &Map.fetch!(edges, &1))

  @doc "The node of an id, or `nil`."
  @spec node(t(), Node.id()) :: Node.t() | nil
  def node(%__MODULE__{nodes: nodes}, id), do: Map.get(nodes, id)

  @doc "The edge of an id, or `nil`."
  @spec edge(t(), Edge.id()) :: Edge.t() | nil
  def edge(%__MODULE__{edges: edges}, id), do: Map.get(edges, id)

  @doc "The edges of a node: those that start or end at it."
  @spec edges_of(t(), Node.id()) :: [Edge.t()]
  def edges_of(%__MODULE__{} = graph, id),
    do: graph |> edges() |> Enum.filter(&(&1.source == id or &1.target == id))

  @doc """
  The box around the nodes, `{x, y, width, height}`, or `nil` for a graph
  without nodes. A node without a size counts as a point.
  """
  @spec bounds(t()) :: {number(), number(), number(), number()} | nil
  def bounds(%__MODULE__{nodes: nodes}) when map_size(nodes) == 0, do: nil

  def bounds(%__MODULE__{nodes: nodes}) do
    {x0, y0, x1, y1} =
      nodes
      |> Map.values()
      |> Enum.reduce({nil, nil, nil, nil}, fn node, {x0, y0, x1, y1} ->
        right = node.x + (node.width || 0)
        bottom = node.y + (node.height || 0)
        {min_or(x0, node.x), min_or(y0, node.y), max_or(x1, right), max_or(y1, bottom)}
      end)

    {x0, y0, x1 - x0, y1 - y0}
  end

  defp min_or(nil, value), do: value
  defp min_or(a, b), do: min(a, b)
  defp max_or(nil, value), do: value
  defp max_or(a, b), do: max(a, b)

  @doc """
  Applies a change. Gives back the graph, the change as it applied, and
  the change that undoes it:

    * a move of a node moves the nodes in it (`parent`) too, unless the
      change places them itself, and a move may put a node in a group or
      take it out (`:parent`); the change lists every node it moved;
    * a delete lists the nodes in its nodes, and the edges of all of
      them, which go with them;
    * the change that undoes a delete adds the nodes back, with their
      edges (over the other nodes, as new nodes are).

  A change does not apply, and nothing changes, when it names a node or an
  edge that the graph does not have (`:missing`), adds one it has
  (`:exists`), moves, resizes or deletes a locked node (`:locked`), or
  adds an edge to a node it does not have, or a node to a parent it does
  not have (`:dangling`), or puts a node in itself or in a node inside it
  (`:nested`). The error has the id.
  """
  @spec apply(t(), Change.t()) ::
          {:ok, t(), Change.t(), Change.t()} | {:error, reason(), String.t()}
  def apply(%__MODULE__{} = graph, %Change{op: op} = change) when op in [:add, :connect] do
    nodes = Enum.map(change.nodes, &Node.new/1)
    edges = Enum.map(change.edges, &Edge.new/1)

    with {:ok, applied} <- put_all(graph, nodes, edges) do
      change = %{change | nodes: nodes, edges: edges}

      inverse = %Change{
        op: :delete,
        nodes: Enum.map(nodes, & &1.id),
        edges: Enum.map(edges, & &1.id),
        by: change.by
      }

      {:ok, applied, change, inverse}
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :move, nodes: places} = change) do
    named = MapSet.new(places, & &1.id)

    Enum.reduce_while(places, {:ok, graph, [], []}, fn place, {:ok, graph, done, undo} ->
      case move(graph, place, named) do
        {:ok, graph, moved, old} -> {:cont, {:ok, graph, moved ++ done, old ++ undo}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, graph, done, undo} ->
        {:ok, graph, %{change | nodes: Enum.reverse(done)},
         %Change{op: :move, nodes: Enum.reverse(undo), by: change.by}}

      error ->
        error
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :reconnect, edges: ends} = change) do
    Enum.reduce_while(ends, {:ok, graph, []}, fn ends, {:ok, graph, undo} ->
      case reconnect(graph, ends) do
        {:ok, graph, old} -> {:cont, {:ok, graph, [old | undo]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, graph, undo} ->
        {:ok, graph, change, %Change{op: :reconnect, edges: Enum.reverse(undo), by: change.by}}

      error ->
        error
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :update} = change) do
    with {:ok, graph, node_undo} <-
           update_all(graph, :nodes, change.nodes, [
             :data,
             :type,
             :locked,
             :x,
             :y,
             :width,
             :height
           ]),
         {:ok, graph, edge_undo} <-
           update_all(graph, :edges, change.edges, [:label, :path, :marker, :animated, :data]) do
      {:ok, graph, change,
       %Change{op: :update, nodes: node_undo, edges: edge_undo, by: change.by}}
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :paper, paper: paper} = change) do
    paper = Paper.new(paper)

    {:ok, %{graph | paper: paper}, %{change | paper: paper},
     %Change{op: :paper, paper: graph.paper, by: change.by}}
  end

  def apply(%__MODULE__{} = graph, %Change{op: :delete} = change) do
    node_ids = change.nodes
    edge_ids = change.edges

    with :ok <- all_present(graph.nodes, node_ids),
         :ok <- all_present(graph.edges, edge_ids),
         node_ids = with_descendants(graph, node_ids),
         :ok <- none_locked(graph, node_ids) do
      gone = MapSet.new(node_ids)

      edge_ids =
        edge_ids ++
          for id <- graph.edge_order,
              id not in edge_ids,
              edge = Map.fetch!(graph.edges, id),
              MapSet.member?(gone, edge.source) or MapSet.member?(gone, edge.target),
              do: id

      gone_edges = MapSet.new(edge_ids)

      applied = %{
        graph
        | nodes: Map.drop(graph.nodes, node_ids),
          edges: Map.drop(graph.edges, edge_ids),
          node_order: Enum.reject(graph.node_order, &MapSet.member?(gone, &1)),
          edge_order: Enum.reject(graph.edge_order, &MapSet.member?(gone_edges, &1))
      }

      inverse = %Change{
        op: :add,
        nodes:
          for(id <- graph.node_order, MapSet.member?(gone, id), do: Map.fetch!(graph.nodes, id)),
        edges:
          for(
            id <- graph.edge_order,
            MapSet.member?(gone_edges, id),
            do: Map.fetch!(graph.edges, id)
          ),
        by: change.by
      }

      {:ok, applied, %{change | nodes: node_ids, edges: edge_ids}, inverse}
    end
  end

  # A node to its place (and size, and parent), with the nodes in it when it
  # moves and the change does not place them: the places it gave, and the
  # old ones for the undo.
  defp move(graph, place, named) do
    id = place.id

    with {:ok, node} <- fetch_node(graph, id),
         :ok <- unlocked(node),
         :ok <- parent_ok(graph, id, Map.get(place, :parent, node.parent)) do
      {moved, old} = place(node, place)
      graph = %{graph | nodes: Map.put(graph.nodes, id, moved)}
      {dx, dy} = {moved.x - node.x, moved.y - node.y}

      # A resize moves the corner, not the nodes inside.
      if Map.has_key?(place, :width) or (dx == 0 and dy == 0) do
        {:ok, graph, [place], [old]}
      else
        follow(graph, id, dx, dy, named, [place], [old])
      end
    end
  end

  defp follow(graph, id, dx, dy, named, done, undo) do
    graph
    |> descendants(id)
    |> Enum.reject(&MapSet.member?(named, &1))
    |> Enum.reduce({:ok, graph, done, undo}, fn child, {:ok, graph, done, undo} ->
      node = Map.fetch!(graph.nodes, child)
      moved = %{node | x: node.x + dx, y: node.y + dy}

      {:ok, %{graph | nodes: Map.put(graph.nodes, child, moved)},
       [%{id: child, x: moved.x, y: moved.y} | done], [%{id: child, x: node.x, y: node.y} | undo]}
    end)
  end

  defp place(node, place) do
    moved = %{node | x: place.x, y: place.y}
    old = %{id: node.id, x: node.x, y: node.y}

    {moved, old} =
      case place do
        %{width: width, height: height} ->
          {%{moved | width: width, height: height},
           Map.merge(old, %{width: node.width, height: node.height})}

        _place ->
          {moved, old}
      end

    case place do
      %{parent: parent} -> {%{moved | parent: parent}, Map.put(old, :parent, node.parent)}
      _place -> {moved, old}
    end
  end

  defp fetch_node(graph, id) do
    case Map.fetch(graph.nodes, id) do
      {:ok, node} -> {:ok, node}
      :error -> {:error, :missing, id}
    end
  end

  defp unlocked(%Node{locked: true, id: id}), do: {:error, :locked, id}
  defp unlocked(_node), do: :ok

  # A parent the graph has, which is neither the node nor inside it.
  defp parent_ok(_graph, _id, nil), do: :ok

  defp parent_ok(graph, id, parent) do
    cond do
      not Map.has_key?(graph.nodes, parent) -> {:error, :dangling, parent}
      parent == id or parent in descendants(graph, id) -> {:error, :nested, parent}
      true -> :ok
    end
  end

  defp reconnect(graph, %{id: id} = ends) do
    with {:ok, edge} <- fetch_edge(graph, id),
         :ok <- present_node(graph, Map.get(ends, :source, edge.source)),
         :ok <- present_node(graph, Map.get(ends, :target, edge.target)) do
      fields = [:source, :source_handle, :target, :target_handle]
      changes = Map.take(ends, fields)
      old = Map.put(Map.take(edge, Map.keys(changes)), :id, id)
      {:ok, %{graph | edges: Map.put(graph.edges, id, struct!(edge, changes))}, old}
    end
  end

  defp fetch_edge(graph, id) do
    case Map.fetch(graph.edges, id) do
      {:ok, edge} -> {:ok, edge}
      :error -> {:error, :missing, id}
    end
  end

  defp present_node(graph, id),
    do: if(Map.has_key?(graph.nodes, id), do: :ok, else: {:error, :dangling, id})

  @doc "The ids of the nodes in a node (its children), in the order they are drawn."
  @spec children(t(), Node.id()) :: [Node.id()]
  def children(%__MODULE__{} = graph, id),
    do: Enum.filter(graph.node_order, &(Map.fetch!(graph.nodes, &1).parent == id))

  @doc """
  The ids of the nodes in a node, and in those, all the way down, in the
  order they are drawn.
  """
  @spec descendants(t(), Node.id()) :: [Node.id()]
  def descendants(%__MODULE__{} = graph, id) do
    by_parent = Enum.group_by(Map.values(graph.nodes), & &1.parent, & &1.id)
    all = MapSet.new(collect(Map.get(by_parent, id, []), by_parent, []))
    Enum.filter(graph.node_order, &MapSet.member?(all, &1))
  end

  defp collect([], _by_parent, acc), do: Enum.reverse(acc)

  defp collect([id | rest], by_parent, acc),
    do: collect(Map.get(by_parent, id, []) ++ rest, by_parent, [id | acc])

  # The nodes, and the nodes in them, each once, in the graph's order.
  defp with_descendants(graph, ids) do
    by_parent = Enum.group_by(Map.values(graph.nodes), & &1.parent, & &1.id)
    all = ids |> collect_all(by_parent) |> MapSet.new()
    Enum.filter(graph.node_order, &MapSet.member?(all, &1))
  end

  defp collect_all(ids, by_parent),
    do: ids ++ collect(Enum.flat_map(ids, &Map.get(by_parent, &1, [])), by_parent, [])

  # Nodes, then edges, each checked against the graph as it grows.
  defp put_all(graph, nodes, edges) do
    with {:ok, graph} <- reduce_ok(nodes, graph, &put_node/2),
         {:ok, graph} <- reduce_ok(nodes, graph, &check_parent/2) do
      reduce_ok(edges, graph, &put_edge/2)
    end
  end

  defp check_parent(%Node{parent: nil}, graph), do: {:ok, graph}

  defp check_parent(%Node{id: id, parent: parent}, graph) do
    with :ok <- parent_ok(graph, id, parent), do: {:ok, graph}
  end

  defp reduce_ok(list, acc, fun) do
    Enum.reduce_while(list, {:ok, acc}, fn item, {:ok, acc} ->
      case fun.(item, acc) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp put_node(%Node{id: id} = node, graph) do
    if Map.has_key?(graph.nodes, id),
      do: {:error, :exists, id},
      else:
        {:ok,
         %{graph | nodes: Map.put(graph.nodes, id, node), node_order: graph.node_order ++ [id]}}
  end

  defp put_edge(%Edge{id: id} = edge, graph) do
    cond do
      Map.has_key?(graph.edges, id) ->
        {:error, :exists, id}

      not Map.has_key?(graph.nodes, edge.source) ->
        {:error, :dangling, edge.source}

      not Map.has_key?(graph.nodes, edge.target) ->
        {:error, :dangling, edge.target}

      true ->
        {:ok,
         %{graph | edges: Map.put(graph.edges, id, edge), edge_order: graph.edge_order ++ [id]}}
    end
  end

  defp update_all(graph, key, items, fields) do
    Enum.reduce_while(items, {:ok, graph, []}, fn item, {:ok, graph, undo} ->
      items = Map.fetch!(graph, key)

      case Map.fetch(items, item.id) do
        :error ->
          {:halt, {:error, :missing, item.id}}

        {:ok, current} ->
          changes = Map.take(item, fields)
          old = Map.merge(Map.take(current, Map.keys(changes)), %{id: item.id})

          {:cont,
           {:ok, Map.put(graph, key, Map.put(items, item.id, struct!(current, changes))),
            [old | undo]}}
      end
    end)
    |> case do
      {:ok, graph, undo} -> {:ok, graph, Enum.reverse(undo)}
      error -> error
    end
  end

  defp all_present(map, ids) do
    case Enum.find(ids, &(not Map.has_key?(map, &1))) do
      nil -> :ok
      id -> {:error, :missing, id}
    end
  end

  defp none_locked(graph, ids) do
    case Enum.find(ids, &Map.fetch!(graph.nodes, &1).locked) do
      nil -> :ok
      id -> {:error, :locked, id}
    end
  end

  # -- Paths ----------------------------------------------------------------
  #
  # The graph read along its edges, from source to target: what comes
  # after a node, before it, the order of a flow, the way from one node to
  # another. Pure, and in the graph's order wherever there is a choice.

  @doc """
  The ids of the nodes an edge goes to from the node `id`, each once, in
  the order of the edges.

      iex> graph = Hakushi.Graph.new(nodes: [%{id: "a"}, %{id: "b"}, %{id: "c"}], edges: [%{source: "a", target: "c"}, %{source: "a", target: "b"}])
      iex> Hakushi.Graph.successors(graph, "a")
      ["c", "b"]
  """
  @spec successors(t(), Node.id()) :: [Node.id()]
  def successors(%__MODULE__{} = graph, id),
    do:
      graph |> edges() |> Enum.filter(&(&1.source == id)) |> Enum.map(& &1.target) |> Enum.uniq()

  @doc "The ids of the nodes an edge comes from to the node `id`, each once, in the order of the edges."
  @spec predecessors(t(), Node.id()) :: [Node.id()]
  def predecessors(%__MODULE__{} = graph, id),
    do:
      graph |> edges() |> Enum.filter(&(&1.target == id)) |> Enum.map(& &1.source) |> Enum.uniq()

  @doc """
  The ids of every node the edges lead to from the node `id`, however far
  (what a step sets off, what a table's rows are used by), nearest first,
  without `id` itself unless a cycle comes back to it.
  """
  @spec downstream(t(), Node.id()) :: [Node.id()]
  def downstream(%__MODULE__{} = graph, id), do: reach(outgoing(graph), id)

  @doc """
  The ids of every node whose edges lead to the node `id`, however far
  (what a step waits for), nearest first, without `id` itself unless a
  cycle comes back to it.
  """
  @spec upstream(t(), Node.id()) :: [Node.id()]
  def upstream(%__MODULE__{} = graph, id), do: reach(incoming(graph), id)

  @doc "The ids of the nodes no edge goes to (where a flow starts), in the order they are drawn."
  @spec roots(t()) :: [Node.id()]
  def roots(%__MODULE__{} = graph) do
    targets = MapSet.new(Map.values(graph.edges), & &1.target)
    Enum.reject(graph.node_order, &MapSet.member?(targets, &1))
  end

  @doc "The ids of the nodes no edge leaves (where a flow ends), in the order they are drawn."
  @spec leaves(t()) :: [Node.id()]
  def leaves(%__MODULE__{} = graph) do
    sources = MapSet.new(Map.values(graph.edges), & &1.source)
    Enum.reject(graph.node_order, &MapSet.member?(sources, &1))
  end

  @doc """
  The ids of every node, each after the nodes its edges come from: the
  order a flow runs in, the order to create a schema's tables in. Of the
  nodes that may come next, the one drawn first does. A graph with a
  cycle has no such order: `{:error, {:cycle, ids}}` gives one.

      iex> graph = Hakushi.Graph.new(nodes: [%{id: "pay"}, %{id: "start"}, %{id: "send"}], edges: [%{source: "start", target: "pay"}, %{source: "pay", target: "send"}])
      iex> Hakushi.Graph.topological_sort(graph)
      {:ok, ["start", "pay", "send"]}
  """
  @spec topological_sort(t()) :: {:ok, [Node.id()]} | {:error, {:cycle, [Node.id()]}}
  def topological_sort(%__MODULE__{} = graph) do
    out = outgoing(graph)
    rank = graph.node_order |> Enum.with_index() |> Map.new()

    degrees =
      Enum.reduce(Map.values(graph.edges), Map.new(graph.node_order, &{&1, 0}), fn edge, acc ->
        Map.update!(acc, edge.target, &(&1 + 1))
      end)

    ready =
      :gb_sets.from_list(
        for id <- graph.node_order, Map.fetch!(degrees, id) == 0, do: {Map.fetch!(rank, id), id}
      )

    case kahn(ready, degrees, out, rank, []) do
      sorted when length(sorted) == map_size(graph.nodes) -> {:ok, sorted}
      _short -> {:error, {:cycle, cycle(graph)}}
    end
  end

  defp kahn(ready, degrees, out, rank, sorted) do
    if :gb_sets.is_empty(ready) do
      Enum.reverse(sorted)
    else
      {{_rank, id}, ready} = :gb_sets.take_smallest(ready)

      {ready, degrees} =
        out |> Map.get(id, []) |> Enum.reduce({ready, degrees}, &release(&1, &2, rank))

      kahn(ready, degrees, out, rank, [id | sorted])
    end
  end

  # One edge fewer to wait for: a node with none left may come next.
  defp release(next, {ready, degrees}, rank) do
    degrees = Map.update!(degrees, next, &(&1 - 1))

    if Map.fetch!(degrees, next) == 0,
      do: {:gb_sets.add({Map.fetch!(rank, next), next}, ready), degrees},
      else: {ready, degrees}
  end

  @doc """
  A cycle of the graph, the ids of its nodes in the order the edges go
  (the last one has an edge back to the first), or `nil` for a graph
  without one. An edge from a node to itself is a cycle of that node.
  """
  @spec cycle(t()) :: [Node.id()] | nil
  def cycle(%__MODULE__{} = graph) do
    out = outgoing(graph)

    Enum.reduce_while(graph.node_order, %{}, fn id, colors ->
      case visit(id, out, colors, []) do
        {:cycle, ids} -> {:halt, {:cycle, ids}}
        {:ok, colors} -> {:cont, colors}
      end
    end)
    |> case do
      {:cycle, ids} -> ids
      _colors -> nil
    end
  end

  # A depth-first walk: a node on the way (:open) met again closes a cycle.
  defp visit(id, out, colors, way) do
    case Map.get(colors, id) do
      :done ->
        {:ok, colors}

      :open ->
        {:cycle, way |> Enum.reverse() |> Enum.drop_while(&(&1 != id))}

      nil ->
        out
        |> Map.get(id, [])
        |> visit_all(out, Map.put(colors, id, :open), [id | way])
        |> case do
          {:ok, colors} -> {:ok, Map.put(colors, id, :done)}
          cycle -> cycle
        end
    end
  end

  defp visit_all([], _out, colors, _way), do: {:ok, colors}

  defp visit_all([next | rest], out, colors, way) do
    case visit(next, out, colors, way) do
      {:ok, colors} -> visit_all(rest, out, colors, way)
      cycle -> cycle
    end
  end

  @doc """
  The shortest way from the node `from` to the node `to` along the edges:
  the ids of its nodes, from `from` to `to`, or `nil` when there is none.
  `directed: false` goes along the edges either way. A node's way to
  itself is `[id]`.

      iex> graph = Hakushi.Graph.new(nodes: [%{id: "a"}, %{id: "b"}, %{id: "c"}], edges: [%{source: "a", target: "b"}, %{source: "b", target: "c"}])
      iex> Hakushi.Graph.path(graph, "a", "c")
      ["a", "b", "c"]
      iex> Hakushi.Graph.path(graph, "c", "a")
      nil
      iex> Hakushi.Graph.path(graph, "c", "a", directed: false)
      ["c", "b", "a"]
  """
  @spec path(t(), Node.id(), Node.id(), keyword()) :: [Node.id()] | nil
  def path(%__MODULE__{} = graph, from, to, opts \\ []) do
    cond do
      not Map.has_key?(graph.nodes, from) or not Map.has_key?(graph.nodes, to) -> nil
      from == to -> [from]
      true -> bfs(neighbours(graph, opts), :queue.from_list([from]), %{from => nil}, to)
    end
  end

  defp bfs(next, queue, came, to) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        nil

      {{:value, id}, queue} ->
        fresh = next |> Map.get(id, []) |> Enum.reject(&Map.has_key?(came, &1))
        came = Enum.reduce(fresh, came, &Map.put(&2, &1, id))

        if Map.has_key?(came, to),
          do: back(came, to, []),
          else: bfs(next, Enum.reduce(fresh, queue, &:queue.in/2), came, to)
    end
  end

  defp back(_came, nil, way), do: way
  defp back(came, id, way), do: back(came, Map.fetch!(came, id), [id | way])

  @doc """
  The ids of the edges along a way of nodes (as `path/4` gives it): for
  each two nodes after each other, the first edge between them, from the
  one to the other (or the other way with `directed: false`). For a
  spotlight on a path (`Hakushi.Live.spotlight/2`).
  """
  @spec edges_along(t(), [Node.id()], keyword()) :: [Edge.id()]
  def edges_along(%__MODULE__{} = graph, way, opts \\ []) when is_list(way) do
    directed = Keyword.get(opts, :directed, true)
    edges = edges(graph)

    way
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [a, b] ->
      case Enum.find(edges, &joins?(&1, a, b, directed)) do
        nil -> []
        edge -> [edge.id]
      end
    end)
  end

  defp joins?(edge, a, b, directed),
    do:
      (edge.source == a and edge.target == b) or
        (not directed and edge.source == b and edge.target == a)

  @doc """
  The parts of the graph that edges join, whichever way they go: a list of
  lists of ids, each in the order the nodes are drawn, the part of the
  first node first. A node with no edge is a part of its own.
  """
  @spec components(t()) :: [[Node.id()]]
  def components(%__MODULE__{} = graph) do
    next = neighbours(graph, directed: false)
    rank = graph.node_order |> Enum.with_index() |> Map.new()

    {parts, _seen} =
      Enum.reduce(graph.node_order, {[], MapSet.new()}, fn id, {parts, seen} ->
        if MapSet.member?(seen, id) do
          {parts, seen}
        else
          part = [id | reach(next, id)] |> Enum.uniq() |> Enum.sort_by(&Map.fetch!(rank, &1))
          {[part | parts], MapSet.union(seen, MapSet.new(part))}
        end
      end)

    Enum.reverse(parts)
  end

  # The ids each node's edges go to, and come from, in the order of the edges.
  defp outgoing(graph), do: adjacency(graph, & &1.source, & &1.target)
  defp incoming(graph), do: adjacency(graph, & &1.target, & &1.source)

  defp neighbours(graph, opts) do
    if Keyword.get(opts, :directed, true) do
      outgoing(graph)
    else
      Map.merge(outgoing(graph), incoming(graph), fn _id, out, in_ -> Enum.uniq(out ++ in_) end)
    end
  end

  defp adjacency(graph, from, to) do
    graph
    |> edges()
    |> Enum.group_by(from, to)
    |> Map.new(fn {id, ids} -> {id, Enum.uniq(ids)} end)
  end

  # Every node reached from `id`, nearest first.
  defp reach(next, id), do: reach(next, :queue.from_list(Map.get(next, id, [])), %{}, [])

  defp reach(next, queue, seen, found) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        Enum.reverse(found)

      {{:value, id}, queue} when is_map_key(seen, id) ->
        reach(next, queue, seen, found)

      {{:value, id}, queue} ->
        queue = Enum.reduce(Map.get(next, id, []), queue, &:queue.in/2)
        reach(next, queue, Map.put(seen, id, true), [id | found])
    end
  end

  @doc """
  What changed from one graph to another: the nodes and edges that are
  new or not the same, the ids of those that went away, and whether the
  paper changed.
  """
  @spec diff(t(), t()) :: %{
          nodes: [Node.t()],
          edges: [Edge.t()],
          deleted_nodes: [Node.id()],
          deleted_edges: [Edge.id()],
          paper: boolean()
        }
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    %{
      paper: old.paper != new.paper,
      nodes: for(node <- nodes(new), Map.get(old.nodes, node.id) != node, do: node),
      edges: for(edge <- edges(new), Map.get(old.edges, edge.id) != edge, do: edge),
      deleted_nodes: for(id <- old.node_order, not Map.has_key?(new.nodes, id), do: id),
      deleted_edges: for(id <- old.edge_order, not Map.has_key?(new.edges, id), do: id)
    }
  end

  @doc """
  The inside of a group, as a graph of its own: the nodes in the node
  `id` (`descendants/2`), those directly in it in no group, and the edges
  between them. The places are the group's: its top left corner is the
  new graph's `{0, 0}`. For a group opened as a canvas of its own (see the
  Drill-down guide); `put_subgraph/3` puts it back.

      iex> graph = Hakushi.Graph.new(nodes: [%{id: "frame", x: 100, y: 100, width: 400, height: 300}, %{id: "a", x: 120, y: 140, parent: "frame"}, %{id: "out", x: 0, y: 0}], edges: [%{source: "a", target: "out"}])
      iex> inside = Hakushi.Graph.subgraph(graph, "frame")
      iex> Enum.map(Hakushi.Graph.nodes(inside), &{&1.id, &1.x, &1.y, &1.parent})
      [{"a", 20, 40, nil}]
      iex> Hakushi.Graph.edges(inside)
      []
  """
  @spec subgraph(t(), Node.id()) :: t()
  def subgraph(%__MODULE__{} = graph, id) do
    group = Map.fetch!(graph.nodes, id)
    inside = descendants(graph, id)
    kept = MapSet.new(inside)

    nodes =
      for child <- inside do
        node = Map.fetch!(graph.nodes, child)
        parent = if node.parent == id, do: nil, else: node.parent
        %{node | x: node.x - group.x, y: node.y - group.y, parent: parent}
      end

    edges =
      for edge <- edges(graph),
          MapSet.member?(kept, edge.source) and MapSet.member?(kept, edge.target),
          do: edge

    new(nodes: nodes, edges: edges)
  end

  @doc """
  Puts the inside of a group back (`subgraph/2`'s, as it changed): the
  nodes now in the node `id` are those of `inside`, at their places in
  the group, and the edges between them are its edges. The edges from a
  node inside to one outside stay when both are still there. Raises when
  a node of `inside` has the id of a node outside the group.
  """
  @spec put_subgraph(t(), Node.id(), t()) :: t()
  def put_subgraph(%__MODULE__{} = graph, id, %__MODULE__{} = inside) do
    group = Map.fetch!(graph.nodes, id)
    old = MapSet.new(descendants(graph, id))

    outside = Enum.reject(nodes(graph), &MapSet.member?(old, &1.id))

    placed =
      for node <- nodes(inside) do
        %{node | x: node.x + group.x, y: node.y + group.y, parent: node.parent || id}
      end

    ids = MapSet.new(Enum.map(outside, & &1.id) ++ Enum.map(placed, & &1.id))

    crossing =
      for edge <- edges(graph),
          MapSet.member?(old, edge.source) != MapSet.member?(old, edge.target),
          MapSet.member?(ids, edge.source) and MapSet.member?(ids, edge.target),
          do: edge

    others =
      Enum.reject(
        edges(graph),
        &(MapSet.member?(old, &1.source) or MapSet.member?(old, &1.target))
      )

    new(nodes: outside ++ placed, edges: others ++ crossing ++ edges(inside), paper: graph.paper)
  end

  @doc """
  How one graph became another, for people to see (a visual diff, the
  versions of a canvas): the ids of the nodes and edges `added` and
  `removed`, those `moved` (a node's place or size), and those `changed`,
  with the fields that changed (a node's `:type`, `:data`, `:locked` or
  `:parent`; an edge's ends, `:label`, `:path`, `:marker`, `:animated` or
  `:data`). A node that moved and changed is in both. `paper` is whether
  the paper changed.

      iex> old = Hakushi.Graph.new(nodes: [%{id: "a"}, %{id: "b", data: %{n: 1}}])
      iex> new = Hakushi.Graph.new(nodes: [%{id: "b", x: 10, data: %{n: 2}}, %{id: "c"}])
      iex> Hakushi.Graph.compare(old, new)
      %{
        added: %{nodes: ["c"], edges: []},
        removed: %{nodes: ["a"], edges: []},
        moved: ["b"],
        changed: %{nodes: %{"b" => [:data]}, edges: %{}},
        paper: false
      }
  """
  @spec compare(t(), t()) :: %{
          added: %{nodes: [Node.id()], edges: [Edge.id()]},
          removed: %{nodes: [Node.id()], edges: [Edge.id()]},
          moved: [Node.id()],
          changed: %{nodes: %{Node.id() => [atom()]}, edges: %{Edge.id() => [atom()]}},
          paper: boolean()
        }
  def compare(%__MODULE__{} = old, %__MODULE__{} = new) do
    node_fields = [:type, :data, :locked, :parent]

    edge_fields = [
      :source,
      :source_handle,
      :target,
      :target_handle,
      :label,
      :path,
      :marker,
      :animated,
      :data
    ]

    %{
      added: %{
        nodes: Enum.reject(new.node_order, &Map.has_key?(old.nodes, &1)),
        edges: Enum.reject(new.edge_order, &Map.has_key?(old.edges, &1))
      },
      removed: %{
        nodes: Enum.reject(old.node_order, &Map.has_key?(new.nodes, &1)),
        edges: Enum.reject(old.edge_order, &Map.has_key?(new.edges, &1))
      },
      moved: moved_nodes(old, new),
      changed: %{
        nodes: changed_fields(old.nodes, new.nodes, new.node_order, node_fields),
        edges: changed_fields(old.edges, new.edges, new.edge_order, edge_fields)
      },
      paper: old.paper != new.paper
    }
  end

  defp moved_nodes(old, new) do
    box = [:x, :y, :width, :height]

    for id <- new.node_order,
        before = old.nodes[id],
        before != nil,
        Map.take(before, box) != Map.take(new.nodes[id], box),
        do: id
  end

  defp changed_fields(old, new, order, fields) do
    for id <- order,
        before = old[id],
        before != nil,
        now = new[id],
        changed = Enum.filter(fields, &(Map.fetch!(before, &1) != Map.fetch!(now, &1))),
        changed != [],
        into: %{},
        do: {id, changed}
  end

  @doc """
  The graph as JSON-able maps, with string keys: for a column of the
  app's database (see `Hakushi.Graph.Type`) or a file. `data` goes as it
  is, so it must be JSON-able itself.
  """
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = graph) do
    %{
      "nodes" =>
        Enum.map(nodes(graph), fn node ->
          node
          |> Map.from_struct()
          |> Map.reject(fn {k, v} -> k in [:width, :height, :parent] and is_nil(v) end)
          |> stringify()
        end),
      "edges" =>
        Enum.map(edges(graph), fn edge ->
          edge |> Map.from_struct() |> Map.reject(fn {_k, v} -> is_nil(v) end) |> stringify()
        end)
    }
    |> dump_paper(graph.paper)
  end

  defp dump_paper(map, nil), do: map

  defp dump_paper(map, paper),
    do: Map.put(map, "paper", paper |> Map.reject(fn {_k, v} -> is_nil(v) end) |> stringify())

  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)

  @doc "The graph of `dump/1`'s maps."
  @spec load(map()) :: t()
  def load(%{} = map) do
    new(
      nodes: Map.get(map, "nodes", []),
      edges: Map.get(map, "edges", []),
      paper: Map.get(map, "paper")
    )
  end
end
