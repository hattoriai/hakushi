defmodule Hakushi.Kits.Notes do
  @moduledoc """
  The kit of sticky notes: notes of a few colours, which people write in
  place, resize by their corners and join with arrows.

  A note is a node of type `"note"` whose data is:

      %{"text" => "Ask finance about refunds", "color" => "yellow"}

  The colours are `colors/0`; the button in a note's corner takes the
  next one.

  In Markdown, notes are a Mermaid flowchart of boxes in their colours
  (`:::yellow`), with their arrows; `from_markdown/1` reads it back.
  """

  use Hakushi.Kit

  alias Hakushi.{Graph, Mermaid}

  @colors ~w(yellow rose sky mint lilac)

  @doc "The colours of the notes, in the order the colour button takes them."
  @spec colors() :: [String.t()]
  def colors, do: @colors

  @impl true
  def name, do: "notes"

  @impl true
  def title(messages), do: messages["kitNotes"]

  @impl true
  def icon, do: "sticky-note"

  @impl true
  def canvas, do: [background: :cross, grid: 20, snap: true]

  @impl true
  def types, do: ["note"]

  @impl true
  def elements(messages), do: [%{item: "note", label: messages["note"], icon: "sticky-note"}]

  @impl true
  def resizable?(_type), do: true

  @impl true
  def new_node(_item, {x, y}, _messages),
    do: %{
      type: "note",
      x: x,
      y: y,
      width: 200,
      height: 150,
      data: %{"text" => "", "color" => "yellow"}
    }

  @impl true
  def node(assigns) do
    assigns =
      assign(assigns,
        text: get(assigns.node.data, "text"),
        color: get(assigns.node.data, "color") || "yellow"
      )

    ~H"""
    <div class="hakushi-kit-note" data-color={@color}>
      <.handle side={:left} />
      <.handle side={:top} />
      <textarea
        :if={!@readonly}
        class="hakushi-kit-field hakushi-kit-note-text"
        aria-label={@messages["noteText"]}
        placeholder={@messages["noteText"]}
        phx-blur="hakushi:edit"
        phx-target={@target}
        phx-value-node={@node.id}
        phx-value-action="text"
      >{@text}</textarea>
      <p :if={@readonly} class="hakushi-kit-note-text">{@text}</p>
      <button
        :if={!@readonly}
        type="button"
        class="hakushi-kit-note-color"
        aria-label={@messages["noteColor"]}
        title={@messages["noteColor"]}
        phx-click="hakushi:edit"
        phx-target={@target}
        phx-value-node={@node.id}
        phx-value-action="color"
      >
      </button>
      <.handle side={:right} />
      <.handle side={:bottom} />
    </div>
    """
  end

  @impl true
  def edit("text", %{"value" => text}, data),
    do: {:ok, Map.put(data, "text", String.slice(to_string(text), 0, 4_000))}

  def edit("color", _params, data) do
    color = get(data, "color")
    i = Enum.find_index(@colors, &(&1 == color)) || -1
    {:ok, Map.put(data, "color", Enum.at(@colors, rem(i + 1, length(@colors))))}
  end

  def edit(_action, _params, _data), do: :error

  @fills %{
    "yellow" => "#fde68a",
    "rose" => "#fecdd3",
    "sky" => "#bae6fd",
    "mint" => "#a7f3d0",
    "lilac" => "#ddd6fe"
  }

  @impl true
  def to_markdown(graph) do
    case Enum.filter(Graph.nodes(graph), &(&1.type == "note")) do
      [] ->
        nil

      notes ->
        ids = Mermaid.ids(notes)

        edges =
          Enum.filter(
            Graph.edges(graph),
            &(Map.has_key?(ids, &1.source) and Map.has_key?(ids, &1.target))
          )

        body =
          ["flowchart LR"] ++
            Enum.map(notes, fn note ->
              color = get(note.data, "color") || "yellow"

              "  " <>
                ids[note.id] <> "[" <> Mermaid.label(get(note.data, "text")) <> "]:::" <> color
            end) ++
            Enum.map(edges, &"  #{ids[&1.source]} --> #{ids[&1.target]}") ++
            Enum.map(@colors, &"  classDef #{&1} fill:#{@fills[&1]},stroke:none") ++
            [Mermaid.places(notes, ids), Mermaid.edge_places(edges, ids)]

        Mermaid.fence(name(), Enum.join(body, "\n"))
    end
  end

  @impl true
  def from_markdown(text) do
    with {:ok, nodes, edges} <- Mermaid.flowchart(text),
         true <- Mermaid.kit(text) == name() or Enum.all?(nodes, &(&1.class in @colors)) do
      notes = Enum.map(nodes, &note/1)
      edges = Mermaid.read_edges(text) || Enum.map(edges, &Map.take(&1, [:from, :to]))
      graph = Mermaid.graph(notes, edges, Mermaid.read_places(text))

      # A note a person wrote has the size of a new note.
      {:ok, sized(graph)}
    else
      _other -> :error
    end
  end

  defp note(node) do
    color = if node.class in @colors, do: node.class, else: "yellow"
    %{m: node.m, type: "note", data: %{"text" => node.text || "", "color" => color}}
  end

  defp sized(graph) do
    Enum.reduce(Graph.nodes(graph), graph, fn
      %{width: nil} = note, graph ->
        %{graph | nodes: Map.put(graph.nodes, note.id, %{note | width: 200, height: 150})}

      _note, graph ->
        graph
    end)
  end
end
