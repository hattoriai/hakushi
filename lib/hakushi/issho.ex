if Code.ensure_loaded?(Issho.Engine) do
  defmodule Hakushi.Issho.Place do
    @moduledoc """
    A place on a Hakushi canvas, in the canvas's own terms (never screen
    pixels, as each person has their own pan and zoom): where a person's
    pointer is, where an agent goes (`Issho.Motion`), what an app keeps of
    them. Its format is part of Hakushi's public API, and only grows.

        %{"point" => [x, y]}          # a point, in the canvas's coordinates
        %{"node" => node_id}          # a node
        %{"nodes" => [node_id, ...]}  # nodes (the first is where it is drawn)

    In the room, it is the `"at"` of a place of the canvas's document:
    `%{"doc" => "board:42", "at" => %{"point" => [120, 80]}}`.

    A canvas's place of what a person selects also has a `"label"`, a
    few words for those who only read it (an agent, Issho's comments):
    the node's name as the app says it (`node_label`), else its title,
    its text or an image's alt, else its kind (`"Drawing"`); for several
    nodes, how many (`"3 nodes"`). It is only words: `"at"` says where.

    `label/3` says a place in words, for a thread of comments on it.
    """
    @behaviour Issho.Place

    alias Hakushi.{Canvas, Graph, Kit, Messages}

    @max_ids 5_000

    @impl true
    def validate(nil), do: :ok

    def validate(%{"point" => [x, y]}) when is_number(x) and is_number(y), do: :ok
    def validate(%{"node" => id}) when is_binary(id) and byte_size(id) <= 160, do: :ok

    def validate(%{"nodes" => ids}) when is_list(ids) and length(ids) <= @max_ids do
      if Enum.all?(ids, &(is_binary(&1) and byte_size(&1) <= 160)),
        do: :ok,
        else: {:error, :invalid_place}
    end

    def validate(_other), do: {:error, :invalid_place}

    @doc ~S"""
    A place of the canvas in words, from its graph: for a thread of
    comments on the canvas (`Issho.Components.comments/1`'s `:place`
    slot), or wherever your app says where something is.

        <.comments id="comments" room="schema:42">
          <:place :let={%{place: place, default: default}}>
            {Hakushi.Issho.Place.label(place, @graph, document: "schema:42") || default}
          </:place>
        </.comments>

    It gives `The node “customers”` (the node's name, as the canvas says
    it to a screen reader), `The node “customers” and 2 more`, or `A point
    on the canvas`; and `nil` for a place of another document, or of nodes
    that are gone, for your own words.

    `place` is a place of the room (`%{"doc" => doc, "at" => at}`), or
    its `at`. Options: `:document`, the canvas's (a place of another
    document is `nil`); `:locale` and `:messages`, as the canvas's; and
    `:kits` and `:node_label`, as the canvas's, for the names of its nodes.

    `@graph` is the graph as it is now: a LiveView keeps it with the
    canvas's events (see "Events" in `Hakushi.Issho`), or reads it with
    `Hakushi.Issho.graph/2`.
    """
    @spec label(map() | nil, Graph.t() | nil, keyword()) :: String.t() | nil
    def label(place, graph, opts \\ [])

    def label(%{"doc" => doc, "at" => at}, graph, opts) do
      if opts[:document] in [nil, doc], do: label(at, graph, opts)
    end

    def label(%{"point" => [x, y]}, _graph, opts) when is_number(x) and is_number(y),
      do: words(opts)["placePoint"]

    def label(%{"node" => id}, graph, opts), do: label(%{"nodes" => [id]}, graph, opts)

    def label(%{"nodes" => ids}, %Graph{} = graph, opts) when is_list(ids) do
      case Enum.filter(Enum.map(ids, &Graph.node(graph, &1)), & &1) do
        [] ->
          nil

        [node | rest] ->
          words = words(opts)
          key = if rest == [], do: "placeNode", else: "placeNodes"

          words[key]
          |> String.replace("{name}", name(node, words, opts))
          |> String.replace("{n}", Integer.to_string(length(rest)))
      end
    end

    def label(_place, _graph, _opts), do: nil

    defp words(opts),
      do:
        Messages.for_locale(
          opts[:locale] || Application.get_env(:hakushi, :locale, "en"),
          opts[:messages] || %{}
        )

    # The node's name as the canvas says it: the app's node_label, else
    # its kit's, else its data's label or name, else its id.
    defp name(node, words, opts) do
      name =
        case opts[:node_label] do
          nil -> Kit.label(opts[:kits] || [], node, words) || Canvas.label(node)
          fun -> fun.(node)
        end

      to_string(name)
    end
  end

  defmodule Hakushi.Issho do
    @moduledoc """
    A shared canvas on [Issho](https://hex.pm/packages/issho): the canvas's
    graph is a document of an Issho room, the canvas's LiveView is one of
    the room's sessions, and Issho is the room's people and their cursors.

        <.canvas id="schema" graph={@graph} issho={[instance: MyApp.Issho, document: "schema:42"]} user={@current_user} />

    `issho` takes the keys of every component (`Issho.Join`): `:instance`
    and `:document` (required; the room is the part before the first
    `"/"`), `:can` (`:read` for a viewer), `:people` (`false` hides the
    canvas's avatars, on a page that lists the room's people), `:follow`
    (`false` for a canvas that takes no part in following),
    `:on_behalf_of` and `:claims`.

    The first canvas to open the room's document gives it its graph, its
    rules and its `on_change`; the others get the document as it is. Each
    change goes to the document's authority, which checks the rules,
    applies it, asks `on_change` (once, whoever made it), and only then
    sends it to every canvas of the room. The document lasts as long as a
    canvas has it open: your app's tables, which `on_change` writes, are
    the truth, and the next canvas starts from the graph you give it.

    `change/4` makes your app's own change, from anywhere (a job, another
    LiveView), on a canvas someone has open. A place on the canvas is
    `Hakushi.Issho.Place`.

    ## Events

    Each change of a shared canvas is an event of its room (`Issho.Event`),
    once the room has it: an agent waits for what people do on the canvas
    (`wait_for_events` with `"canvas.*"`), a component of the page hears
    it (`Issho.Live.subscribe/3`'s `:events`), and your app acts on it
    (`Issho.Events.subscribe/2`). The event's `document` is the canvas's,
    its `by` who made the change, and its name is the change's op:

      * `"canvas.added"`: nodes added (dropped, pasted, an undone delete),
        `%{nodes: [%{id: id, type: type}], edges: [%{id: id, source: id, target: id}]}`.
      * `"canvas.connected"`: edges drawn, `%{edges: [%{id: id, source: id, target: id}]}`.
      * `"canvas.reconnected"`: an edge's end moved to another node, the
        same, with its new ends.
      * `"canvas.moved"`: nodes moved or resized, `%{nodes: [%{id: id, x: x, y: y}]}`
        (with `width` and `height` for a resize, `parent` for a node put in
        a group or out), the nodes inside a moved node too.
      * `"canvas.updated"`: nodes or edges changed (a node's data, an
        edge's label), `%{nodes: [id], edges: [id]}`.
      * `"canvas.deleted"`: nodes and edges deleted, `%{nodes: [id], edges: [id]}`,
        with the nodes inside the nodes deleted and the edges that went
        with them.

    A change of the paper makes none: Issho's `"document.changed"` says it,
    as it says every change.
    """

    alias Hakushi.{Change, Commit, Graph, Rules}

    defmodule GraphEngine do
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

    use Issho.Binding, engine: Hakushi.Issho.GraphEngine, place: Hakushi.Issho.Place

    @doc ~S"""
    A shared canvas's document, for your policy's `document/2`
    (`Issho.Policy`): what the room's canvas is, whoever opens it first (its
    page, an embed of it in a document, an agent with no browser). Give it
    the graph your app keeps, and the canvas's `rules` and `on_change` (as
    `canvas/1` takes them): a canvas that opens the room gets the document
    as it is, and its own `graph`, `rules` and `on_change` are not used.

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
        engine: __MODULE__,
        initial: graph,
        opts: [rules: rules],
        store: :none,
        on_transaction: hook(rules, on_change, canvas),
        events: &__MODULE__.events/2
      }
    end

    @doc false
    # The events of a transaction, once the room has it (see "Events"):
    # one for each change, as it applied (a delete lists its edges, a move
    # the nodes that went with it).
    @spec events([Change.t()], map()) :: [{String.t(), map()}]
    def events(changes, %{before: %Graph{} = graph}) do
      {events, _graph} =
        Enum.flat_map_reduce(changes, graph, fn change, graph ->
          case Graph.apply(graph, change) do
            {:ok, result, applied, _inverse} -> {event(applied, result), result}
            {:error, _reason, _id} -> {[], graph}
          end
        end)

      events
    end

    defp event(%Change{op: :add, nodes: nodes, edges: edges}, _graph),
      do: [
        {"canvas.added",
         %{nodes: Enum.map(nodes, &%{id: &1.id, type: &1.type}), edges: Enum.map(edges, &ends/1)}}
      ]

    defp event(%Change{op: :connect, edges: edges}, _graph),
      do: [{"canvas.connected", %{edges: Enum.map(edges, &ends/1)}}]

    defp event(%Change{op: :reconnect, edges: edges}, graph),
      do: [
        {"canvas.reconnected", %{edges: Enum.map(edges, &ends(Graph.edge(graph, &1.id)))}}
      ]

    defp event(%Change{op: :move, nodes: places}, _graph),
      do: [
        {"canvas.moved",
         %{nodes: Enum.map(places, &Map.take(&1, [:id, :x, :y, :width, :height, :parent]))}}
      ]

    defp event(%Change{op: :update} = change, _graph), do: [{"canvas.updated", ids(change)}]
    defp event(%Change{op: :delete} = change, _graph), do: [{"canvas.deleted", ids(change)}]

    defp event(%Change{}, _graph), do: []

    defp ids(change) do
      {nodes, edges} = Change.ids(change)
      %{nodes: nodes, edges: edges}
    end

    defp ends(edge), do: %{id: edge.id, source: edge.source, target: edge.target}

    # on_change, once for each change, with the change as it applied (a
    # delete lists its edges) and the graph before and after it.
    defp hook(_rules, nil, _canvas), do: nil

    defp hook(rules, on_change, canvas) do
      fn changes, %{before: before} = context ->
        ask_each(changes, before, rules, on_change, {canvas, context[:by]})
      end
    end

    # Each change is asked about with the graph the ones before it made.
    defp ask_each([], _graph, _rules, _on_change, _who), do: :ok

    defp ask_each([change | rest], graph, rules, on_change, who) do
      with {:ok, result} <- ask(graph, change, rules, on_change, who),
           do: ask_each(rest, result, rules, on_change, who)
    end

    defp ask(graph, change, rules, on_change, {canvas, by}) do
      with {:ok, result, applied, _inverse} <- Commit.check_and_apply(graph, change, rules),
           :ok <-
             Commit.ask(on_change, applied, %{
               graph: graph,
               result: result,
               by: by,
               user: change.by,
               canvas: canvas
             }) do
        {:ok, result}
      end
    end

    @doc """
    Makes your app's own change on a shared canvas: the way of a person's
    (the rules, `on_change`), to everyone in the room, and not a person's to
    undo. `changes` is a `Hakushi.Change` or a list of them, applied
    together. Gives `:ok`, `{:error, reason}`, or `{:error, :not_running}`
    when no canvas has the document open (then change your own copy, in
    your database).

    Options: `:author`, who makes it: a key (`"server"`, the default) or
    your actor (`current_user`); `on_change` gets it as `:by`, an
    `Issho.Identity`, as everyone's.
    """
    @spec change(atom(), String.t(), Change.t() | [Change.t()], keyword()) ::
            :ok | {:error, term()}
    def change(instance, document, changes, opts \\ [])

    def change(instance, document, %Change{} = change, opts),
      do: change(instance, document, [change], opts)

    def change(instance, document, changes, opts) when is_list(changes) do
      case Issho.Documents.whereis(instance, document) do
        nil ->
          {:error, :not_running}

        _pid ->
          changes = Enum.map(changes, fn %Change{} = change -> %{change | by: nil} end)
          author = Keyword.get(opts, :author, "server")

          case Issho.transact(instance, document, changes, author: author) do
            {:ok, _receipt} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end

    @doc false
    # The canvas's issho option, checked (Issho.Join): Hakushi has no keys
    # of its own.
    @spec join!(keyword() | map()) :: Issho.Join.t()
    def join!(issho), do: Issho.Join.new!(issho)

    @doc ~S"""
    Hakushi's tools for agents (`Issho.Tool`): an agent reads a shared
    canvas, points (the people see its pointer, with its name), selects,
    adds nodes, drags them (they see the node go), connects them, changes
    and deletes them, as a person does, through the canvas's rules and its
    `on_change`. Give them to your app's model (`Issho.Tools`), or serve
    them to MCP clients (`Issho.MCP`), with Issho's room tools:

        tools = Issho.Tools.room() ++ Hakushi.Issho.tools()

    A tool names its canvas by its document (`"schema:42"`, the canvas's
    `issho` `:document`);
    an agent works on a canvas someone has open, or on one your policy's
    `document/2` describes with `document/2`.

    A person may pause or stop an agent at work (`Issho.Work`): then its
    tools read the canvas and change nothing on it, not even where its
    pointer is, and say why, as Issho's room tools do.

    Its pointer travels to where it works, and drags, as a hand does: only
    where it goes is sent, and each browser draws the way. For changes that
    land at once: `config :hakushi, Hakushi.Issho, travel: false`.

    On a canvas with ink (`Hakushi.Kits.Ink`), `draw_on_canvas` draws
    strokes, or a ring around a node: the people see its pen draw each
    stroke as they see a person's, and each stroke lands as a node when
    the pen lifts. How it draws is the app's to set, and the agent's for
    a drawing (its `live` argument):

        config :hakushi, Hakushi.Issho,
          ink: [
            live: true,    # false: the strokes land at once, unseen as drawn
            speed: 900,    # how fast the pen goes, in pixels of the canvas a second
            max: 8_000     # the most a drawing takes, in milliseconds
          ]

    It draws only for someone who sees it: when no one in the room shows
    the canvas, or each of them prefers reduced motion, or with `travel:
    false` (Hakushi's or Issho's), the strokes land at once.
    """
    @spec tools() :: [module()]
    def tools,
      do:
        [
          Hakushi.Issho.Tools.Read,
          Hakushi.Issho.Tools.Point,
          Hakushi.Issho.Actions.AddNode,
          Hakushi.Issho.Tools.Move,
          Hakushi.Issho.Actions.Connect,
          Hakushi.Issho.Actions.Update,
          Hakushi.Issho.Actions.Delete,
          Hakushi.Issho.Tools.Draw,
          Hakushi.Issho.Tools.Shape
        ] ++ image_tools()

    # add_image, when the app has Storehouse for the images' files.
    if Code.ensure_loaded?(Storehouse) do
      defp image_tools, do: [Hakushi.Issho.Tools.Image]
    else
      defp image_tools, do: []
    end

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
