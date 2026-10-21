defmodule Hakushi.Rules do
  @moduledoc """
  The rules of the edges of a canvas, the same in the browser and on the
  server.

      <.canvas id="flow" graph={@graph} rules={[cycles: false]}>

  While a person draws an edge, the browser shows the handles it may end
  on, and no others; when the edge comes to the server, the canvas checks
  the same rules again, so that a browser that does not follow them still
  makes no edge they forbid.

    * `loops` - an edge from a node to itself (`false` unless set).
    * `duplicates` - a second edge between the same two handles, in the
      same direction (`false` unless set).
    * `cycles` - an edge that closes a cycle, as a workflow must not have
      (`true` unless set).

  A handle of one `type` connects to a handle that `accepts` it (see
  `Hakushi.Components.handle/1`). That rule is the browser's: the server
  does not know the handles, which are in the HEEx of each node. Check
  what an edge means for your app in `on_change` (see `Hakushi.Change`).
  """

  alias Hakushi.{Edge, Graph}

  defstruct loops: false, duplicates: false, cycles: true

  @type t :: %__MODULE__{loops: boolean(), duplicates: boolean(), cycles: boolean()}

  @typedoc "Why the rules refuse an edge."
  @type reason :: :loop | :duplicate | :cycle

  @doc "Makes rules of a keyword list, or gives rules back."
  @spec new(t() | keyword() | nil) :: t()
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = rules), do: rules

  def new(opts) when is_list(opts) do
    Enum.reduce(opts, %__MODULE__{}, fn
      {key, value}, rules when key in [:loops, :duplicates, :cycles] and is_boolean(value) ->
        Map.put(rules, key, value)

      other, _rules ->
        raise ArgumentError,
              "unknown rule #{inspect(other)}, the rules are loops, duplicates and cycles"
    end)
  end

  @doc """
  Checks an edge against the rules, in a graph that does not have it yet.
  """
  @spec check(t(), Graph.t(), Edge.t()) :: :ok | {:error, reason()}
  def check(%__MODULE__{} = rules, %Graph{} = graph, %Edge{} = edge) do
    cond do
      not rules.loops and edge.source == edge.target -> {:error, :loop}
      not rules.duplicates and duplicate?(graph, edge) -> {:error, :duplicate}
      not rules.cycles and path?(graph, edge.target, edge.source) -> {:error, :cycle}
      true -> :ok
    end
  end

  defp duplicate?(graph, edge) do
    Enum.any?(graph.edges, fn {_id, other} ->
      other.source == edge.source and other.target == edge.target and
        other.source_handle == edge.source_handle and other.target_handle == edge.target_handle
    end)
  end

  # Whether the edges lead from `from` to `to`.
  defp path?(_graph, same, same), do: true

  defp path?(graph, from, to) do
    out =
      Enum.reduce(graph.edges, %{}, fn {_id, edge}, out ->
        Map.update(out, edge.source, [edge.target], &[edge.target | &1])
      end)

    walk([from], out, to, MapSet.new([from]))
  end

  defp walk([], _out, _to, _seen), do: false

  defp walk([node | rest], out, to, seen) do
    next = out |> Map.get(node, []) |> Enum.reject(&MapSet.member?(seen, &1))

    if to in next,
      do: true,
      else: walk(next ++ rest, out, to, Enum.into(next, seen))
  end

  @doc false
  def to_client(%__MODULE__{} = rules),
    do: %{"loops" => rules.loops, "duplicates" => rules.duplicates, "cycles" => rules.cycles}
end
