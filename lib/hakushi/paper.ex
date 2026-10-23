defmodule Hakushi.Paper do
  @moduledoc """
  The paper of a canvas: its pattern (`background`) and the size of its
  squares (`grid`), which nodes snap to.

  A canvas's paper is its `background` and `grid` attributes (or its first
  kit's, see `c:Hakushi.Kit.canvas/0`), unless its graph has one of its
  own (`Hakushi.Graph`'s `paper`): the paper people chose, with the
  canvas's paper picker (`papers`), or the app (`Hakushi.Change.paper/1`).
  It is a change as any other: it goes through `on_change`, ⌘Z takes it
  back, and on a shared canvas everyone sees it.

      %{background: "lines", grid: 24}

  ## The papers people choose from

  The canvas's `papers` attribute turns the picker on, in its controls:
  `true` for Hakushi's papers (`builtin/0`), or a list of the papers it
  offers, Hakushi's by their atom and the app's own by their name and
  label:

      <.canvas id="board" graph={@graph} papers={[:dots, :lines, %{name: "iso", label: "Isometric"}]} />

  ## A paper of the app's own

  A paper is a pattern of CSS, drawn on the paper of the canvas
  (`.hakushi[data-background="iso"] .hakushi-background`) and on its
  swatch in the picker (`.hakushi-paper-swatch[data-background="iso"]`).
  The canvas moves the pattern with the view, and sets its custom
  properties: `--hakushi-grid-size`, a square on the screen (the grid at
  the zoom); `--hakushi-pattern` and `--hakushi-pattern-strong`, the colours
  of the paper's lines (see the Theming guide).

      .hakushi[data-background="iso"] .hakushi-background,
      .hakushi-paper-swatch[data-background="iso"] {
        background-image:
          linear-gradient(30deg, var(--hakushi-pattern) 1px, transparent 1px),
          linear-gradient(150deg, var(--hakushi-pattern) 1px, transparent 1px);
        background-size: var(--hakushi-grid-size) calc(var(--hakushi-grid-size) * 0.577);
      }

  Give it to the canvas as its `background` (`background="iso"`), or in
  its `papers`.
  """

  @builtin ~w(dots lines cross none)
  @grids [10, 20, 40]

  @typedoc "A paper: its pattern's name and its squares' size, each `nil` for the canvas's own."
  @type t :: %{background: String.t() | nil, grid: pos_integer() | nil}

  @typedoc "A paper offered in the picker: its name, and its label (`nil` for Hakushi's words)."
  @type offer :: %{name: String.t(), label: String.t() | nil}

  @doc "The names of Hakushi's papers: dots, graph paper, crosses and none."
  @spec builtin() :: [String.t()]
  def builtin, do: @builtin

  @doc "The sizes of the squares the picker offers, in pixels at 100%."
  @spec grids() :: [pos_integer()]
  def grids, do: @grids

  @doc """
  A paper of a map or a keyword list with `:background` (an atom or a
  string) and `:grid`, or `nil` for none. Raises on a name that is not one
  (letters, digits and dashes) or a grid that is not a whole number from 4
  to 200.
  """
  @spec new(nil | map() | keyword()) :: t() | nil
  def new(nil), do: nil
  def new(fields) when is_list(fields), do: fields |> Map.new() |> new()

  def new(%{} = fields) do
    background = Hakushi.Node.get(fields, :background, nil)
    grid = Hakushi.Node.get(fields, :grid, nil)

    case {name(background), grid(grid)} do
      {:error, _grid} ->
        raise ArgumentError, "a paper's background must be a name, got: #{inspect(background)}"

      {_name, :error} ->
        raise ArgumentError, "a paper's grid must be from 4 to 200, got: #{inspect(grid)}"

      {name, grid} ->
        %{background: name, grid: grid}
    end
  end

  defp name(nil), do: nil
  defp name(name) when is_atom(name), do: name |> Atom.to_string() |> name()

  defp name(name) when is_binary(name) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,39}\z/, name), do: name, else: :error
  end

  defp name(_other), do: :error

  defp grid(nil), do: nil
  defp grid(grid) when is_integer(grid) and grid in 4..200, do: grid
  defp grid(_other), do: :error

  @doc false
  # The papers a canvas offers (its `papers` attribute), as the picker
  # lists them.
  @spec offered(term()) :: [offer()]
  def offered(nil), do: []
  def offered(false), do: []
  def offered(true), do: offered(Enum.map(@builtin, &String.to_atom/1))
  def offered(papers) when is_list(papers), do: Enum.map(papers, &offer/1)

  def offered(other),
    do:
      raise(
        ArgumentError,
        "a canvas's papers are true or a list of papers, got: #{inspect(other)}"
      )

  defp offer(%{} = paper) do
    label = Hakushi.Node.get(paper, :label, nil)
    %{name: checked_name(Hakushi.Node.get(paper, :name, nil)), label: label && to_string(label)}
  end

  defp offer({name, label}), do: %{name: checked_name(name), label: to_string(label)}
  defp offer(name), do: %{name: checked_name(name), label: nil}

  defp checked_name(name) do
    case name(name) do
      checked when is_binary(checked) ->
        checked

      _error ->
        raise ArgumentError, "a paper's name is letters, digits and dashes, got: #{inspect(name)}"
    end
  end

  @doc false
  # The paper a browser asks for, checked: one the canvas offers, with a
  # grid of the picker's.
  @spec from_client(term(), [offer()]) :: {:ok, t()} | :error
  def from_client(%{"background" => background, "grid" => grid}, offered)
      when is_binary(background) and is_integer(grid) do
    if Enum.any?(offered, &(&1.name == background)) and grid in @grids,
      do: {:ok, %{background: background, grid: grid}},
      else: :error
  end

  def from_client(_params, _offered), do: :error
end
