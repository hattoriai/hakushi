defmodule Hakushi.Node do
  @moduledoc """
  A node of a canvas: a box at a place, drawn by the `:node` slot of its
  `type`.

      %Hakushi.Node{id: "users", type: "table", x: 120, y: 80, data: %{name: "users"}}

    * `id` - a string, unique in the canvas.
    * `type` - the name of the `:node` slot that draws it (`"default"`
      unless set).
    * `x`, `y` - the place of its top left corner, in the canvas's units
      (pixels at 100%).
    * `width`, `height` - its size; `nil` (the default) for the size of its
      content. A node that people resize gets both.
    * `data` - anything of the app's: the slot gets the node, and draws it
      from its data. It stays on the server; the browser has only what the
      slot renders.
    * `locked` - a locked node does not move, resize or go away, in the
      browser or on the server.
    * `parent` - the id of the node it is in (a frame, a group), or `nil`.
      A node moves with its parent and goes with it; people put a node in
      a group by dropping it there, and take it out by dragging it out.
      See [Groups](groups.md).
  """

  @enforce_keys [:id]
  defstruct id: nil,
            type: "default",
            x: 0,
            y: 0,
            width: nil,
            height: nil,
            data: %{},
            locked: false,
            parent: nil

  @type id :: String.t()

  @type t :: %__MODULE__{
          id: id(),
          type: String.t(),
          x: number(),
          y: number(),
          width: number() | nil,
          height: number() | nil,
          data: term(),
          locked: boolean(),
          parent: id() | nil
        }

  @doc """
  Makes a node of a map or a keyword list: the struct's keys as atoms or
  strings. Raises on a node without an id, or with a place that is not a
  number.
  """
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = node), do: check!(node)
  def new(fields) when is_list(fields), do: fields |> Map.new() |> new()

  def new(%{} = fields) do
    node = %__MODULE__{
      id: fetch(fields, :id),
      type: to_string(get(fields, :type, "default")),
      x: get(fields, :x, 0),
      y: get(fields, :y, 0),
      width: get(fields, :width, nil),
      height: get(fields, :height, nil),
      data: get(fields, :data, %{}),
      locked: get(fields, :locked, false) == true,
      parent: get(fields, :parent, nil)
    }

    check!(node)
  end

  defp check!(%__MODULE__{id: id} = node) do
    unless is_binary(id) and id != "",
      do: raise(ArgumentError, "a node's id must be a non-empty string, got: #{inspect(id)}")

    for key <- [:x, :y],
        not is_number(Map.fetch!(node, key)),
        do: raise(ArgumentError, "the #{key} of node #{inspect(id)} must be a number")

    check_parent!(node)

    for key <- [:width, :height],
        value = Map.fetch!(node, key),
        value != nil and not (is_number(value) and value > 0),
        do: raise(ArgumentError, "the #{key} of node #{inspect(id)} must be a positive number")

    node
  end

  defp check_parent!(%__MODULE__{parent: nil}), do: :ok

  defp check_parent!(%__MODULE__{id: id, parent: parent}) when is_binary(parent) and parent != id,
    do: :ok

  defp check_parent!(%__MODULE__{id: id}),
    do: raise(ArgumentError, "the parent of node #{inspect(id)} must be another node's id")

  @doc false
  def fetch(fields, key) do
    case get(fields, key, nil) do
      nil -> raise ArgumentError, "missing #{key} in #{inspect(fields)}"
      value -> value
    end
  end

  @doc false
  def get(fields, key, default) do
    case Map.fetch(fields, key) do
      {:ok, value} -> value
      :error -> Map.get(fields, Atom.to_string(key), default)
    end
  end
end
