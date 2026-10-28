defmodule Hakushi.Live do
  @moduledoc ~S"""
  The `on_mount` hook of a LiveView with a shared canvas (`issho`), the
  app's own changes to a canvas, the person's view of it (what it shows,
  `fit/2` and `focus/3`, and what is selected, `select/3`), and the marks
  of what its nodes are now, which are not saved (`mark/3`).

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

  @doc """
  Marks nodes of the canvas `canvas` of this LiveView with what they are
  now, which is not saved: a step that runs, a table that failed its
  check, the results of a search. `ids` is a node's id or a list of them,
  and `mark` a keyword list or a map of:

    * `status` - an atom or a string (`:running`, `:done`, `:failed`,
      `:warning`, `:waiting`, or the app's own): `data-mark-status` on
      the node, which Hakushi's styles give a ring for the first five;
    * `badge` - a few words or a number in a corner of the node;
    * `progress` - a bar along its foot, from `0` to `1`;
    * `highlight` - `true` (a ring of the accent) or a colour;
    * `dim` - `true`: faded, for the nodes that do not matter now;
    * `title` - the words a pointer over the node shows;
    * `class` - classes of the app's own on the node.

  A mark adds to the node's: a key given `nil` goes, and a `mark` of
  `nil` takes them all away. Marks are this LiveView's, in its canvas:
  they are not part of the graph, `on_change` never sees them, and they
  go when the page goes (mark again in `mount`). On a shared canvas, each
  person's are their own.

      Hakushi.Live.mark("flow", "send-receipt", status: :running, progress: 0.4)
      Hakushi.Live.mark("flow", "send-receipt", status: :done, progress: nil)
      Hakushi.Live.mark("schema", ["users", "orders"], highlight: true)

  See [Marks](marks.md).
  """
  @spec mark(String.t(), String.t() | [String.t()], keyword() | map() | nil) :: :ok
  def mark(canvas, ids, mark) when is_binary(canvas) do
    send_update(Hakushi.Canvas, id: canvas, hakushi_mark: {:nodes, ids!(ids), mark!(mark)})
    :ok
  end

  @doc """
  Marks edges of the canvas `canvas` of this LiveView, as `mark/3` marks
  nodes: `status`, `highlight`, `dim` and `title` (an edge has no badge,
  no progress and no classes). A `:running` edge flows.

      Hakushi.Live.mark_edges("flow", ["e1", "e2"], status: :running)
  """
  @spec mark_edges(String.t(), String.t() | [String.t()], keyword() | map() | nil) :: :ok
  def mark_edges(canvas, ids, mark) when is_binary(canvas) do
    mark = mark!(mark)

    case mark && Map.keys(mark) -- [:status, :highlight, :dim, :title] do
      bad when bad in [nil, []] -> :ok
      bad -> raise ArgumentError, "an edge's mark has no #{inspect(bad)}"
    end

    send_update(Hakushi.Canvas, id: canvas, hakushi_mark: {:edges, ids!(ids), mark})
    :ok
  end

  @doc """
  Takes away every mark of the canvas `canvas` of this LiveView, of its
  nodes and its edges, and its spotlight.
  """
  @spec clear_marks(String.t()) :: :ok
  def clear_marks(canvas) when is_binary(canvas) do
    send_update(Hakushi.Canvas, id: canvas, hakushi_mark: :clear)
    :ok
  end

  @doc """
  Puts the spotlight on nodes and edges of the canvas `canvas` of this
  LiveView: the others fade, so that a path, a part of a flow, or what a
  search found stands out (`nodes: ids`, `edges: ids`). `nil` takes the
  spotlight away. It is a mark: this LiveView's, and not saved.

      Hakushi.Live.spotlight("flow", nodes: ["start", "check", "send-receipt"], edges: ["e1", "e2"])
  """
  @spec spotlight(String.t(), keyword() | nil) :: :ok
  def spotlight(canvas, nil) when is_binary(canvas) do
    send_update(Hakushi.Canvas, id: canvas, hakushi_mark: {:spotlight, nil})
    :ok
  end

  def spotlight(canvas, opts) when is_binary(canvas) and is_list(opts) do
    lit = %{
      nodes: MapSet.new(ids!(Keyword.get(opts, :nodes, []))),
      edges: MapSet.new(ids!(Keyword.get(opts, :edges, [])))
    }

    send_update(Hakushi.Canvas, id: canvas, hakushi_mark: {:spotlight, lit})
    :ok
  end

  @mark_keys [:status, :badge, :progress, :highlight, :dim, :title, :class]
  @color ~r/\A(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|(rgb|rgba|hsl|hsla|oklch|oklab)\([0-9.,%\s\/-]+\)|var\(--[a-zA-Z0-9-]+\))\z/

  @doc false
  # A mark, checked: its keys and their values (nil, to take a key away).
  @spec mark!(keyword() | map() | nil) :: map() | nil
  def mark!(nil), do: nil

  def mark!(mark) when is_list(mark) or is_map(mark) do
    Map.new(mark, fn {key, value} ->
      unless key in @mark_keys,
        do: raise(ArgumentError, "a mark has no #{inspect(key)}, it has #{inspect(@mark_keys)}")

      {key, mark_value!(key, value)}
    end)
  end

  def mark!(other),
    do: raise(ArgumentError, "a mark is a keyword list or a map, got: #{inspect(other)}")

  defp mark_value!(_key, nil), do: nil

  defp mark_value!(:status, status) when is_atom(status),
    do: mark_value!(:status, Atom.to_string(status))

  defp mark_value!(:status, status) when is_binary(status) do
    if Regex.match?(~r/\A[a-z][a-z0-9-]{0,31}\z/, status),
      do: status,
      else:
        raise(
          ArgumentError,
          "a mark's status is a word of a-z, 0-9 and -, got: #{inspect(status)}"
        )
  end

  defp mark_value!(:badge, badge) when is_binary(badge) or is_number(badge), do: to_string(badge)

  defp mark_value!(:progress, progress)
       when is_number(progress) and progress >= 0 and progress <= 1,
       do: progress

  defp mark_value!(:highlight, highlight) when is_boolean(highlight), do: highlight

  defp mark_value!(:highlight, color) when is_binary(color) do
    if Regex.match?(@color, color),
      do: color,
      else: raise(ArgumentError, "a mark's highlight is true or a colour, got: #{inspect(color)}")
  end

  defp mark_value!(:dim, dim) when is_boolean(dim), do: dim
  defp mark_value!(key, text) when key in [:title, :class] and is_binary(text), do: text

  defp mark_value!(key, value),
    do: raise(ArgumentError, "a mark's #{key} cannot be #{inspect(value)}")

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
