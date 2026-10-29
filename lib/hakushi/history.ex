defmodule Hakushi.History do
  @moduledoc """
  The versions of a canvas: its graph as it was, and each change since,
  with who made it and when. To show a past version, what changed since
  (a canvas's `compare`), and to keep them with the graph.

      history = Hakushi.History.new(graph)

      def change(change, %{by: by}, flow) do
        {:ok, history} = Hakushi.History.record(flow.history, change, by: by && by.id)
        Flows.save(flow, history)
      end

      Hakushi.History.versions(history)
      #=> [%{version: 1, op: :add, by: "ada", at: ~U[...]}, ...]

      Hakushi.History.at(history, 3)
      #=> the graph after the third change

  A version is a number: 0 is the graph the history started from, and
  each change recorded is the next. With `limit`, a history keeps that
  many changes, and the graph before them (`first/1` is the oldest
  version it can give back); the numbers of the versions stay theirs.

  `dump/1` and `load/1` keep a history in a column of JSON (as
  `Hakushi.Graph.dump/1` does a graph): the `data` of the nodes and
  edges, and `by`, must be JSON-able.
  """

  alias Hakushi.{Change, Graph}

  defstruct base: %Graph{}, first: 0, entries: [], graph: %Graph{}, limit: nil

  @typedoc "A change recorded: its version, the change as it applied, who made it and when."
  @type entry :: %{version: pos_integer(), change: Change.t(), by: term(), at: DateTime.t() | nil}

  @type t :: %__MODULE__{
          base: Graph.t(),
          first: non_neg_integer(),
          entries: [entry()],
          graph: Graph.t(),
          limit: pos_integer() | nil
        }

  @doc """
  A history that starts from `graph` (version 0). `limit: n` keeps the
  last `n` changes, and no more.
  """
  @spec new(Graph.t(), keyword()) :: t()
  def new(%Graph{} = graph, opts \\ []) do
    limit =
      case Keyword.get(opts, :limit) do
        nil ->
          nil

        n when is_integer(n) and n > 0 ->
          n

        other ->
          raise ArgumentError, "a history's limit is a positive integer, got: #{inspect(other)}"
      end

    %__MODULE__{base: graph, graph: graph, limit: limit}
  end

  @doc """
  Records a change, applied to the graph as it is now: the next version.
  `by` (who made it: an id, a name, a map) and `at` (a `DateTime`, now
  unless given) go with it. Gives `{:error, reason, id}` for a change that
  does not apply to this graph (see `Hakushi.Graph.apply/2`).
  """
  @spec record(t(), Change.t(), keyword()) :: {:ok, t()} | {:error, Graph.reason(), String.t()}
  def record(%__MODULE__{} = history, %Change{} = change, opts \\ []) do
    with {:ok, graph, applied, _inverse} <- Graph.apply(history.graph, change) do
      entry = %{
        version: version(history) + 1,
        change: applied,
        by: Keyword.get(opts, :by),
        at: Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
      }

      {:ok, trim(%{history | graph: graph, entries: history.entries ++ [entry]})}
    end
  end

  # The changes past the limit, into the graph they start from.
  defp trim(%{limit: limit, entries: entries} = history)
       when is_integer(limit) and length(entries) > limit do
    {old, kept} = Enum.split(entries, length(entries) - limit)
    base = Enum.reduce(old, history.base, &apply!(&2, &1.change))
    %{history | base: base, first: history.first + length(old), entries: kept}
  end

  defp trim(history), do: history

  @doc "The graph as it is now: after the last change."
  @spec graph(t()) :: Graph.t()
  def graph(%__MODULE__{graph: graph}), do: graph

  @doc "The number of the last version (0 before any change)."
  @spec version(t()) :: non_neg_integer()
  def version(%__MODULE__{first: first, entries: entries}), do: first + length(entries)

  @doc "The oldest version the history can give back: 0, unless a `limit` let older ones go."
  @spec first(t()) :: non_neg_integer()
  def first(%__MODULE__{first: first}), do: first

  @doc """
  The versions after the first, oldest first: maps of the `version`, the
  change's `op`, the ids of the `nodes` and `edges` it touched, `by` and
  `at`.
  """
  @spec versions(t()) :: [map()]
  def versions(%__MODULE__{entries: entries}) do
    for %{change: change} = entry <- entries do
      {nodes, edges} = Change.ids(change)

      %{
        version: entry.version,
        op: change.op,
        nodes: nodes,
        edges: edges,
        by: entry.by,
        at: entry.at
      }
    end
  end

  @doc "The change of a version, as it applied (with `by` and `at`), or `nil`."
  @spec entry(t(), pos_integer()) :: entry() | nil
  def entry(%__MODULE__{entries: entries}, version),
    do: Enum.find(entries, &(&1.version == version))

  @doc """
  The graph at a version: after its change, as it was then. Raises for a
  version the history does not have (older than `first/1`, or newer than
  `version/1`).
  """
  @spec at(t(), non_neg_integer()) :: Graph.t()
  def at(%__MODULE__{} = history, version) when is_integer(version) do
    last = version(history)

    cond do
      version == last ->
        history.graph

      version < history.first or version > last ->
        raise ArgumentError,
              "the history has the versions #{history.first} to #{last}, not #{version}"

      true ->
        history.entries
        |> Enum.take_while(&(&1.version <= version))
        |> Enum.reduce(history.base, &apply!(&2, &1.change))
    end
  end

  @doc """
  What changed from one version to another (`Hakushi.Graph.compare/2`):
  from `from` to the last unless `to` is given.
  """
  @spec compare(t(), non_neg_integer(), non_neg_integer() | nil) :: map()
  def compare(%__MODULE__{} = history, from, to \\ nil),
    do: Graph.compare(at(history, from), at(history, to || version(history)))

  defp apply!(graph, change) do
    case Graph.apply(graph, change) do
      {:ok, graph, _change, _inverse} ->
        graph

      {:error, reason, id} ->
        raise ArgumentError,
              "a change of the history no longer applies (#{reason}: #{inspect(id)})"
    end
  end

  @doc "The history as JSON-able maps, with string keys."
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = history) do
    %{
      "base" => Graph.dump(history.base),
      "first" => history.first,
      "limit" => history.limit,
      "entries" =>
        Enum.map(history.entries, fn entry ->
          %{
            "version" => entry.version,
            "change" => Change.dump(entry.change),
            "by" => entry.by,
            "at" => entry.at && DateTime.to_iso8601(entry.at)
          }
        end)
    }
  end

  @doc "The history of `dump/1`'s maps."
  @spec load(map()) :: t()
  def load(%{"base" => base} = map) do
    entries =
      for entry <- Map.get(map, "entries", []) do
        %{
          version: entry["version"],
          change: Change.load(entry["change"]),
          by: entry["by"],
          at: entry["at"] && entry["at"] |> DateTime.from_iso8601() |> elem(1)
        }
      end

    base = Graph.load(base)
    graph = Enum.reduce(entries, base, &apply!(&2, &1.change))

    %__MODULE__{
      base: base,
      first: Map.get(map, "first", 0),
      entries: entries,
      graph: graph,
      limit: map["limit"]
    }
  end
end
