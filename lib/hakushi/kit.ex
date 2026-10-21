defmodule Hakushi.Kit do
  @moduledoc """
  A kit: the things of one kind of canvas, which the canvas draws, makes
  and edits by itself. A canvas with `kits` needs no `:node` slots and no
  `new_node` for them:

      <.canvas id="model" graph={@graph} kits={[Hakushi.Kits.Schema]} on_change={&save/2} />
      <.kit_items for="model" kits={[Hakushi.Kits.Schema]} />

  Kits are optional: a canvas draws anything with `:node` slots, and a
  kit is a way to package a kind of canvas (its nodes, how people make and
  edit them, its paper and its rules) so that it is used in one line, by
  one app or many. Hakushi has three: `Hakushi.Kits.Schema` (tables,
  their columns and foreign keys), `Hakushi.Kits.Flow` (triggers, steps
  and conditions) and `Hakushi.Kits.Notes` (sticky notes); an app makes
  its own with the same callbacks. See the [Kits](kits.md) guide.

  ## A kit of the app's own

  A kit is a module that `use`s `Hakushi.Kit` and implements its
  callbacks:

      defmodule MyAppWeb.Kits.Roadmap do
        use Hakushi.Kit

        @impl true
        def name, do: "roadmap"
        @impl true
        def title(_messages), do: "Roadmap"
        @impl true
        def icon, do: "workflow"
        @impl true
        def types, do: ["roadmap-milestone"]
        @impl true
        def elements(_messages), do: [%{item: "milestone", label: "Milestone", icon: "zap"}]

        @impl true
        def new_node(_item, {x, y}, _messages),
          do: %{type: "roadmap-milestone", x: x, y: y, data: %{"title" => "Milestone"}}

        @impl true
        def node(assigns) do
          ~H\"""
          <div class="milestone">
            <.handle kind={:target} side={:left} />
            <input
              :if={!@readonly}
              value={get(@node.data, "title")}
              phx-blur="hakushi:edit"
              phx-target={@target}
              phx-value-node={@node.id}
              phx-value-action="title"
            />
            <span :if={@readonly}>{get(@node.data, "title")}</span>
            <.handle kind={:source} side={:right} />
          </div>
          \"""
        end

        @impl true
        def edit("title", %{"value" => title}, data), do: {:ok, Map.put(data, "title", title)}
        def edit(_action, _params, _data), do: :error
      end

  The node's controls send `"hakushi:edit"` to the canvas (`@target`)
  with the node's id and an `action`; the canvas calls `edit/3` with the
  node's data and puts the data it returns in the node, as a change of the
  person's own: checked by the rules and `on_change`, undone with ⌘Z, and
  shared with everyone on a shared canvas.

  A kit's data has string keys, as a graph loaded from JSON has; `get/2`
  reads a key of either kind.
  """

  @typedoc "An element of a kit: an item of its bar (`Hakushi.Components.kit_items/1`)."
  @type element :: %{item: String.t(), label: String.t(), icon: String.t()}

  @doc "The kit's name, unique among a canvas's kits."
  @callback name() :: String.t()

  @doc "The kit's title, in the canvas's words (`Hakushi.Messages`)."
  @callback title(messages :: map()) :: String.t()

  @doc "The kit's icon, a name of `Hakushi.Icons`."
  @callback icon() :: String.t()

  @doc "The node types the kit draws."
  @callback types() :: [String.t()]

  @doc "The things people add, in the canvas's words."
  @callback elements(messages :: map()) :: [element()]

  @doc """
  A new node for an element's `item` dropped at `{x, y}`, or for a double
  click on the paper (`item` is `nil`). A node with no `id` gets one.
  """
  @callback new_node(item :: String.t() | nil, at :: {number(), number()}, messages :: map()) ::
              map() | nil

  @doc """
  Draws a node of the kit's types. The assigns are `node` (the
  `Hakushi.Node`), `canvas` (the canvas's id, for the ids of forms),
  `readonly`, `target` (the canvas, for `phx-target`) and `messages`
  (the canvas's words).
  """
  @callback node(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  The node's data after an `action` of its controls (`params` are the
  event's), or `:error` for an action the kit refuses.
  """
  @callback edit(action :: String.t(), params :: map(), data :: map()) :: {:ok, map()} | :error

  @doc "Whether people resize the nodes of a type by their corners. Defaults to `false`."
  @callback resizable?(type :: String.t()) :: boolean()

  @doc """
  The canvas the kit likes: its paper (`background`, `grid`, `snap`), the
  way the tidy up goes (`layout`) and the rules of its edges (`rules`, a
  keyword list of `Hakushi.Rules`). Defaults to `[]`.

  The canvas's own attributes win; among kits, the first kit's paper and
  layout, and the rules of all of them (the first kit's, for a rule two
  kits set).

      def canvas, do: [background: :lines, grid: 24, rules: [loops: false]]
  """
  @callback canvas() :: keyword()

  @doc """
  The kit's nodes of `graph` as Markdown: a fenced diagram (Mermaid), so
  that a document with the canvas in it (a Kotoba embed) exports as text
  people read and Markdown viewers draw, and that `from_markdown/1` reads
  back. `nil` when the graph has none of the kit's nodes.

  Write the places of the nodes in it (`Hakushi.Mermaid.places/3`), so
  that the canvas comes back as it was. See the [Kits](kits.md) guide.
  """
  @callback to_markdown(graph :: Hakushi.Graph.t()) :: String.t() | nil

  @doc """
  The canvas of a diagram that `to_markdown/1` wrote, or that a person
  wrote in the kit's kind of diagram: `{:ok, graph}`, or `:error` for a
  text the kit does not read.
  """
  @callback from_markdown(text :: String.t()) :: {:ok, Hakushi.Graph.t()} | :error

  @optional_callbacks resizable?: 1, canvas: 0, to_markdown: 1, from_markdown: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour Hakushi.Kit
      use Phoenix.Component
      import Hakushi.Components, only: [handle: 1]
      import Hakushi.Icons, only: [icon: 1]
      import Hakushi.Kit, only: [get: 2, word: 3]
    end
  end

  @doc """
  The value of `key` in a node's data, whose keys are strings (a graph
  loaded from JSON) or atoms (a graph made in Elixir).
  """
  @spec get(map(), String.t()) :: term()
  def get(data, key) when is_map(data) and is_binary(key) do
    case Map.fetch(data, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(data, &atom_value(&1, key))
    end
  end

  defp atom_value({k, v}, key) when is_atom(k), do: if(Atom.to_string(k) == key, do: v)
  defp atom_value(_entry, _key), do: nil

  @doc "A word of `messages`, with its `{name}` filled."
  @spec word(map(), String.t(), String.t()) :: String.t()
  def word(messages, key, name), do: String.replace(messages[key] || key, "{name}", name)

  @doc """
  A canvas as Markdown: the diagram of each of `kits` that has nodes in
  `graph` (`c:to_markdown/1`), one after the other. `nil` when none has.

      Hakushi.Kit.to_markdown([Hakushi.Kits.Schema], graph)
      #=> "```mermaid\n%% hakushi kit=schema\nerDiagram\n  ..."
  """
  @spec to_markdown([module()], Hakushi.Graph.t()) :: String.t() | nil
  def to_markdown(kits, graph) do
    kits
    |> Enum.filter(&function_exported?(&1, :to_markdown, 1))
    |> Enum.map(& &1.to_markdown(graph))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  @doc """
  A canvas from Markdown (a diagram of `to_markdown/2`): read by the kit it
  names (`%% hakushi kit=...`), or else by the first of `kits` that reads
  it. Gives `{:ok, graph, kit}` or `:error`.
  """
  @spec from_markdown([module()], String.t()) :: {:ok, Hakushi.Graph.t(), module()} | :error
  def from_markdown(kits, text) do
    readers = Enum.filter(kits, &function_exported?(&1, :from_markdown, 1))

    readers =
      case Hakushi.Mermaid.kit(text) && by_name(readers, Hakushi.Mermaid.kit(text)) do
        nil -> readers
        kit -> [kit]
      end

    Enum.find_value(readers, :error, fn kit ->
      case kit.from_markdown(text) do
        {:ok, graph} -> {:ok, graph, kit}
        :error -> nil
      end
    end)
  end

  @doc false
  # The kit that draws a node type, among a canvas's kits.
  def for_type(kits, type), do: Enum.find(kits, &(type in &1.types()))

  @doc false
  def by_name(kits, name), do: Enum.find(kits, &(&1.name() == name))

  @doc false
  def resizable?(kit, type),
    do: function_exported?(kit, :resizable?, 1) and kit.resizable?(type)

  @doc false
  # The canvas the kits like: the first kit's paper and layout, every
  # kit's rules (the first kit's, for a rule two kits set).
  def canvas_prefs(kits) do
    prefs = for kit <- kits, function_exported?(kit, :canvas, 0), do: kit.canvas()

    paper =
      Enum.reduce(Enum.reverse(prefs), [], fn pref, acc ->
        Keyword.merge(acc, Keyword.take(pref, [:background, :grid, :snap, :layout]))
      end)

    rules =
      prefs
      |> Enum.reverse()
      |> Enum.reduce([], fn pref, acc -> Keyword.merge(acc, Keyword.get(pref, :rules, [])) end)

    Keyword.put(paper, :rules, rules)
  end

  @doc false
  # String keys, as the kits keep them.
  def stringify(data) when is_map(data), do: Map.new(data, fn {k, v} -> {to_string(k), v} end)
end
