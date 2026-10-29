defmodule Hakushi.Commit do
  @moduledoc false

  # The way of every change: the rules of the edges and the graph
  # (check_and_apply/3,
  # pure: on a shared canvas, the engine of its Issho document), then the
  # app's on_change (ask/3: on a shared canvas, the document's transaction
  # hook, once for each change, whoever made it).
  #
  # on_change may give back another change in its place (a move snapped to
  # the app's grid, a delete that takes more with it): that one goes the
  # same way, the rules and on_change again, until on_change takes a change
  # as it is, at most @rounds times.

  require Logger

  alias Hakushi.{Change, Graph, Rules}

  # The most changes on_change may give back in place of one.
  @rounds 5

  @type opts :: %{
          required(:rules) => Rules.t(),
          required(:on_change) => (Change.t(), map() -> term()) | nil,
          required(:canvas) => String.t() | nil,
          optional(:by) => term()
        }

  @doc false
  # The graph after the change, the change as it applied (on_change's, when
  # it gave back another), its inverse, and whether on_change gave back
  # another.
  @spec run(Graph.t(), Change.t(), opts()) ::
          {:ok, Graph.t(), Change.t(), Change.t(), boolean()} | {:error, atom() | String.t()}
  def run(%Graph{} = graph, %Change{} = change, opts), do: run(graph, change, opts, 0)

  defp run(graph, change, opts, round) do
    with {:ok, result, applied, inverse} <- check_and_apply(graph, change, opts.rules) do
      context = %{
        graph: graph,
        result: result,
        by: Map.get(opts, :by),
        user: applied.by,
        canvas: opts.canvas
      }

      case ask(opts.on_change, applied, context) do
        :ok -> {:ok, result, applied, inverse, round > 0}
        {:rewrite, other} -> rewrite(round, other, &run(graph, &1, opts, round + 1))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc false
  # Another change of on_change's, the way of the first: or no change at
  # all, after too many.
  @spec rewrite(non_neg_integer(), change, (change -> result)) :: result | {:error, :failed}
        when change: Change.t() | [Change.t()], result: term()
  def rewrite(round, change, again) when round < @rounds, do: again.(change)

  def rewrite(_round, change, _again) do
    Logger.warning(
      "Hakushi: on_change gave back another change #{@rounds} times; the last: #{inspect(change)}"
    )

    {:error, :failed}
  end

  @doc false
  # The rules of the edges, then the graph: the change as it applied and
  # its inverse, or why it does not apply.
  @spec check_and_apply(Graph.t(), Change.t(), Rules.t()) ::
          {:ok, Graph.t(), Change.t(), Change.t()} | {:error, atom() | String.t()}
  def check_and_apply(%Graph{} = graph, %Change{} = change, rules) do
    with :ok <- check_edges(rules, graph, change) do
      graph |> Graph.apply(change) |> drop_id()
    end
  end

  defp drop_id({:error, reason, _id}), do: {:error, reason}
  defp drop_id(ok), do: ok

  # The rules are for the edges people draw; the edges of an add (a paste,
  # an undone delete) were drawn before.
  defp check_edges(rules, graph, %Change{op: :connect, edges: edges}) do
    Enum.reduce_while(edges, {:ok, graph}, fn edge, {:ok, graph} ->
      with :ok <- Rules.check(rules, graph, edge),
           {:ok, graph, _change, _inverse} <-
             Graph.apply(graph, %Change{op: :connect, edges: [edge]}) do
        {:cont, {:ok, graph}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        {:error, reason, _id} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _graph} -> :ok
      error -> error
    end
  end

  # A moved end: the rules of the edge with its new ends, in the graph
  # without it.
  defp check_edges(rules, graph, %Change{op: :reconnect, edges: ends}) do
    Enum.reduce_while(ends, :ok, fn ends, :ok ->
      case check_ends(rules, graph, ends) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_edges(_rules, _graph, _change), do: :ok

  defp check_ends(rules, graph, %{id: id} = ends) do
    case Graph.edge(graph, id) do
      nil ->
        {:error, :missing}

      edge ->
        others = %{
          graph
          | edges: Map.delete(graph.edges, id),
            edge_order: List.delete(graph.edge_order, id)
        }

        moved = struct!(edge, Map.take(ends, [:source, :source_handle, :target, :target_handle]))
        Rules.check(rules, others, moved)
    end
  end

  @doc false
  # The app's on_change: :ok, another change in its place (with the same
  # `by`), or why it refuses the change. The change given back as it was
  # given is the change taken.
  @spec ask((Change.t(), map() -> term()) | nil, Change.t(), map()) ::
          :ok | {:rewrite, Change.t()} | {:error, term()}
  def ask(nil, _change, _context), do: :ok

  def ask(on_change, change, context) do
    case on_change.(change, context) do
      :ok ->
        :ok

      {:ok, %Change{} = other} ->
        other = %{other | by: change.by}
        if other == change, do: :ok, else: {:rewrite, other}

      {:ok, _anything} ->
        :ok

      {:error, reason} when is_binary(reason) or is_atom(reason) ->
        {:error, reason}

      {:error, %{errors: [_ | _]} = changeset} ->
        {:error, changeset_message(changeset)}

      other ->
        raise ArgumentError,
              "on_change must return :ok, {:ok, term}, {:ok, %Hakushi.Change{}} or {:error, reason} (a string), got: #{inspect(other)}"
    end
  end

  # The first error of a changeset, as a sentence.
  defp changeset_message(%{errors: [{field, {message, values}} | _]}) do
    message =
      Enum.reduce(values, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
      end)

    "#{Phoenix.Naming.humanize(field)} #{message}."
  end
end
