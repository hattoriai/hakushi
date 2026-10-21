if Code.ensure_loaded?(Issho.Engine) do
  defmodule Hakushi.Issho do
    @moduledoc """
    A shared canvas on [Issho](https://hex.pm/packages/issho): the canvas's
    graph is a document of an Issho room, the canvas's LiveView is one of
    the room's sessions, and Issho is the room's people and their cursors.

        <.canvas id="schema" graph={@graph} live={{MyApp.Issho, "schema:42"}} user={@current_user} />

    The first canvas to open the room's document gives it its graph, its
    rules and its `on_change`; the others get the document as it is. Each
    change goes to the document's authority, which checks the rules,
    applies it, asks `on_change` (once, whoever made it), and only then
    sends it to every canvas of the room. The document lasts as long as a
    canvas has it open: your app's tables, which `on_change` writes, are
    the truth, and the next canvas starts from the graph you give it.

    `change/3` makes your app's own change, from anywhere (a job, another
    LiveView), on a canvas someone has open.
    """

    alias Hakushi.{Change, Commit, Graph, Rules}

    defmodule Engine do
      @moduledoc false
      # The graph as an Issho engine: each transaction is a list of
      # Hakushi.Change structs, checked by the rules and applied in order.
      # Pure, so the authority can replay it.
      @behaviour Issho.Engine

      @impl true
      def name, do: "hakushi"

      @impl true
      def version, do: 1

      @impl true
      def init(%Graph{} = graph, _opts), do: {:ok, graph}
      def init(_other, _opts), do: {:error, :invalid_graph}

      @impl true
      def apply(%Graph{} = graph, changes, opts) do
        rules = Keyword.get(opts, :rules, Rules.new(nil))

        Enum.reduce_while(changes, {:ok, graph}, fn
          %Change{} = change, {:ok, graph} ->
            case Commit.check_and_apply(graph, change, rules) do
              {:ok, graph, _change, _inverse} -> {:cont, {:ok, graph}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          _other, _acc ->
            {:halt, {:error, :invalid_change}}
        end)
      end
    end

    @doc ~S"""
    A shared canvas's document, for your policy's `document/2`
    (`Issho.Policy`): what the room's canvas is when an agent opens it
    before anyone has it open in a browser. Give it the graph your app
    keeps, and the canvas's `rules` and `on_change` (as `canvas/1` takes
    them), so that the agent's changes go the way of everyone's; a canvas
    that opens the room later gets the document as it is.

        def document(_identity, "board:" <> id = room) do
          board = MyApp.Boards.get!(id)
          Hakushi.Issho.document(board.graph, on_change: &MyApp.Boards.on_change(room, &1, &2))
        end

    Options: `:rules` (a list, as the canvas's), `:on_change` and `:canvas`
    (the id `on_change` gets as `:canvas`, `"agent"` unless given).
    """
    @spec document(Graph.t(), keyword()) :: {:ok, map()}
    def document(%Graph{} = graph, opts \\ []) do
      rules = opts |> Keyword.get(:rules, []) |> Rules.new()
      {:ok, spec(graph, rules, opts[:on_change], Keyword.get(opts, :canvas, "agent"))}
    end

    @doc false
    # What the canvas's document is, if this canvas opens it first.
    @spec spec(Graph.t(), Rules.t(), function() | nil, String.t()) :: map()
    def spec(%Graph{} = graph, %Rules{} = rules, on_change, canvas) do
      %{
        engine: Engine,
        initial: graph,
        opts: [rules: rules],
        store: :none,
        on_transaction: hook(rules, on_change, canvas)
      }
    end

    # on_change, once for each change, with the change as it applied (a
    # delete lists its edges) and the graph before and after it.
    defp hook(_rules, nil, _canvas), do: nil

    defp hook(rules, on_change, canvas) do
      fn changes, %{before: before} -> ask_each(changes, before, rules, on_change, canvas) end
    end

    # Each change is asked about with the graph the ones before it made.
    defp ask_each([], _graph, _rules, _on_change, _canvas), do: :ok

    defp ask_each([change | rest], graph, rules, on_change, canvas) do
      with {:ok, result} <- ask(graph, change, rules, on_change, canvas),
           do: ask_each(rest, result, rules, on_change, canvas)
    end

    defp ask(graph, change, rules, on_change, canvas) do
      with {:ok, result, applied, _inverse} <- Commit.check_and_apply(graph, change, rules),
           :ok <-
             Commit.ask(on_change, applied, %{
               graph: graph,
               result: result,
               user: change.by,
               canvas: canvas
             }) do
        {:ok, result}
      end
    end

    @doc """
    Makes your app's own change on a shared canvas: the way of a person's
    (the rules, `on_change`), to everyone in the room, and not a person's to
    undo (`by` is `nil`). Gives `:ok`, `{:error, reason}`, or
    `{:error, :not_running}` when no canvas has the room open (then change
    your own copy, in your database).
    """
    @spec change(atom(), String.t(), Change.t()) :: :ok | {:error, term()}
    def change(instance, topic, %Change{} = change) do
      case Issho.Documents.whereis(instance, topic) do
        nil ->
          {:error, :not_running}

        _pid ->
          case Issho.transact(instance, topic, [%{change | by: nil}], author: "app") do
            {:ok, _receipt} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end

    @doc ~S"""
    Hakushi's tools for agents (`Issho.Tool`): an agent reads a shared
    canvas, points (the people see its pointer, with its name), selects,
    adds nodes, drags them (they see the node go), connects them, changes
    and deletes them, as a person does, through the canvas's rules and its
    `on_change`. Give them to your app's model (`Issho.Tools`), or serve
    them to MCP clients (`Issho.MCP`), with Issho's room tools:

        tools = Issho.Tools.room() ++ Hakushi.Issho.tools()

    A tool names its canvas by its room (`live={{MyApp.Issho, "schema:42"}}`);
    an agent works on a canvas someone has open, or on one your policy's
    `document/2` describes with `document/2`.

    Its pointer travels to where it works, and drags, as a hand does: only
    where it goes is sent, and each browser draws the way. For changes that
    land at once: `config :hakushi, Hakushi.Issho, travel: false`.
    """
    @spec tools() :: [module()]
    def tools,
      do: [
        Hakushi.Issho.Tools.Read,
        Hakushi.Issho.Tools.Point,
        Hakushi.Issho.Tools.Add,
        Hakushi.Issho.Tools.Move,
        Hakushi.Issho.Tools.Connect,
        Hakushi.Issho.Tools.Update,
        Hakushi.Issho.Tools.Delete
      ]

    @doc "The graph of a shared canvas as its room has it, or `nil` when no canvas has it open."
    @spec graph(atom(), String.t()) :: Graph.t() | nil
    def graph(instance, topic) do
      with pid when is_pid(pid) <- Issho.Documents.whereis(instance, topic),
           {:ok, %{"state" => graph}} <- Issho.Authority.snapshot(pid) do
        graph
      else
        _ -> nil
      end
    end
  end
end
