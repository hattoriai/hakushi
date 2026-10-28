defmodule Hakushi.Menu do
  @moduledoc """
  The menu of a canvas: what a right click on a node, an edge or the
  paper offers (or the menu key, or Shift+F10, on what is selected).

      <.canvas id="flow" graph={@graph} menu={&menu/1} on_menu={&send(self(), {:menu, &1, &2})}>

      def menu(%{kind: :node, nodes: [id]}),
        do: [%{id: "inspect", label: "Inspect"}, :separator, :copy, :duplicate, :delete]

      def menu(%{kind: :node}), do: [:copy, :duplicate, :delete]
      def menu(%{kind: :edge}), do: [:label, :delete]
      def menu(%{kind: :canvas}), do: [:paste, :select_all, :fit, :tidy]

  The canvas's `menu` is a function of the target (below) that gives the
  items, or `true` for Hakushi's own items of each kind (`defaults/1`).
  A list without items shows no menu.

  ## The target

  A map of the `canvas`'s id, the `kind` of thing under the pointer
  (`:node`, `:edge` or `:canvas`, the paper), the ids of the `nodes` and
  `edges` selected (a right click on a node that is not selected selects
  it), and the point of the canvas it was at (`at`, `{x, y}`).

  ## The items

    * an atom, an action of the canvas's own, which the canvas runs and
      names in its language: `:copy`, `:cut`, `:paste`, `:duplicate`,
      `:delete`, `:select_all`, `:label` (an edge's), `:fit`, `:tidy`,
      `:undo`, `:redo`, `:align_left`, `:align_center`, `:align_right`,
      `:align_top`, `:align_middle`, `:align_bottom`,
      `:distribute_horizontal`, `:distribute_vertical`; and `:separator`,
      a line between items. A person
      who may not change the canvas is not offered those that change it.
    * a map of the app's own: `:id` and `:label` (required), `:icon` (a
      name of `Hakushi.Icons`), `:shortcut` (the words of its keys, shown
      beside it), `:danger` (`true`, in the colour of a delete) and
      `:disabled` (`true`, shown and not chosen). A person who chooses it
      calls the canvas's `on_menu` with its `id` and the target, in the
      LiveView's process, and `notify` hears `{:menu, id, target}`.
  """

  @actions [
    :copy,
    :cut,
    :paste,
    :duplicate,
    :delete,
    :select_all,
    :label,
    :fit,
    :tidy,
    :undo,
    :redo,
    :align_left,
    :align_center,
    :align_right,
    :align_top,
    :align_middle,
    :align_bottom,
    :distribute_horizontal,
    :distribute_vertical
  ]

  # What a person who changes nothing (readonly) may still do, and one who
  # only arranges the nodes (readonly: :arrange).
  @viewing [:select_all, :fit]
  @arranging [
    :tidy,
    :undo,
    :redo,
    :align_left,
    :align_center,
    :align_right,
    :align_top,
    :align_middle,
    :align_bottom,
    :distribute_horizontal,
    :distribute_vertical
  ]

  @typedoc "What the menu is of."
  @type target :: %{
          canvas: String.t(),
          kind: :node | :edge | :canvas,
          nodes: [String.t()],
          edges: [String.t()],
          at: {number(), number()}
        }

  @typedoc "An item: an action of the canvas, a line, or the app's own."
  @type item :: atom() | %{required(:id) => String.t(), required(:label) => String.t()}

  @doc "The actions of the canvas's own that a menu may have."
  @spec actions() :: [atom()]
  def actions, do: @actions

  @doc """
  Hakushi's own items for a target (a menu of `true`): for nodes, copy,
  cut, duplicate and delete, and for two or more, lining them up (and for
  three or more, spacing them out); for an edge, its label and delete; for
  the paper, paste, select all, fit and tidy up.
  """
  @spec defaults(target()) :: [item()]
  def defaults(%{kind: :node, nodes: [_, _ | _] = nodes}) do
    spread = if length(nodes) >= 3, do: [:distribute_horizontal, :distribute_vertical], else: []

    [:copy, :cut, :duplicate, :separator] ++
      [:align_left, :align_center, :align_right, :align_top, :align_middle, :align_bottom] ++
      spread ++ [:separator, :delete]
  end

  def defaults(%{kind: :node}), do: [:copy, :cut, :duplicate, :separator, :delete]
  def defaults(%{kind: :edge}), do: [:label, :separator, :delete]
  def defaults(%{kind: :canvas}), do: [:paste, :select_all, :separator, :fit, :tidy]

  @doc false
  # The items as the browser draws them (JSON), those the person may
  # choose, without separators at either end or two together; and the ids
  # of the app's own, which a choice must be one of.
  @spec to_client([item()], map()) :: {[map()], MapSet.t()}
  def to_client(items, %{messages: messages} = can) when is_list(items) do
    items =
      items
      |> Enum.map(&item!/1)
      |> Enum.filter(&allowed?(&1, can))
      |> tidy_separators()

    client = Enum.map(items, &client_item(&1, messages))
    ids = for %{id: id} <- items, into: MapSet.new(), do: id
    {client, ids}
  end

  def to_client(other, _can),
    do: raise(ArgumentError, "a canvas's menu gives a list of items, got: #{inspect(other)}")

  defp item!(:separator), do: :separator
  defp item!(action) when action in @actions, do: {:action, action}

  defp item!(%{id: id, label: label} = item) when is_binary(id) and is_binary(label) do
    case Map.keys(item) -- [:id, :label, :icon, :shortcut, :danger, :disabled] do
      [] -> :ok
      keys -> raise ArgumentError, "a menu item has no #{inspect(keys)}: #{inspect(item)}"
    end

    if item[:icon] && item.icon not in Hakushi.Icons.names(),
      do:
        raise(
          ArgumentError,
          "a menu item's icon is one of #{inspect(Hakushi.Icons.names())}, got: #{inspect(item.icon)}"
        )

    item
  end

  defp item!(other) do
    raise ArgumentError,
          "a menu item is one of #{inspect(@actions ++ [:separator])}, or a map with an :id and a :label, got: #{inspect(other)}"
  end

  defp allowed?({:action, action}, %{readonly: true, arrange: arrange}),
    do: action in @viewing or (arrange and action in @arranging)

  defp allowed?(_item, _can), do: true

  defp tidy_separators(items) do
    items
    |> Enum.reduce([], fn
      :separator, [] -> []
      :separator, [:separator | _] = acc -> acc
      item, acc -> [item | acc]
    end)
    |> Enum.drop_while(&(&1 == :separator))
    |> Enum.reverse()
  end

  defp client_item(:separator, _messages), do: %{"separator" => true}

  defp client_item({:action, action}, messages) do
    %{"action" => Atom.to_string(action), "label" => action_label(action, messages)}
  end

  defp client_item(item, _messages) do
    %{
      "id" => item.id,
      "label" => item.label,
      "icon" => item[:icon] && Hakushi.Icons.svg(item.icon),
      "shortcut" => item[:shortcut],
      "danger" => item[:danger] == true,
      "disabled" => item[:disabled] == true
    }
  end

  defp action_label(:fit, messages), do: messages["fit"]
  defp action_label(:tidy, messages), do: messages["layout"]
  defp action_label(:undo, messages), do: messages["undo"]
  defp action_label(:redo, messages), do: messages["redo"]
  defp action_label(:select_all, messages), do: messages["menuSelectAll"]

  defp action_label(action, messages),
    do: messages["menu" <> Macro.camelize(Atom.to_string(action))]

  @doc false
  # The target the browser sends, checked: the ids the canvas has, a kind,
  # a point.
  @spec target(map(), String.t(), Hakushi.Graph.t()) :: target()
  def target(params, canvas, graph) do
    kind =
      case params["kind"] do
        "node" -> :node
        "edge" -> :edge
        _other -> :canvas
      end

    at =
      case params["at"] do
        [x, y] when is_number(x) and is_number(y) -> {x, y}
        _other -> {0, 0}
      end

    %{
      canvas: canvas,
      kind: kind,
      nodes: ids(params["nodes"], &Hakushi.Graph.node(graph, &1)),
      edges: ids(params["edges"], &Hakushi.Graph.edge(graph, &1)),
      at: at
    }
  end

  defp ids(list, has) when is_list(list),
    do: list |> Enum.filter(&is_binary/1) |> Enum.take(5_000) |> Enum.filter(has)

  defp ids(_other, _has), do: []
end
