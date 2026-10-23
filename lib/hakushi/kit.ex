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
  one app or many. Hakushi has six: `Hakushi.Kits.Schema` (tables,
  their columns and foreign keys), `Hakushi.Kits.Flow` (triggers, steps
  and conditions), `Hakushi.Kits.Notes` (sticky notes),
  `Hakushi.Kits.Ink` (drawing with a pen), `Hakushi.Kits.Shapes`
  (rectangles, ellipses, text, lines) and `Hakushi.Kits.Images` (image
  files); an app makes
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

  @doc """
  The tools of the kit, for a bar on the canvas: a way to make its nodes
  by drawing them, as a pen draws ink (`Hakushi.Kits.Ink`). Defaults to
  none.

  A tool is a map with `tool` (its name in the kit), `label`, `icon` (a
  name of `Hakushi.Icons`), `key` (a letter that takes it, or `nil`) and
  `mode`, what the pointer does with it on the canvas:

    * `"draw"`: draws a line, which becomes a node (`c:drawn/3`) when the
      pen lifts. Its options are `colors` (the names of the colours the
      bar has, `--hakushi-ink-<name>` in the CSS), `color`, `sizes`, `size`
      and `flat` (one width, whatever the pressure).
    * `"erase"`: deletes the nodes of the kit's types that it passes over.
    * `"lasso"`: selects what a line drawn around encloses.
    * `"pick"`: opens the browser's picker of files, for a kit that takes
      them (`c:upload/0`); the pointer stays as it was.

  The bar has the pointer first, which selects and drags as usual.
  """
  @callback tools(messages :: map()) :: [map()]

  @doc """
  A new node for a line drawn with a tool of the kit (`c:tools/1`), or
  `nil`. `params` are the line's `"points"` on the canvas (`[x, y,
  pressure]`), and the `"color"` and `"size"` chosen in the bar. A node
  with no `id` gets one; drawn over a group, it is in it.
  """
  @callback drawn(tool :: String.t(), params :: map(), messages :: map()) :: map() | nil

  @doc """
  The style of the kit's nodes that people change, in a panel over the
  selection, for one node or many, as one change: a list of groups, each
  with a `key` of the nodes' data, a `label`, a `kind` (`"color"`,
  `"width"` or `"choice"`) and its `options` (maps of `value` and `label`);
  or a field for a text (`"text"`, with a `placeholder`), which sends its
  value as a choice does; or a button of the canvas's own for one node
  (`"action"`, by its `key`: `"crop"` crops an image in place).
  A node shows its style in its element's `data-hakushi-style` (JSON of
  those keys it has); a choice sends `"hakushi:edit"` with the nodes, the
  action `"style"` and `%{"style" => %{key => value}}`, which `c:edit/3`
  gets for each node. Defaults to none. See `Hakushi.Kits.Shapes`.
  """
  @callback styles(messages :: map()) :: [map()]

  @doc """
  A node's name for screen readers, where the canvas's `node_label` is
  its default: `"Drawing"`. Defaults to the default's.
  """
  @callback label(node :: Hakushi.Node.t(), messages :: map()) :: String.t()

  @doc """
  The files people drop, paste or pick on the canvas, for a kit whose
  nodes are made of them (`Hakushi.Kits.Images`): the options of a
  LiveView upload (`Phoenix.LiveView.allow_upload/3`'s `accept`,
  `max_file_size` and `max_entries`), which the canvas allows for the
  first such kit of its kits. Defaults to none.
  """
  @callback upload() :: keyword()

  @doc """
  A node of an uploaded file, which the canvas adds where the person put
  it: `{:ok, node}`, or `{:error, reason}` for a file the kit refuses.
  `path` is the uploaded file, a temporary file; `meta` has the client's
  `:name` and `:content_type` (a claim); `box` is the place the person
  put it, `[x, y, width, height]`, or `nil`.
  """
  @callback uploaded(path :: Path.t(), meta :: map(), box :: [number()] | nil, messages :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  A node of an address (a URL) pasted on the canvas, as `c:uploaded/4`.
  It runs away from the LiveView (it may download), and the canvas adds
  its node when it is done.
  """
  @callback pasted(url :: String.t(), box :: [number()] | nil, messages :: map()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks resizable?: 1,
                      upload: 0,
                      uploaded: 4,
                      pasted: 3,
                      canvas: 0,
                      to_markdown: 1,
                      from_markdown: 1,
                      tools: 1,
                      styles: 1,
                      drawn: 3,
                      label: 2

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
    |> Enum.filter(&exports?(&1, :to_markdown, 1))
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
    readers = Enum.filter(kits, &exports?(&1, :from_markdown, 1))

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
    do: exports?(kit, :resizable?, 1) and kit.resizable?(type)

  @doc false
  # The tools of a canvas's kits, for its bar: each with its kit's name.
  def tools(kits, messages) do
    for kit <- kits, exports?(kit, :tools, 1), tool <- kit.tools(messages) do
      Map.put(tool, :kit, kit.name())
    end
  end

  @doc false
  # The style panels of a canvas's kits: each kit's, with its node types.
  def styles(kits, messages) do
    for kit <- kits, exports?(kit, :styles, 1) do
      %{kit: kit.name(), types: kit.types(), groups: kit.styles(messages)}
    end
  end

  @doc false
  # The kit that takes files, among a canvas's kits: the first.
  def uploader(kits), do: Enum.find(kits, &exports?(&1, :upload, 0))

  @doc false
  def drawn(kit, tool, params, messages),
    do: if(exports?(kit, :drawn, 3), do: kit.drawn(tool, params, messages))

  @doc false
  # A kit's name for a node, or nil for none of its own.
  def label(kits, node, messages) do
    case for_type(kits, node.type) do
      nil -> nil
      kit -> if exports?(kit, :label, 2), do: kit.label(node, messages)
    end
  end

  @doc false
  # The canvas the kits like: the first kit's paper and layout, every
  # kit's rules (the first kit's, for a rule two kits set).
  def canvas_prefs(kits) do
    prefs = for kit <- kits, exports?(kit, :canvas, 0), do: kit.canvas()

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
  # An optional callback of a kit: the module is loaded first, as
  # function_exported?/3 is false for a module not loaded yet.
  def exports?(kit, function, arity),
    do: Code.ensure_loaded?(kit) and function_exported?(kit, function, arity)

  @doc false
  # String keys, as the kits keep them.
  def stringify(data) when is_map(data), do: Map.new(data, fn {k, v} -> {to_string(k), v} end)
end
