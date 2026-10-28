defmodule Hakushi.Test do
  @moduledoc """
  Helpers for `Phoenix.LiveViewTest`, to read and change the canvases of
  a LiveView with no browser.

      import Hakushi.Test

      test "joins two tables", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/schema")

        assert :ok = connect(view, "schema", {"orders", "user_id"}, {"users", "id"})
        assert [%{source: "orders", target: "users"}] = edges(view, "schema")

        assert {:error, "A node cannot connect to itself."} =
                 connect(view, "schema", "users", "users")
      end

  The functions send the events that the browser sends (see
  `Hakushi.Canvas`), so each change goes the way of a person's: the rules,
  `on_change`, the room of a shared canvas. A change the canvas refuses
  gives `{:error, reason}`, with the words the person sees.

  `nodes/2` and `edges/2` read what the canvas shows: the nodes and edges
  as the browser has them, in their order.
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  import ExUnit.Assertions

  alias Phoenix.LiveViewTest

  @doc """
  The nodes of the canvas `id`, in the order they are drawn: maps with
  `:id`, `:type`, `:x`, `:y`, `:width`, `:height` (`nil` for the size of
  the content), `:locked`, `:parent` (the group it is in, or `nil`) and
  `:label` (the name screen readers say).
  """
  @spec nodes(struct(), String.t()) :: [map()]
  def nodes(view, id) do
    view
    |> query(id, ".hakushi-nodes > .hakushi-node")
    |> Enum.map(fn node ->
      %{
        id: attribute(node, "data-id"),
        type: attribute(node, "data-type"),
        x: number(attribute(node, "data-x")),
        y: number(attribute(node, "data-y")),
        width: number(attribute(node, "data-width")),
        height: number(attribute(node, "data-height")),
        locked: attribute(node, "data-locked") == "true",
        parent: attribute(node, "data-parent"),
        label: attribute(node, "aria-label")
      }
    end)
  end

  @doc """
  The edges of the canvas `id`: maps with `:id`, `:source`,
  `:source_handle`, `:target`, `:target_handle`, `:path`, `:label`,
  `:marker` and `:animated`.
  """
  @spec edges(struct(), String.t()) :: [map()]
  def edges(view, id) do
    view
    |> query(id, "##{id}-edge-data > i")
    |> Enum.map(fn edge ->
      %{
        id: attribute(edge, "data-id"),
        source: attribute(edge, "data-source"),
        source_handle: attribute(edge, "data-source-handle"),
        target: attribute(edge, "data-target"),
        target_handle: attribute(edge, "data-target-handle"),
        path: attribute(edge, "data-path"),
        label: attribute(edge, "data-label"),
        marker: attribute(edge, "data-marker"),
        animated: attribute(edge, "data-animated") == "true"
      }
    end)
  end

  @doc """
  Moves nodes, as a person drags them: `{id, x, y}` for each, or one
  node's id and `{x, y}`. A tuple `{id, x, y, width, height}` resizes it
  too. A map `%{id: id, x: x, y: y, parent: group}` drops it into a group
  (or out of one, with `parent: nil`), as a drop on a group does.
  """
  @spec move(struct(), String.t(), String.t() | [tuple()], {number(), number()} | nil) ::
          :ok | {:error, String.t()}
  def move(view, id, node, place \\ nil)
  def move(view, id, node, {x, y}) when is_binary(node), do: move(view, id, [{node, x, y}])

  def move(view, id, places, nil) when is_list(places) do
    nodes =
      Enum.map(places, fn
        {node, x, y} ->
          %{"id" => node, "x" => x, "y" => y}

        {node, x, y, w, h} ->
          %{"id" => node, "x" => x, "y" => y, "width" => w, "height" => h}

        %{id: node, x: x, y: y} = place ->
          place
          |> Map.take([:parent])
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.merge(%{"id" => node, "x" => x, "y" => y})
      end)

    change(view, id, %{"op" => "move", "nodes" => nodes})
  end

  @doc """
  Connects two nodes, as a person draws an edge from a handle to a
  handle: each end a node's id, or `{node, handle}`.
  """
  @spec connect(
          struct(),
          String.t(),
          String.t() | {String.t(), String.t()},
          String.t() | {String.t(), String.t()}
        ) ::
          :ok | {:error, String.t()}
  def connect(view, id, source, target) do
    {source, source_handle} = end_of(source)
    {target, target_handle} = end_of(target)

    change(view, id, %{
      "op" => "connect",
      "edges" => [
        %{
          "source" => source,
          "sourceHandle" => source_handle,
          "target" => target,
          "targetHandle" => target_handle
        }
      ]
    })
  end

  defp end_of({node, handle}), do: {node, handle}
  defp end_of(node) when is_binary(node), do: {node, nil}

  @doc """
  Deletes nodes (with their edges) and edges, as the Delete key does:
  `nodes: ids, edges: ids`. (Not `delete`, which `Phoenix.ConnTest` has.)
  """
  @spec remove(struct(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def remove(view, id, opts) do
    change(view, id, %{
      "op" => "delete",
      "nodes" => opts[:nodes] || [],
      "edges" => opts[:edges] || []
    })
  end

  @doc """
  Moves an end of an edge to another handle, as a person drags the end of
  a selected edge: `source:` or `target:`, a node's id or
  `{node, handle}`.
  """
  @spec reconnect(struct(), String.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def reconnect(view, id, edge, ends) do
    current =
      Enum.find(edges(view, id), &(&1.id == edge)) || flunk("no edge #{inspect(edge)} in #{id}")

    {source, source_handle} =
      if s = ends[:source], do: end_of(s), else: {current.source, current.source_handle}

    {target, target_handle} =
      if t = ends[:target], do: end_of(t), else: {current.target, current.target_handle}

    change(view, id, %{
      "op" => "reconnect",
      "edges" => [
        %{
          "id" => edge,
          "source" => source,
          "sourceHandle" => source_handle,
          "target" => target,
          "targetHandle" => target_handle
        }
      ]
    })
  end

  @doc "Sets the label of an edge, or takes it away (`nil`)."
  @spec label(struct(), String.t(), String.t(), String.t() | nil) :: :ok | {:error, String.t()}
  def label(view, id, edge, label) do
    change(view, id, %{"op" => "update", "edges" => [%{"id" => edge, "label" => label}]})
  end

  @doc """
  Copies nodes, and pastes them at `{x, y}` (or next to them): gives
  `{:ok, ids}` of the new nodes.
  """
  @spec copy_paste(struct(), String.t(), [String.t()], {number(), number()} | nil) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def copy_paste(view, id, nodes, at \\ nil) do
    %{"ok" => true} = event(view, id, "hakushi:copy", %{"nodes" => nodes})
    params = if at, do: %{"x" => elem(at, 0), "y" => elem(at, 1)}, else: %{}
    selected(event(view, id, "hakushi:paste", params))
  end

  @doc "Duplicates nodes, as ⌘D does: gives `{:ok, ids}` of the copies."
  @spec duplicate(struct(), String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def duplicate(view, id, nodes),
    do: selected(event(view, id, "hakushi:duplicate", %{"nodes" => nodes}))

  @doc """
  Drops an item (`Hakushi.Components.canvas_item/1`) on the canvas at
  `{x, y}`, or double-clicks there (`item` is `nil`): gives `{:ok, [id]}`
  of the node that `new_node` made. `parent: group` drops it in a group,
  as a drop on the group does.
  """
  @spec drop(struct(), String.t(), String.t() | nil, {number(), number()}, keyword()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def drop(view, id, item, {x, y}, opts \\ []) do
    payload = %{"item" => item, "x" => x, "y" => y, "parent" => opts[:parent]}
    selected(event(view, id, "hakushi:drop", payload))
  end

  @doc """
  Edits a kit's node, as its controls do (`Hakushi.Kit`): the `action`,
  with the event's `params` (`"value"`, a column's index, ...). A list of
  nodes is edited in one change, as the style panel of a kit does
  (`c:Hakushi.Kit.styles/1`).

      edit(view, "model", "orders", "add")
      edit(view, "board", ["a", "b"], "style", %{"style" => %{"fill" => "red"}})
      edit(view, "model", "orders", "column", %{"column" => 1, "value" => "customer_id"})
  """
  @spec edit(struct(), String.t(), String.t() | [String.t()], String.t(), map()) ::
          :ok | {:error, String.t()}
  def edit(view, id, node, action, params \\ %{}) do
    target = if is_list(node), do: %{"nodes" => node}, else: %{"node" => node}

    payload =
      params
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(target)
      |> Map.put("action", action)

    result(event(view, id, "hakushi:edit", payload))
  end

  @doc """
  Draws a line with a kit's tool (`"ink:pen"`), as a pen does on the
  canvas when it lifts: its `points` on the canvas (`[x, y]` or `[x, y,
  pressure]`). Gives `{:ok, id}` of the node the kit made of it.
  Options: `:color`, `:size`, and `:parent`, the group it is drawn over.

      {:ok, id} = draw(view, "board", "ink:pen", [[0, 0], [40, 12], [80, 0]], color: "red")
  """
  @spec draw(struct(), String.t(), String.t(), [[number()]], keyword()) ::
          {:ok, String.t()} | {:error, String.t() | nil}
  def draw(view, id, tool, points, opts \\ []) do
    payload = %{
      "tool" => tool,
      "points" => points,
      "color" => opts[:color],
      "size" => opts[:size],
      "parent" => opts[:parent]
    }

    case event(view, id, "hakushi:draw", payload) do
      %{"ok" => true, "drawn" => node} -> {:ok, node}
      reply -> result(reply)
    end
  end

  @doc """
  The paper the canvas shows: `%{background: name, grid: size}`, its
  graph's when people chose one, else its own (`Hakushi.Paper`).
  """
  @spec paper(struct(), String.t()) :: %{background: String.t(), grid: pos_integer()}
  def paper(view, id) do
    config = view |> query(id, "##{id}-hook") |> attribute("data-config") |> JSON.decode!()
    %{background: config["background"], grid: config["grid"]}
  end

  @doc """
  Chooses the canvas's paper with its picker (`papers`), as a person does:
  a paper it offers, by name, and the size of its squares (one of
  `Hakushi.Paper.grids/0`).

      :ok = paper(view, "board", "lines", 40)
  """
  @spec paper(struct(), String.t(), String.t(), pos_integer()) :: :ok | {:error, String.t()}
  def paper(view, id, background, grid) do
    payload = %{"op" => "paper", "paper" => %{"background" => background, "grid" => grid}}
    result(event(view, id, "hakushi:change", payload))
  end

  @doc """
  Draws a box with a kit's tool of the mode `"box"` (`"shapes:rect"`), as
  a drag on the paper does: `[x, y, width, height]` of the canvas (a box
  of no size, as a click). Gives `{:ok, id}` of the node the kit made.
  """
  @spec draw_box(struct(), String.t(), String.t(), [number()], keyword()) ::
          {:ok, String.t()} | {:error, String.t() | nil}
  def draw_box(view, id, tool, box, opts \\ []) do
    case event(view, id, "hakushi:draw", %{
           "tool" => tool,
           "box" => box,
           "parent" => opts[:parent]
         }) do
      %{"ok" => true, "drawn" => node} -> {:ok, node}
      reply -> result(reply)
    end
  end

  @doc "Undoes the last change of this LiveView's person, as ⌘Z does."
  @spec undo(struct(), String.t()) :: :ok | {:error, String.t()}
  def undo(view, id), do: result(event(view, id, "hakushi:undo", %{}))

  @doc "Does again the last change undone, as ⇧⌘Z does."
  @spec redo(struct(), String.t()) :: :ok | {:error, String.t()}
  def redo(view, id), do: result(event(view, id, "hakushi:redo", %{}))

  @doc "The words the canvas shows for the last change it refused, or `nil`."
  @spec notice(struct(), String.t()) :: String.t() | nil
  def notice(view, id) do
    case view |> query(id, "##{id} > .hakushi-notice") |> LazyHTML.text() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  @doc """
  The people the canvas `id` shows on a shared canvas (not the person
  of this LiveView): their ids.
  """
  @spec people(struct(), String.t()) :: [String.t()]
  def people(view, id) do
    view
    |> query(id, "[data-hakushi-people] [data-person]")
    |> Enum.map(&attribute(&1, "data-person"))
  end

  @doc """
  The marks of the canvas `id` (`Hakushi.Live.mark/3`), as it draws them:
  `%{nodes: %{id => mark}, edges: %{id => mark}}`, each mark a map of the
  keys it has (`:status`, `:badge`, `:progress`, `:highlight`, `:dim`,
  `:title` and, under a spotlight, `:lit`), for the nodes and edges that
  have one.
  """
  @spec marks(struct(), String.t()) :: %{nodes: map(), edges: map()}
  def marks(view, id) do
    nodes =
      for node <- query(view, id, ".hakushi-nodes > .hakushi-node"),
          mark = node_mark(node),
          mark != %{},
          into: %{},
          do: {attribute(node, "data-id"), mark}

    edges =
      for edge <- query(view, id, "##{id}-edge-data > i"),
          mark = edge_mark(edge),
          mark != %{},
          into: %{},
          do: {attribute(edge, "data-id"), mark}

    %{nodes: nodes, edges: edges}
  end

  defp node_mark(node) do
    badge =
      node |> LazyHTML.query(".hakushi-mark-badge") |> LazyHTML.text() |> String.trim()

    progress =
      case node
           |> LazyHTML.query(".hakushi-mark-progress")
           |> attribute("aria-valuenow") do
        nil -> nil
        percent -> String.to_integer(percent) / 100
      end

    %{
      status: attribute(node, "data-mark-status"),
      badge: if(badge != "", do: badge),
      progress: progress,
      highlight: highlight(attribute(node, "data-mark-highlight"), attribute(node, "style")),
      dim: attribute(node, "data-mark-dim") == "true" || nil,
      title: attribute(node, "title"),
      lit: attribute(node, "data-lit") == "true" || nil
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp edge_mark(edge) do
    %{
      status: attribute(edge, "data-mark-status"),
      highlight:
        attribute(edge, "data-mark-color") ||
          (attribute(edge, "data-mark-highlight") == "true" || nil),
      dim: attribute(edge, "data-mark-dim") == "true" || nil,
      title: attribute(edge, "data-mark-title"),
      lit: attribute(edge, "data-lit") == "true" || nil
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp highlight("true", style) do
    case Regex.run(~r/--hakushi-mark: ([^;]+);/, style || "") do
      [_, color] -> color
      nil -> true
    end
  end

  defp highlight(_none, _style), do: nil

  @doc """
  Selects nodes, and edges, as a person does with a click or a box: the
  canvas's `on_select` hears it. To select from the app, as
  `Hakushi.Live.select/3` does, assert its push of `"hakushi:select"`.
  """
  @spec select(struct(), String.t(), [String.t()], [String.t()]) :: :ok
  def select(view, id, nodes, edges \\ []) do
    tell(view, id, "hakushi:select", %{"nodes" => nodes, "edges" => edges})
  end

  @doc """
  Moves the person's view to show the part `{x, y, width, height}` of the
  canvas at `zoom`, as a pan or a zoom that comes to rest does: the
  canvas's `on_viewport` hears it.
  """
  @spec viewport(struct(), String.t(), {number(), number(), number(), number()}, number()) :: :ok
  def viewport(view, id, {x, y, width, height}, zoom) do
    tell(view, id, "hakushi:viewport", %{"box" => [x, y, width, height], "zoom" => zoom})
  end

  defp change(view, id, params), do: result(event(view, id, "hakushi:change", params))

  # An event the browser sends without waiting for a reply.
  defp tell(view, id, name, payload) do
    view
    |> LiveViewTest.element("##{id}-hook")
    |> LiveViewTest.render_hook(name, payload)

    :ok
  end

  defp result(%{"ok" => true}), do: :ok
  defp result(%{"ok" => false}), do: {:error, nil}
  defp result(%{"error" => message}), do: {:error, message}

  defp selected(%{"ok" => true, "select" => ids}), do: {:ok, ids}
  defp selected(reply), do: result(reply)

  defp event(view, id, name, payload) do
    # A render first: changes broadcast before this call reach the canvas
    # before the event does.
    LiveViewTest.render(view)

    view
    |> LiveViewTest.element("##{id}-hook")
    |> LiveViewTest.render_hook(name, payload)

    %{proxy: {ref, _topic, _pid}} = view

    receive do
      {^ref, {:reply, reply}} -> reply
    after
      1000 -> flunk("the canvas #{id} did not answer #{name}")
    end
  end

  defp query(view, id, selector) do
    # A change of a shared canvas comes to the LiveView, which passes it to
    # the canvas (a message to itself): the first render lets it pass it,
    # the second has it.
    LiveViewTest.render(view)
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()

    if LazyHTML.query(html, "##{id}") |> Enum.empty?(),
      do: flunk("no canvas with the id #{inspect(id)}")

    LazyHTML.query(
      html,
      if(String.starts_with?(selector, "#"), do: selector, else: "##{id} #{selector}")
    )
  end

  defp attribute(node, name) do
    case LazyHTML.attribute(node, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp number(nil), do: nil

  defp number(text) do
    case Integer.parse(text) do
      {int, ""} -> int
      _other -> String.to_float(text)
    end
  end
end
