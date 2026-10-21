defmodule Hakushi.Kits.Notes do
  @moduledoc """
  The kit of sticky notes: notes of a few colours, which people write in
  place, resize by their corners and join with arrows.

  A note is a node of type `"note"` whose data is:

      %{"text" => "Ask finance about refunds", "color" => "yellow"}

  The colours are `colors/0`; the button in a note's corner takes the
  next one.
  """

  use Hakushi.Kit

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
    do: %{type: "note", x: x, y: y, width: 200, height: 150, data: %{"text" => "", "color" => "yellow"}}

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
end
