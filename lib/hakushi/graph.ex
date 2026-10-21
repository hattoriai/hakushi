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
  """

  alias Hakushi.{Change, Edge, Node}

  defstruct nodes: %{}, edges: %{}, node_order: [], edge_order: []

  @type t :: %__MODULE__{
          nodes: %{Node.id() => Node.t()},
          edges: %{Edge.id() => Edge.t()},
          node_order: [Node.id()],
          edge_order: [Edge.id()]
        }

  @typedoc "Why a change does not apply."
  @type reason :: :missing | :exists | :locked | :dangling

  @doc """
  Makes a graph of `nodes` and `edges`: `Hakushi.Node`s and
  `Hakushi.Edge`s, or maps and keyword lists for `Hakushi.Node.new/1` and
  `Hakushi.Edge.new/1`. Raises on two nodes or two edges with one id, and
  on an edge to a node the graph does not have.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    nodes = opts |> Keyword.get(:nodes, []) |> Enum.map(&Node.new/1)
    edges = opts |> Keyword.get(:edges, []) |> Enum.map(&Edge.new/1)

    case put_all(%__MODULE__{}, nodes, edges) do
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

    * a delete lists the edges of its nodes too, which go with them;
    * the change that undoes a delete adds the nodes back, with their
      edges (over the other nodes, as new nodes are).

  A change does not apply, and nothing changes, when it names a node or an
  edge that the graph does not have (`:missing`), adds one it has
  (`:exists`), moves, resizes or deletes a locked node (`:locked`), or
  adds an edge to a node it does not have (`:dangling`). The error has the
  id.
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
    Enum.reduce_while(places, {:ok, graph, []}, fn place, {:ok, graph, undo} ->
      id = place.id

      case Map.fetch(graph.nodes, id) do
        :error ->
          {:halt, {:error, :missing, id}}

        {:ok, %Node{locked: true}} ->
          {:halt, {:error, :locked, id}}

        {:ok, node} ->
          {moved, old} = place(node, place)
          {:cont, {:ok, %{graph | nodes: Map.put(graph.nodes, id, moved)}, [old | undo]}}
      end
    end)
    |> case do
      {:ok, graph, undo} ->
        {:ok, graph, change, %Change{op: :move, nodes: Enum.reverse(undo), by: change.by}}

      error ->
        error
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :update} = change) do
    with {:ok, graph, node_undo} <-
           update_all(graph, :nodes, change.nodes, [:data, :type, :locked]),
         {:ok, graph, edge_undo} <-
           update_all(graph, :edges, change.edges, [:label, :path, :marker, :animated, :data]) do
      {:ok, graph, change,
       %Change{op: :update, nodes: node_undo, edges: edge_undo, by: change.by}}
    end
  end

  def apply(%__MODULE__{} = graph, %Change{op: :delete} = change) do
    node_ids = change.nodes
    edge_ids = change.edges

    with :ok <- all_present(graph.nodes, node_ids),
         :ok <- all_present(graph.edges, edge_ids),
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

      applied = %__MODULE__{
        nodes: Map.drop(graph.nodes, node_ids),
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

      {:ok, applied, %{change | edges: edge_ids}, inverse}
    end
  end

  # A node at its new place (and size), and its old place for the undo.
  defp place(node, %{width: width, height: height} = place) do
    {%{node | x: place.x, y: place.y, width: width, height: height},
     %{id: node.id, x: node.x, y: node.y, width: node.width, height: node.height}}
  end

  defp place(node, place) do
    {%{node | x: place.x, y: place.y}, %{id: node.id, x: node.x, y: node.y}}
  end

  # Nodes, then edges, each checked against the graph as it grows.
  defp put_all(graph, nodes, edges) do
    with {:ok, graph} <- reduce_ok(nodes, graph, &put_node/2) do
      reduce_ok(edges, graph, &put_edge/2)
    end
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

  @doc """
  What changed from one graph to another: the nodes and edges that are
  new or not the same, and the ids of those that went away.
  """
  @spec diff(t(), t()) :: %{
          nodes: [Node.t()],
          edges: [Edge.t()],
          deleted_nodes: [Node.id()],
          deleted_edges: [Edge.id()]
        }
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    %{
      nodes: for(node <- nodes(new), Map.get(old.nodes, node.id) != node, do: node),
      edges: for(edge <- edges(new), Map.get(old.edges, edge.id) != edge, do: edge),
      deleted_nodes: for(id <- old.node_order, not Map.has_key?(new.nodes, id), do: id),
      deleted_edges: for(id <- old.edge_order, not Map.has_key?(new.edges, id), do: id)
    }
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
          |> Map.reject(fn {k, v} -> k in [:width, :height] and is_nil(v) end)
          |> stringify()
        end),
      "edges" =>
        Enum.map(edges(graph), fn edge ->
          edge |> Map.from_struct() |> Map.reject(fn {_k, v} -> is_nil(v) end) |> stringify()
        end)
    }
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)

  @doc "The graph of `dump/1`'s maps."
  @spec load(map()) :: t()
  def load(%{} = map) do
    new(nodes: Map.get(map, "nodes", []), edges: Map.get(map, "edges", []))
  end
end
