defmodule Hakushi.Kits.Schema do
  @moduledoc """
  The kit of a database schema: tables, with columns that have a name, a
  type and a key (primary or foreign), and foreign keys drawn from a
  column to a column of the same type.

  A table is a node of type `"schema-table"` whose data is:

      %{
        "name" => "orders",
        "columns" => [
          %{"id" => "c1", "name" => "id", "type" => "uuid", "key" => "pk"},
          %{"id" => "c2", "name" => "customer_id", "type" => "uuid", "key" => "fk"},
          %{"id" => "c3", "name" => "placed_at", "type" => "timestamp", "key" => nil}
        ]
      }

  Each column has a handle on each side, of the column's type: an edge
  joins two columns of one type, and takes the sides nearest each other.
  A column's handles are its `"id"` (its name, for a column without one),
  so a foreign key stays when people rename the column.
  People rename the table and its columns in place, pick a column's type,
  set its key, and add and remove columns.
  """

  use Hakushi.Kit

  @types ~w(uuid text integer bigint decimal money boolean date timestamp json)

  @doc "The column types people pick from."
  @spec column_types() :: [String.t()]
  def column_types, do: @types

  @impl true
  def name, do: "schema"

  @impl true
  def title(messages), do: messages["kitSchema"]

  @impl true
  def icon, do: "database"

  @impl true
  def canvas, do: [background: :lines, layout: :right, rules: [loops: false]]

  @impl true
  def types, do: ["schema-table"]

  @impl true
  def elements(messages), do: [%{item: "table", label: messages["table"], icon: "table"}]

  @impl true
  def new_node(_item, {x, y}, _messages) do
    %{
      type: "schema-table",
      x: x,
      y: y,
      data: %{"name" => "new_table", "columns" => [column("id", "uuid", "pk")]}
    }
  end

  defp column(name, type, key \\ nil),
    do: %{"id" => column_id(), "name" => name, "type" => type, "key" => key}

  defp column_id, do: "c" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

  defp handle_id(column), do: get(column, "id") || get(column, "name")

  @impl true
  def node(assigns) do
    assigns =
      assign(assigns,
        name: get(assigns.node.data, "name"),
        columns: Enum.with_index(get(assigns.node.data, "columns") || [])
      )

    ~H"""
    <div class="hakushi-kit-table">
      <div class="hakushi-kit-table-head">
        <.icon name="database" size={13} />
        <input
          :if={!@readonly}
          class="hakushi-kit-field hakushi-kit-table-name"
          value={@name}
          aria-label={@messages["tableName"]}
          spellcheck="false"
          phx-blur="hakushi:edit"
          phx-keydown="hakushi:edit"
          phx-key="Enter"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="name"
        />
        <span :if={@readonly} class="hakushi-kit-table-name">{@name}</span>
      </div>
      <div :for={{c, i} <- @columns} class="hakushi-kit-column">
        <.handle id={handle_id(c)} side={:left} type={get(c, "type")} accepts={[get(c, "type")]} />
        <button
          type="button"
          class="hakushi-kit-key"
          data-key={get(c, "key")}
          disabled={@readonly}
          aria-label={word(@messages, "columnKey", get(c, "name"))}
          title={!@readonly && word(@messages, "columnKey", get(c, "name"))}
          phx-click="hakushi:edit"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="key"
          phx-value-column={i}
        >
          <.icon :if={get(c, "key") == "pk"} name="key" size={11} />
          <span :if={get(c, "key") == "fk"}>FK</span>
        </button>
        <input
          :if={!@readonly}
          class="hakushi-kit-field hakushi-kit-column-name"
          value={get(c, "name")}
          aria-label={@messages["columnName"]}
          spellcheck="false"
          phx-blur="hakushi:edit"
          phx-keydown="hakushi:edit"
          phx-key="Enter"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="column"
          phx-value-column={i}
        />
        <span :if={@readonly} class="hakushi-kit-column-name">{get(c, "name")}</span>
        <form
          :if={!@readonly}
          id={"#{@canvas}-#{@node.id}-type-#{i}"}
          class="hakushi-kit-type"
          phx-auto-recover="ignore"
          phx-change="hakushi:edit"
          phx-submit="hakushi:edit"
          phx-target={@target}
        >
          <input type="hidden" name="node" value={@node.id} />
          <input type="hidden" name="action" value="type" />
          <input type="hidden" name="column" value={i} />
          <select name="value" aria-label={word(@messages, "columnType", get(c, "name"))}>
            <option :for={t <- types_with(get(c, "type"))} value={t} selected={t == get(c, "type")}>
              {t}
            </option>
          </select>
        </form>
        <span :if={@readonly} class="hakushi-kit-type">{get(c, "type")}</span>
        <button
          :if={!@readonly}
          type="button"
          class="hakushi-kit-remove"
          aria-label={word(@messages, "removeColumn", get(c, "name"))}
          title={word(@messages, "removeColumn", get(c, "name"))}
          phx-click="hakushi:edit"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="remove"
          phx-value-column={i}
        >
          <.icon name="x" size={12} />
        </button>
        <.handle id={handle_id(c)} side={:right} type={get(c, "type")} accepts={[get(c, "type")]} />
      </div>
      <button
        :if={!@readonly}
        type="button"
        class="hakushi-kit-add"
        phx-click="hakushi:edit"
        phx-target={@target}
        phx-value-node={@node.id}
        phx-value-action="add"
      >
        <.icon name="plus" size={12} /> {@messages["addColumn"]}
      </button>
    </div>
    """
  end

  # A type of the app's own (a column made elsewhere) stays in the list.
  defp types_with(type), do: if(type in @types or is_nil(type), do: @types, else: [type | @types])

  @impl true
  def edit("name", %{"value" => name}, data) do
    case identifier(name) do
      nil -> :error
      name -> {:ok, Map.put(data, "name", name)}
    end
  end

  def edit("column", %{"value" => name} = params, data) do
    case identifier(name) do
      nil -> :error
      name -> update_column(data, params, &Map.put(&1, "name", name))
    end
  end

  def edit("type", %{"value" => type} = params, data) when type in @types,
    do: update_column(data, params, &Map.put(&1, "type", type))

  def edit("key", params, data),
    do: update_column(data, params, &Map.put(&1, "key", next_key(get(&1, "key"))))

  def edit("remove", params, data) do
    with {:ok, i, columns} <- column_at(data, params),
         do: {:ok, Map.put(data, "columns", List.delete_at(columns, i))}
  end

  def edit("add", _params, data) do
    columns = columns(data)
    names = MapSet.new(columns, &get(&1, "name"))

    name =
      Stream.iterate(length(columns) + 1, &(&1 + 1))
      |> Stream.map(&"column_#{&1}")
      |> Enum.find(&(not MapSet.member?(names, &1)))

    {:ok, Map.put(data, "columns", columns ++ [column(name, "text")])}
  end

  def edit(_action, _params, _data), do: :error

  defp next_key(nil), do: "pk"
  defp next_key("pk"), do: "fk"
  defp next_key(_fk), do: nil

  defp columns(data), do: Enum.map(get(data, "columns") || [], &Hakushi.Kit.stringify/1)

  defp column_at(data, %{"column" => i}) do
    columns = columns(data)

    case Integer.parse(to_string(i)) do
      {i, ""} when i >= 0 and i < length(columns) -> {:ok, i, columns}
      _other -> :error
    end
  end

  defp column_at(_data, _params), do: :error

  defp update_column(data, params, fun) do
    with {:ok, i, columns} <- column_at(data, params),
         do: {:ok, Map.put(data, "columns", List.update_at(columns, i, fun))}
  end

  # A name of a table or a column: lower case letters, digits and
  # underscores, as people write them in SQL.
  defp identifier(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> nil
      name -> String.slice(name, 0, 63)
    end
  end
end
