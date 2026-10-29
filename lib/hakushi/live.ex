defmodule Hakushi.Live do
  @moduledoc ~S"""
  The `on_mount` hook of a LiveView with a shared canvas (`issho`), the
  app's own changes to a canvas, and the person's view of it: what it
  shows (`fit/2`, `focus/3`) and what is selected (`select/3`).

      live_session :default, on_mount: [Hakushi.Live] do

  or, in one LiveView:

      on_mount Hakushi.Live

  A shared canvas is a session of an Issho room (see `Hakushi.Issho`): this
  hook is Issho's (`Issho.Live`), which takes the room's events in the
  LiveView's process and gives them to its canvases, so the LiveView needs
  no `handle_info` of its own for them. A LiveView that has `on_mount
  Issho.Live` already needs no other. A canvas with `issho` in a LiveView
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
  `Hakushi.Issho.change/4`.
  """
  @spec change(String.t(), Change.t()) :: :ok
  def change(canvas, %Change{} = change) when is_binary(canvas) do
    send_update(Hakushi.Canvas, id: canvas, hakushi_change: change)
    :ok
  end

  @doc """
  Tidies up the canvas `canvas` of this LiveView, as its tidy up button
  does: `algorithm: :layered` (in layers along the edges, `direction:
  :right` or `:down`), `:force` (by forces) or `:grid`; the canvas's
  `layout` (or the way the person chose in its menu) unless given. The
  person's browser lays the nodes out, and the new places are a change as
  any: checked, shared, and undone with ⌘Z.

      Hakushi.Live.layout("schema", algorithm: :force)
  """
  @spec layout(String.t(), keyword()) :: :ok
  def layout(canvas, opts \\ []) when is_binary(canvas) do
    payload =
      for {key, values} <- [direction: [:right, :down], algorithm: [:layered, :force, :grid]],
          value = opts[key],
          value != nil,
          into: %{} do
        unless value in values,
          do:
            raise(
              ArgumentError,
              "a layout's #{key} is one of #{inspect(values)}, got: #{inspect(value)}"
            )

        {Atom.to_string(key), Atom.to_string(value)}
      end

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:layout", payload})
    :ok
  end

  @doc """
  Downloads the canvas `canvas` of this LiveView as an image, in the
  person's browser: `format: :png` (the default) or `:svg`, `filename`
  (the canvas's id unless given), without its extension, and `paper:
  true` for the canvas's paper behind the nodes (none unless asked).
  """
  @spec export(String.t(), keyword()) :: :ok
  def export(canvas, opts \\ []) when is_binary(canvas) do
    payload = %{
      "format" => Atom.to_string(opts[:format] || :png),
      "filename" => opts[:filename] || canvas,
      "paper" => opts[:paper] == true
    }

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:export", payload})
    :ok
  end

  @doc """
  Moves the view of the canvas `canvas` of this LiveView, in the person's
  browser, to show all of its nodes, as its fit button does; or:

    * `nodes: ids` - those nodes;
    * `box: {x, y, width, height}` - that part of the canvas, at the zoom
      that shows it whole (an `on_viewport`'s, to come back to it).

  `padding` is the room around them, in pixels of the screen (48 unless
  given), and `animate: false` jumps there at once. Nodes are shown at
  100% at most, so that a few are not blown up; a box at the zoom it
  needs, between the canvas's `min_zoom` and `max_zoom`.

      Hakushi.Live.fit("flow", nodes: ["start", "send-receipt"])
      Hakushi.Live.fit("flow", box: {0, 0, 1200, 800}, animate: false)
  """
  @spec fit(String.t(), keyword()) :: :ok
  def fit(canvas, opts \\ []) when is_binary(canvas) do
    payload =
      opts
      |> view_opts()
      |> put_target(opts)

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:view", payload})
    :ok
  end

  @doc """
  Brings nodes into the middle of the view of the canvas `canvas` of this
  LiveView, and selects them: a result of a search, a step an error names.
  `ids` is a node's id or a list of them.

  The view keeps its zoom, unless the nodes do not fit at it (then it shows
  them whole) or `zoom` is given. `select: false` leaves the selection as
  it is, and `animate: false` jumps there at once. A selection of the app
  does not call `on_select`.

      Hakushi.Live.focus("flow", "send-receipt")
  """
  @spec focus(String.t(), String.t() | [String.t()], keyword()) :: :ok
  def focus(canvas, ids, opts \\ []) when is_binary(canvas) do
    ids = ids!(ids)

    payload =
      opts
      |> view_opts()
      |> Map.merge(%{"focus" => ids, "select" => Keyword.get(opts, :select, true)})

    payload =
      case opts[:zoom] do
        nil ->
          payload

        zoom when is_number(zoom) and zoom > 0 ->
          Map.put(payload, "zoom", zoom)

        other ->
          raise ArgumentError, "a focus's zoom is a positive number, got: #{inspect(other)}"
      end

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:view", payload})
    :ok
  end

  @doc """
  Selects nodes on the canvas `canvas` of this LiveView, in the person's
  browser, as a click does: `ids`, a node's id or a list of them (`[]`
  selects nothing), and `edges: ids` for edges. The ids the canvas does
  not have are left out. `reveal: true` brings them into view when they
  are off the screen. A selection of the app does not call `on_select`.

      Hakushi.Live.select("schema", ["users", "orders"])
  """
  @spec select(String.t(), String.t() | [String.t()], keyword()) :: :ok
  def select(canvas, ids, opts \\ []) when is_binary(canvas) do
    payload = %{
      "nodes" => ids!(ids),
      "edges" => ids!(Keyword.get(opts, :edges, [])),
      "reveal" => Keyword.get(opts, :reveal, false) == true
    }

    send_update(Hakushi.Canvas, id: canvas, hakushi_push: {"hakushi:select", payload})
    :ok
  end

  defp view_opts(opts) do
    padding =
      case Keyword.get(opts, :padding, 48) do
        padding when is_number(padding) and padding >= 0 ->
          padding

        other ->
          raise ArgumentError, "a view's padding is a number of pixels, got: #{inspect(other)}"
      end

    %{"padding" => padding, "animate" => Keyword.get(opts, :animate, true) != false}
  end

  defp put_target(payload, opts) do
    case {opts[:nodes], opts[:box]} do
      {nil, nil} ->
        payload

      {ids, nil} ->
        Map.put(payload, "nodes", ids!(ids))

      {nil, {x, y, w, h}} when is_number(x) and is_number(y) and w > 0 and h > 0 ->
        Map.put(payload, "box", [x, y, w, h])

      {nil, other} ->
        raise ArgumentError,
              "a fit's box is {x, y, width, height}, of a positive size, got: #{inspect(other)}"

      _both ->
        raise ArgumentError, "a fit takes nodes or a box, not both"
    end
  end

  defp ids!(id) when is_binary(id), do: [id]

  defp ids!(ids) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1),
      do: ids,
      else: raise(ArgumentError, "ids are strings, got: #{inspect(ids)}")
  end

  defp ids!(other), do: raise(ArgumentError, "ids are strings, got: #{inspect(other)}")

  @doc false
  @spec ensure_mounted!(String.t()) :: :ok
  def ensure_mounted!(canvas) do
    cond do
      not Code.ensure_loaded?(Issho.Live) ->
        raise ArgumentError, """
        the canvas #{inspect(canvas)} has `issho`, which needs Issho: add {:issho, "~> 0.4.2"} \
        to your dependencies\
        """

      Process.get({Issho.Live, :mounted}) ->
        :ok

      true ->
        raise ArgumentError, """
        the canvas #{inspect(canvas)} has `issho`, which needs the Hakushi.Live hook in its \
        LiveView: `on_mount Hakushi.Live`, or `live_session :default, on_mount: [Hakushi.Live]`\
        """
    end
  end
end
