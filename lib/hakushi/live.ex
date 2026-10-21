defmodule Hakushi.Live do
  @moduledoc ~S"""
  The `on_mount` hook of a LiveView with a shared canvas (`live`), and the
  app's own changes to a canvas.

      live_session :default, on_mount: [Hakushi.Live] do

  or, in one LiveView:

      on_mount Hakushi.Live

  A canvas with `live` gets the changes of the others, and their cursors,
  in its LiveView's process, as messages of its topic: this hook takes
  them, so the LiveView needs no `handle_info` of its own for them. A
  canvas with `live` in a LiveView without the hook raises, saying so.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, send_update: 2]

  alias Hakushi.Change
  alias Phoenix.LiveView.Socket

  @doc false
  def on_mount(_arg, _params, _session, %Socket{} = socket) do
    Process.put(__MODULE__, true)
    {:cont, attach_hook(socket, :hakushi_live, :handle_info, &__MODULE__.__handle_info__/2)}
  end

  @doc false
  def __handle_info__({:hakushi, topic, message}, socket) do
    for canvas <- canvases(topic), do: send_update(Hakushi.Canvas, id: canvas, hakushi: message)
    {:halt, socket}
  end

  def __handle_info__(_message, socket), do: {:cont, socket}

  @doc """
  Makes the app's own change on the canvas `canvas` of this LiveView: a
  node of a form, a label set from a menu, a step a job finished. The
  change goes the way of a person's (the graph, the rules, `on_change`),
  to everyone on a shared canvas, and cannot be undone by the people
  (`by` is `nil`).

      def handle_event("add_table", %{"name" => name}, socket) do
        node = %Hakushi.Node{id: name, type: "table", x: 0, y: 0, data: %{name: name, columns: []}}
        Hakushi.Live.change("schema", Hakushi.Change.add([node]))
        {:noreply, socket}
      end

  A change the canvas refuses shows its reason on the canvas.
  """
  @spec change(String.t(), Change.t()) :: :ok
  def change(canvas, %Change{} = change) when is_binary(canvas) do
    send_update(Hakushi.Canvas, id: canvas, hakushi_change: change)
    :ok
  end

  @doc """
  Tidies up the canvas `canvas` of this LiveView, as its tidy up button
  does: its nodes in layers along their edges (`direction: :right` or
  `:down`, the canvas's `layout` unless given). The person's browser lays
  them out, and the new places are a change as any: checked, shared, and
  undone with ⌘Z.
  """
  @spec layout(String.t(), keyword()) :: :ok
  def layout(canvas, opts \\ []) when is_binary(canvas) do
    payload = if dir = opts[:direction], do: %{"direction" => Atom.to_string(dir)}, else: %{}
    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:layout", payload})
    :ok
  end

  @doc """
  Downloads the canvas `canvas` of this LiveView as an image, in the
  person's browser: `format: :png` (the default) or `:svg`, and
  `filename` (the canvas's id unless given), without its extension.
  """
  @spec export(String.t(), keyword()) :: :ok
  def export(canvas, opts \\ []) when is_binary(canvas) do
    payload = %{
      "format" => Atom.to_string(opts[:format] || :png),
      "filename" => opts[:filename] || canvas
    }

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:export", payload})
    :ok
  end

  @doc false
  @spec ensure_mounted!(String.t()) :: :ok
  def ensure_mounted!(canvas) do
    if Process.get(__MODULE__),
      do: :ok,
      else:
        raise(ArgumentError, """
        the canvas #{inspect(canvas)} has `live`, which needs the Hakushi.Live hook in its \
        LiveView: `on_mount Hakushi.Live`, or `live_session :default, on_mount: [Hakushi.Live]`\
        """)
  end

  @doc false
  # The canvases of this LiveView on a topic.
  @spec register(String.t(), String.t()) :: :new | :known
  def register(topic, canvas) do
    known = canvases(topic)
    Process.put({__MODULE__, topic}, Enum.uniq([canvas | known]))
    if known == [], do: :new, else: :known
  end

  defp canvases(topic), do: Process.get({__MODULE__, topic}, [])
end
