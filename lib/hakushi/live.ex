defmodule Hakushi.Live do
  @moduledoc ~S"""
  The `on_mount` hook of a LiveView with a shared canvas (`live`), and the
  app's own changes to a canvas.

      live_session :default, on_mount: [Hakushi.Live] do

  or, in one LiveView:

      on_mount Hakushi.Live

  A shared canvas is a session of an Issho room (see `Hakushi.Issho`): this
  hook is Issho's (`Issho.Live`), which takes the room's events in the
  LiveView's process and gives them to its canvases, so the LiveView needs
  no `handle_info` of its own for them. A LiveView that has `on_mount
  Issho.Live` already needs no other. A canvas with `live` in a LiveView
  without the hook raises, saying so.
  """

  import Phoenix.LiveView, only: [send_update: 2]

  alias Hakushi.Change

  @compile {:no_warn_undefined, Issho.Live}

  @doc false
  def on_mount(arg, params, session, socket) do
    if Code.ensure_loaded?(Issho.Live),
      do: Issho.Live.on_mount(arg, params, session, socket),
      else: {:cont, socket}
  end

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

  A change the canvas refuses shows its reason on the canvas. From outside
  the LiveView (a job), change a shared canvas with
  `Hakushi.Issho.change/3`.
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
    cond do
      not Code.ensure_loaded?(Issho.Live) ->
        raise ArgumentError, """
        the canvas #{inspect(canvas)} has `live`, which needs Issho: add {:issho, "~> 0.1"} \
        to your dependencies\
        """

      Process.get({Issho.Live, :mounted}) ->
        :ok

      true ->
        raise ArgumentError, """
        the canvas #{inspect(canvas)} has `live`, which needs the Hakushi.Live hook in its \
        LiveView: `on_mount Hakushi.Live`, or `live_session :default, on_mount: [Hakushi.Live]`\
        """
    end
  end
end
