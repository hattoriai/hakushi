if Code.ensure_loaded?(Ecto.Type) do
  defmodule Hakushi.Graph.Type do
    @moduledoc """
    An Ecto type for a whole canvas in one column: a `:map` (`jsonb` on
    PostgreSQL, JSON text on SQLite and MySQL).

        schema "diagrams" do
          field :graph, Hakushi.Graph.Type, default: Hakushi.Graph.new()
        end

        # the migration
        add :graph, :map, null: false, default: %{}

    The column holds `Hakushi.Graph.dump/1`'s maps, so the `data` of the
    nodes and edges must be JSON-able, and comes back with string keys.
    A canvas whose nodes are rows of their own (the tables of a schema, the
    steps of a workflow) keeps them in its own tables instead, and makes
    its graph of them.
    """

    use Ecto.Type

    alias Hakushi.Graph

    @impl true
    def type, do: :map

    @impl true
    def cast(%Graph{} = graph), do: {:ok, graph}

    def cast(%{} = map) do
      {:ok, Graph.load(map)}
    rescue
      ArgumentError -> :error
    end

    def cast(_value), do: :error

    @impl true
    def load(%{} = map), do: cast(map)
    def load(_value), do: :error

    @impl true
    def dump(%Graph{} = graph), do: {:ok, Graph.dump(graph)}
    def dump(_value), do: :error

    @impl true
    def equal?(%Graph{} = a, %Graph{} = b), do: Graph.dump(a) == Graph.dump(b)
    def equal?(a, b), do: a == b

    @impl true
    def embed_as(_format), do: :self
  end
end
