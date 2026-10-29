defmodule Hakushi.Edge do
  @moduledoc """
  An edge of a canvas: a line from a handle of one node to a handle of
  another.

      %Hakushi.Edge{id: "e1", source: "orders", source_handle: "user_id", target: "users", target_handle: "id"}

    * `id` - a string, unique in the canvas.
    * `source`, `target` - the ids of its nodes.
    * `source_handle`, `target_handle` - the ids of the handles in those
      nodes (`Hakushi.Components.handle/1`); `nil` for the node's first
      handle of that kind, or its side when it has none.
    * `path` - how it is drawn: `"bezier"` (the default), `"smooth"` (steps
      with round corners), `"step"` or `"straight"`.
    * `label` - a text on its middle, or `nil`.
    * `marker` - the end of the line at the target: `"arrow"` (the
      default), `"dot"` or `"none"`.
    * `animated` - a line that flows from the source to the target.
    * `points` - the points it goes through on its way, `[x, y]` each,
      in the canvas's terms: where people bent it (a waypoint dragged
      out of its line); `[]` for none, the way its `path` takes.
    * `data` - anything of the app's; it stays on the server.
  """

  @paths ~w(bezier smooth step straight)
  @markers ~w(arrow dot none)

  @enforce_keys [:id, :source, :target]
  defstruct id: nil,
            source: nil,
            source_handle: nil,
            target: nil,
            target_handle: nil,
            path: "bezier",
            label: nil,
            marker: "arrow",
            animated: false,
            points: [],
            data: %{}

  @type id :: String.t()

  @type t :: %__MODULE__{
          id: id(),
          source: Hakushi.Node.id(),
          source_handle: String.t() | nil,
          target: Hakushi.Node.id(),
          target_handle: String.t() | nil,
          path: String.t(),
          label: String.t() | nil,
          marker: String.t(),
          animated: boolean(),
          points: [[number()]],
          data: term()
        }

  @doc "The kinds of `path`."
  @spec paths() :: [String.t()]
  def paths, do: @paths

  @doc """
  Makes an edge of a map or a keyword list: the struct's keys as atoms or
  strings. An edge with no id gets one made of its ends.
  """
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = edge), do: check!(edge)
  def new(fields) when is_list(fields), do: fields |> Map.new() |> new()

  def new(%{} = fields) do
    import Hakushi.Node, only: [get: 3, fetch: 2]

    source = fetch(fields, :source)
    target = fetch(fields, :target)
    source_handle = optional_string(get(fields, :source_handle, nil))
    target_handle = optional_string(get(fields, :target_handle, nil))

    edge = %__MODULE__{
      id: get(fields, :id, nil) || default_id(source, source_handle, target, target_handle),
      source: source,
      source_handle: source_handle,
      target: target,
      target_handle: target_handle,
      path: to_string(get(fields, :path, "bezier")),
      label: optional_string(get(fields, :label, nil)),
      marker: to_string(get(fields, :marker, "arrow")),
      animated: get(fields, :animated, false) == true,
      points: points(get(fields, :points, [])),
      data: get(fields, :data, %{})
    }

    check!(edge)
  end

  @doc """
  The id of an edge made of its ends, as `new/1` gives an edge with none:
  the same ends make the same id.
  """
  @spec default_id(String.t(), String.t() | nil, String.t(), String.t() | nil) :: String.t()
  def default_id(source, source_handle, target, target_handle) do
    "#{source}:#{source_handle}->#{target}:#{target_handle}"
  end

  # The most points an edge goes through.
  @max_points 100

  @doc false
  # Points as an edge keeps them, `[x, y]` each: of pairs, tuples or maps;
  # :error for anything else.
  @spec points(term()) :: [[number()]] | :error
  def points(nil), do: []

  def points(points) when is_list(points) and length(points) <= @max_points do
    points = Enum.map(points, &point/1)
    if Enum.member?(points, :error), do: :error, else: points
  end

  def points(_other), do: :error

  defp point([x, y]) when is_number(x) and is_number(y), do: [x, y]
  defp point({x, y}) when is_number(x) and is_number(y), do: [x, y]
  defp point(%{x: x, y: y}) when is_number(x) and is_number(y), do: [x, y]
  defp point(%{"x" => x, "y" => y}) when is_number(x) and is_number(y), do: [x, y]
  defp point(_other), do: :error

  defp optional_string(nil), do: nil
  defp optional_string(""), do: nil
  defp optional_string(value), do: to_string(value)

  defp check!(%__MODULE__{} = edge) do
    for key <- [:id, :source, :target],
        value = Map.fetch!(edge, key),
        not (is_binary(value) and value != ""),
        do:
          raise(
            ArgumentError,
            "an edge's #{key} must be a non-empty string, got: #{inspect(value)}"
          )

    unless edge.path in @paths,
      do:
        raise(
          ArgumentError,
          "an edge's path must be one of #{inspect(@paths)}, got: #{inspect(edge.path)}"
        )

    if edge.points == :error,
      do:
        raise(
          ArgumentError,
          "an edge's points are at most #{@max_points} of [x, y], got: #{inspect(edge.points)}"
        )

    unless edge.marker in @markers,
      do:
        raise(
          ArgumentError,
          "an edge's marker must be one of #{inspect(@markers)}, got: #{inspect(edge.marker)}"
        )

    edge
  end
end
