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
    * `:move` - `nodes` is a list of maps with `:id`, `:x` and `:y`, and
      `:width` and `:height` for a node that was resized.
    * `:update` - `nodes` is a list of maps with `:id` and the keys that
      change (`:data`, `:type`, `:locked`), `edges` a list of maps with
      `:id` and the keys that change (`:label`, `:path`, `:marker`,
      `:animated`, `:data`).
    * `:delete` - `nodes` and `edges` are lists of ids. Deleting a node
      deletes its edges: the change that `Hakushi.Graph.apply/2` gives back
      lists them.

  `by` is the `user` of the canvas that made it (a map with an `:id`), or
  `nil` for the app's own.
  """

  alias Hakushi.{Edge, Node}

  @ops [:add, :connect, :move, :update, :delete]

  @enforce_keys [:op]
  defstruct op: nil, nodes: [], edges: [], by: nil

  @type op :: :add | :connect | :move | :update | :delete

  @type t :: %__MODULE__{
          op: op(),
          nodes: [Node.t() | map() | Node.id()],
          edges: [Edge.t() | map() | Edge.id()],
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

  defp ids?(list), do: is_list(list) and Enum.all?(list, &(is_binary(&1) and &1 != ""))

  defp client_place(%{"id" => id, "x" => x, "y" => y} = place)
       when is_binary(id) and is_number(x) and is_number(y) do
    case {place["width"], place["height"]} do
      {nil, nil} ->
        %{id: id, x: x, y: y}

      {w, h} when is_number(w) and is_number(h) and w > 0 and h > 0 ->
        %{id: id, x: x, y: y, width: w, height: h}

      _other ->
        nil
    end
  end

  defp client_place(_place), do: nil

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

  @doc false
  def ops, do: @ops
end
