defmodule Hakushi.Change do
  @moduledoc """
  A change to a canvas: what a person did, or what the app does.

  Every change goes the same way, whoever makes it: the canvas applies it
  to its graph (`Hakushi.Graph.apply/2`), checks its rules
  (`Hakushi.Rules`), asks the app (`on_change`), and only then shows it,
  to the person and to everyone else on the canvas. A change the server
  refuses goes back in the browser, with the reason.

  `op` is one of:

    * `:add` - `nodes` is a list of `Hakushi.Node`s, `edges` a list of
      `Hakushi.Edge`s between them or others: a node dropped on the canvas,
      a paste, a duplicate, an undone delete.
    * `:connect` - `edges` is a list of `Hakushi.Edge`s, drawn by a person
      from a handle to a handle.
    * `:move` - `nodes` is a list of maps with `:id`, `:x` and `:y`,
      `:width` and `:height` for a node that was resized, and `:parent`
      for a node dropped into a group (an id) or out of one (`nil`). The
      nodes in a moved node move with it: `Hakushi.Graph.apply/2` lists
      them.
    * `:reconnect` - `edges` is a list of maps with `:id` and the new
      ends (`:source`, `:source_handle`, `:target`, `:target_handle`): an
      edge's end dragged to another handle.
    * `:update` - `nodes` is a list of maps with `:id` and the keys that
      change (`:data`, `:type`, `:locked`, and `:x`, `:y`, `:width` and
      `:height` for an edit that moves its node too), `edges` a list of maps with
      `:id` and the keys that change (`:label`, `:path`, `:marker`,
      `:animated`, `:data`).
    * `:delete` - `nodes` and `edges` are lists of ids. Deleting a node
      deletes the nodes in it and the edges of all of them: the change
      that `Hakushi.Graph.apply/2` gives back lists them.
    * `:paper` - `paper` is the canvas's paper (`Hakushi.Paper`), chosen
      with the canvas's picker, or `nil` for the canvas's own
      `background` and `grid`.

  `by` is the `user` of the canvas that made it (a map with an `:id`), or
  `nil` for the app's own.
  """

  alias Hakushi.{Edge, Node, Paper}

  @ops [:add, :connect, :move, :reconnect, :update, :delete, :paper]

  @enforce_keys [:op]
  defstruct op: nil, nodes: [], edges: [], paper: nil, by: nil

  @type op :: :add | :connect | :move | :reconnect | :update | :delete | :paper

  @type t :: %__MODULE__{
          op: op(),
          nodes: [Node.t() | map() | Node.id()],
          edges: [Edge.t() | map() | Edge.id()],
          paper: Paper.t() | nil,
          by: map() | nil
        }

  @doc "Adds nodes, and edges."
  @spec add([Node.t() | map()], [Edge.t() | map()]) :: t()
  def add(nodes, edges \\ []),
    do: %__MODULE__{
      op: :add,
      nodes: Enum.map(nodes, &Node.new/1),
      edges: Enum.map(edges, &Edge.new/1)
    }

  @doc "Connects two nodes: an edge, or a list of them."
  @spec connect(Edge.t() | map() | [Edge.t() | map()]) :: t()
  def connect(edges) when is_list(edges),
    do: %__MODULE__{op: :connect, edges: Enum.map(edges, &Edge.new/1)}

  def connect(edge), do: connect([edge])

  @doc "Moves nodes: `[{id, x, y}]` or maps with `:id`, `:x` and `:y`."
  @spec move([{Node.id(), number(), number()} | map()]) :: t()
  def move(places), do: %__MODULE__{op: :move, nodes: Enum.map(places, &place/1)}

  @doc """
  Moves the ends of edges: maps with the edge's `:id` and its new
  `:source`, `:source_handle`, `:target` or `:target_handle`.
  """
  @spec reconnect([map()]) :: t()
  def reconnect(ends), do: %__MODULE__{op: :reconnect, edges: ends}

  @doc """
  Changes nodes and edges: maps with an `:id` and the keys that change.

      Hakushi.Change.update(nodes: [%{id: "users", data: %{name: "people"}}])
  """
  @spec update(keyword()) :: t()
  def update(opts),
    do: %__MODULE__{
      op: :update,
      nodes: Keyword.get(opts, :nodes, []),
      edges: Keyword.get(opts, :edges, [])
    }

  @doc "Deletes nodes (with their edges) and edges, by id."
  @spec delete(keyword()) :: t()
  def delete(opts),
    do: %__MODULE__{
      op: :delete,
      nodes: Keyword.get(opts, :nodes, []),
      edges: Keyword.get(opts, :edges, [])
    }

  @doc """
  Changes the canvas's paper: its pattern and the size of its squares
  (`Hakushi.Paper.new/1`), or `nil` for the canvas's own.

      Hakushi.Change.paper(background: :lines, grid: 24)
  """
  @spec paper(map() | keyword() | nil) :: t()
  def paper(paper), do: %__MODULE__{op: :paper, paper: Paper.new(paper)}

  defp place({id, x, y}), do: %{id: id, x: x, y: y}
  defp place(%{} = place), do: place

  @doc """
  The ids of the nodes a change touches, and of its edges, as two lists.
  """
  @spec ids(t()) :: {[Node.id()], [Edge.id()]}
  def ids(%__MODULE__{nodes: nodes, edges: edges}),
    do: {Enum.map(nodes, &id/1), Enum.map(edges, &id/1)}

  defp id(id) when is_binary(id), do: id
  defp id(%{id: id}), do: id

  # The most nodes or edges of one change from a browser.
  @max_items 5_000

  @doc false
  # A change the browser sends: a move (a drag, a resize, the arrow keys),
  # a connection, a delete, or a new label of an edge. Everything else the
  # browser asks for (a paste, a drop, an undo) the canvas makes itself,
  # from what the server has.
  @spec from_client(map()) :: {:ok, t()} | :error
  def from_client(%{"op" => "move", "nodes" => [_ | _] = nodes})
      when length(nodes) <= @max_items do
    places = Enum.map(nodes, &client_place/1)
    if Enum.all?(places), do: {:ok, %__MODULE__{op: :move, nodes: places}}, else: :error
  end

  def from_client(%{"op" => "connect", "edges" => [_ | _] = edges})
      when length(edges) <= @max_items do
    edges = Enum.map(edges, &client_edge/1)
    if Enum.all?(edges), do: {:ok, %__MODULE__{op: :connect, edges: edges}}, else: :error
  end

  def from_client(%{"op" => "reconnect", "edges" => [%{"id" => id} = ends]}) when is_binary(id) do
    with {:ok, source} <- node_id(ends["source"]),
         {:ok, target} <- node_id(ends["target"]) do
      {:ok,
       %__MODULE__{
         op: :reconnect,
         edges: [
           %{
             id: id,
             source: source,
             source_handle: string_or_nil(ends["sourceHandle"]),
             target: target,
             target_handle: string_or_nil(ends["targetHandle"])
           }
         ]
       }}
    end
  end

  def from_client(%{"op" => "delete"} = params) do
    nodes = Map.get(params, "nodes", [])
    edges = Map.get(params, "edges", [])

    if ids?(nodes) and ids?(edges) and nodes ++ edges != [] and
         length(nodes) + length(edges) <= @max_items,
       do: {:ok, %__MODULE__{op: :delete, nodes: Enum.uniq(nodes), edges: Enum.uniq(edges)}},
       else: :error
  end

  def from_client(%{"op" => "update", "edges" => [%{"id" => id, "label" => label}]})
      when is_binary(id) and (is_binary(label) or is_nil(label)) do
    label = if label, do: label |> String.trim() |> String.slice(0, 500)
    {:ok, %__MODULE__{op: :update, edges: [%{id: id, label: if(label != "", do: label)}]}}
  end

  def from_client(_params), do: :error

  defp node_id(id) when is_binary(id) and id != "", do: {:ok, id}
  defp node_id(_id), do: :error

  defp ids?(list), do: is_list(list) and Enum.all?(list, &(is_binary(&1) and &1 != ""))

  defp client_place(%{"id" => id, "x" => x, "y" => y} = place)
       when is_binary(id) and is_number(x) and is_number(y) do
    %{id: id, x: x, y: y}
    |> client_size(place["width"], place["height"])
    |> client_parent(Map.fetch(place, "parent"))
  end

  defp client_place(_place), do: nil

  defp client_size(place, nil, nil), do: place

  defp client_size(place, w, h) when is_number(w) and is_number(h) and w > 0 and h > 0,
    do: Map.merge(place, %{width: w, height: h})

  defp client_size(_place, _w, _h), do: nil

  # A drop into a group (its id) or out of one (nil); no key, no change.
  defp client_parent(nil, _parent), do: nil
  defp client_parent(place, :error), do: place
  defp client_parent(place, {:ok, nil}), do: Map.put(place, :parent, nil)

  defp client_parent(place, {:ok, parent}) when is_binary(parent) and parent != "",
    do: Map.put(place, :parent, parent)

  defp client_parent(_place, _parent), do: nil

  defp client_edge(%{"source" => source, "target" => target} = edge)
       when is_binary(source) and is_binary(target) do
    Edge.new(%{
      source: source,
      target: target,
      source_handle: string_or_nil(edge["sourceHandle"]),
      target_handle: string_or_nil(edge["targetHandle"])
    })
  rescue
    ArgumentError -> nil
  end

  defp client_edge(_edge), do: nil

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_value), do: nil

  @doc """
  The change as JSON-able maps, with string keys, to keep it (a version
  of `Hakushi.History`, a log of the app's own). The `data` of its nodes
  and edges goes as it is, so it must be JSON-able itself; `by` keeps its
  `id` and `name`.
  """
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = change) do
    %{
      "op" => Atom.to_string(change.op),
      "nodes" => Enum.map(change.nodes, &dump_item/1),
      "edges" => Enum.map(change.edges, &dump_item/1)
    }
    |> put_dumped("paper", change.paper && dump_item(change.paper))
    |> put_dumped("by", change.by && dump_item(Map.take(change.by, [:id, :name])))
  end

  defp put_dumped(map, _key, nil), do: map
  defp put_dumped(map, key, value), do: Map.put(map, key, value)

  defp dump_item(id) when is_binary(id), do: id
  defp dump_item(%_{} = struct), do: struct |> Map.from_struct() |> dump_item()

  defp dump_item(%{} = map) do
    for {key, value} <- map, not is_nil(value) or key in [:parent, :label], into: %{} do
      {to_string(key), value}
    end
  end

  # The keys of the maps of a move, a reconnect and an update, and of `by`.
  @item_keys ~w(id x y width height parent data type locked label path marker animated source source_handle target target_handle name)a

  @doc "The change of `dump/1`'s maps."
  @spec load(map()) :: t()
  def load(%{"op" => op} = map) do
    op =
      Enum.find(@ops, &(Atom.to_string(&1) == op)) || raise ArgumentError, "no op #{inspect(op)}"

    nodes = Map.get(map, "nodes", [])
    edges = Map.get(map, "edges", [])

    %__MODULE__{
      op: op,
      nodes: load_items(op, nodes, &Node.new/1),
      edges: load_items(op, edges, &Edge.new/1),
      paper: map["paper"] && Paper.new(map["paper"]),
      by: map["by"] && load_map(map["by"])
    }
  end

  # An add's and a connect's nodes and edges are whole; a delete's are ids;
  # the others' are maps of the keys that change.
  defp load_items(op, items, whole) when op in [:add, :connect], do: Enum.map(items, whole)
  defp load_items(:delete, ids, _whole), do: ids
  defp load_items(_op, items, _whole), do: Enum.map(items, &load_map/1)

  defp load_map(map) do
    for {key, value} <- map,
        atom = Enum.find(@item_keys, &(Atom.to_string(&1) == key)),
        into: %{} do
      {atom, value}
    end
  end

  @doc false
  def ops, do: @ops
end
