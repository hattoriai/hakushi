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

  Each column has a handle on each side, of the column's family of types
  (`family/1`): an edge joins two columns of one family (`integer` to
  `bigint`, `varchar(64)` to `text`, but not `text` to `uuid`), and takes
  the sides nearest each other.
  A column's handles are its `"id"` (its name, for a column without one),
  so a foreign key stays when people rename the column.
  People rename the table and its columns in place, pick a column's type,
  set its key, and add and remove columns.

  In Markdown, a schema is a Mermaid entity relationship diagram: each
  table with its columns (`uuid id PK`), and a foreign key as a
  relationship from its table to the table it refers to, named after its
  column. `from_markdown/1` reads it back, and reads ER diagrams people
  write: a relationship becomes an edge from the column it names (else
  the table's first column) to the other table's primary key.
  """

  use Hakushi.Kit

  alias Hakushi.{Graph, Mermaid}

  @types ~w(uuid text integer bigint decimal money boolean date timestamp json)

  @doc "The column types people pick from."
  @spec column_types() :: [String.t()]
  def column_types, do: @types

  # The families of types, by the names databases give them (sizes and
  # modifiers aside): Postgres, MySQL, SQLite, SQL Server, and Ecto's.
  @families %{
    "integer" =>
      ~w(integer int int2 int4 int8 smallint bigint tinyint mediumint serial serial2 serial4 serial8 smallserial bigserial id),
    "decimal" => ~w(decimal numeric money smallmoney),
    "float" => ~w(float float4 float8 real double) ++ ["double precision"],
    "text" =>
      ~w(text varchar char character nchar nvarchar bpchar citext string tinytext mediumtext longtext clob ntext name) ++
        ["character varying", "national character varying"],
    "uuid" => ~w(uuid uniqueidentifier binary_id),
    "timestamp" =>
      ~w(timestamp timestamptz datetime datetime2 datetimeoffset smalldatetime utc_datetime utc_datetime_usec naive_datetime naive_datetime_usec),
    "date" => ~w(date),
    "time" => ~w(time timetz time_usec),
    "boolean" => ~w(boolean bool bit),
    "json" => ~w(json jsonb map),
    "binary" => ~w(bytea blob tinyblob mediumblob longblob binary varbinary image)
  }

  @family_of for {family, types} <- @families, type <- types, into: %{}, do: {type, family}

  @doc """
  The family of a column's type: the types whose columns a foreign key
  joins. Sizes, precisions and modifiers do not count (`varchar(255)`,
  `numeric(12,2)`, `int unsigned`, `timestamp with time zone`), nor case.

      iex> Hakushi.Kits.Schema.family("int4")
      "integer"
      iex> Hakushi.Kits.Schema.family("character varying(255)")
      "text"
      iex> Hakushi.Kits.Schema.family("TIMESTAMP WITH TIME ZONE")
      "timestamp"

  The families are `integer`, `decimal`, `float`, `text`, `uuid`,
  `timestamp`, `date`, `time`, `boolean`, `json` and `binary`. A type of
  none of them is a family of its own (its name, in lower case, with
  underscores for spaces), so it joins only its own type. Add or change
  families with `config :hakushi, Hakushi.Kits.Schema, families: %{"geometry" =>
  "geometry", "ltree" => "text"}`.
  """
  @spec family(String.t() | nil) :: String.t() | nil
  def family(nil), do: nil

  def family(type) do
    type = type |> to_string() |> String.downcase() |> String.trim()
    families = Application.get_env(:hakushi, __MODULE__, [])[:families] || %{}

    case families[type] do
      nil ->
        # MySQL's booleans are tinyint(1); an array is a family of its own.
        base =
          if type == "tinyint(1)",
            do: "boolean",
            else: type |> String.replace(~r/\([^)]*\)/, "") |> plain()

        families[base] || @family_of[base] || String.replace(base, " ", "_")

      family ->
        family
    end
  end

  # A type without its modifiers: unsigned, zerofill, time zones, varying.
  defp plain(type) do
    type
    |> String.replace(
      ~r/\b(unsigned|signed|zerofill|with(out)? time zone|with local time zone)\b/,
      ""
    )
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

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
        <.handle
          id={handle_id(c)}
          side={:left}
          type={family(get(c, "type"))}
          accepts={[family(get(c, "type"))]}
        />
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
        <.handle
          id={handle_id(c)}
          side={:right}
          type={family(get(c, "type"))}
          accepts={[family(get(c, "type"))]}
        />
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

  @impl true
  def to_markdown(graph) do
    case Enum.filter(Graph.nodes(graph), &(&1.type == "schema-table")) do
      [] -> nil
      tables -> Mermaid.fence(name(), er_diagram(graph, tables))
    end
  end

  defp er_diagram(graph, tables) do
    ids = entity_names(tables)
    columns = Map.new(tables, &{&1.id, columns(&1.data)})

    edges =
      Enum.filter(
        Graph.edges(graph),
        &(Map.has_key?(ids, &1.source) and Map.has_key?(ids, &1.target))
      )

    entities =
      Enum.map(tables, fn table ->
        rows =
          Enum.map(columns[table.id], fn c ->
            key = %{"pk" => " PK", "fk" => " FK"}[get(c, "key")] || ""
            "    #{word(get(c, "type"))} #{word(get(c, "name"))}#{key}"
          end)

        Enum.join(["  #{ids[table.id]} {" | rows] ++ ["  }"], "\n")
      end)

    relations =
      Enum.map(edges, fn edge ->
        column = Enum.find(columns[edge.source], &(handle_id(&1) == edge.source_handle))
        label = if column, do: get(column, "name"), else: "refers to"
        "  #{ids[edge.source]} }o--|| #{ids[edge.target]} : #{Mermaid.label(label)}"
      end)

    extra =
      Map.new(tables, &{&1.id, %{"name" => get(&1.data, "name"), "columns" => columns[&1.id]}})

    Enum.join(
      ["erDiagram" | entities] ++
        relations ++ [Mermaid.places(tables, ids, extra), Mermaid.edge_places(edges, ids)],
      "\n"
    )
  end

  # Entity names: the tables' names, made unique.
  defp entity_names(tables) do
    {names, _seen} =
      Enum.map_reduce(tables, MapSet.new(), fn table, seen ->
        base = word(get(table.data, "name") || table.id)

        name =
          Stream.iterate(1, &(&1 + 1))
          |> Stream.map(&if(&1 == 1, do: base, else: "#{base}_#{&1}"))
          |> Enum.find(&(not MapSet.member?(seen, &1)))

        {{table.id, name}, MapSet.put(seen, name)}
      end)

    Map.new(names)
  end

  # A word Mermaid takes as a name or a type.
  defp word(text) do
    case text |> to_string() |> String.replace(~r/[^\w-]+/u, "_") |> String.trim("_") do
      "" -> "_"
      word -> word
    end
  end

  @impl true
  def from_markdown(text) do
    case Mermaid.lines(text) do
      ["erDiagram" | lines] -> {:ok, read_er(text, lines)}
      _other -> :error
    end
  end

  defp read_er(text, lines) do
    {entities, relations, _open} = Enum.reduce(lines, {[], [], nil}, &read_er_line/2)
    places = Mermaid.read_places(text)
    names = Enum.uniq(Enum.reverse(entities) |> Enum.map(&elem(&1, 0)))

    tables =
      Enum.map(names, fn name ->
        place = places[name] || %{}

        parsed =
          entities
          |> Enum.filter(&(elem(&1, 0) == name))
          |> Enum.flat_map(&elem(&1, 1))
          |> Enum.reverse()

        %{
          m: name,
          type: "schema-table",
          data: %{"name" => place["name"] || name, "columns" => place["columns"] || parsed}
        }
      end)

    edges = Mermaid.read_edges(text) || keys(Enum.reverse(relations), tables)
    Mermaid.graph(tables, edges, places)
  end

  @attribute ~r/^(\S+)\s+(\S+)((?:\s+(?:PK|FK|UK)\s*,?)*)\s*(?:"[^"]*")?$/
  @relation ~r/^([\w-]+)\s+\S+?(?:--|\.\.)\S+\s+([\w-]+)\s*:\s*(.+)$/
  @open ~r/^([\w-]+)\s*\{$/

  defp read_er_line("}", {entities, relations, _open}), do: {entities, relations, nil}

  defp read_er_line(line, {entities, relations, nil}) do
    cond do
      match = Regex.run(@open, line) ->
        [_all, name] = match
        {[{name, []} | entities], relations, name}

      match = Regex.run(@relation, line) ->
        [_all, from, to, label] = match
        mentioned = [{to, []}, {from, []}]
        {mentioned ++ entities, [{from, to, Mermaid.unlabel(label)} | relations], nil}

      true ->
        {entities, relations, nil}
    end
  end

  defp read_er_line(line, {[{name, columns} | entities], relations, name}) do
    case Regex.run(@attribute, line) do
      [_all, type, column, keys] ->
        key =
          cond do
            keys =~ "PK" -> "pk"
            keys =~ "FK" -> "fk"
            true -> nil
          end

        {[{name, [column(column, type, key) | columns]} | entities], relations, name}

      nil ->
        {[{name, columns} | entities], relations, name}
    end
  end

  # A relationship a person wrote: from the column it names (or the
  # table's first) to the primary key of the other table (or its first).
  defp keys(relations, tables) do
    columns = Map.new(tables, &{&1.m, &1.data["columns"]})

    Enum.map(relations, fn {from, to, label} ->
      source = Enum.find(columns[from], &(get(&1, "name") == label)) || List.first(columns[from])
      target = Enum.find(columns[to], &(get(&1, "key") == "pk")) || List.first(columns[to])

      %{from: from, to: to, path: "smooth"}
      |> then(&if(source, do: Map.put(&1, :source_handle, handle_id(source)), else: &1))
      |> then(&if(target, do: Map.put(&1, :target_handle, handle_id(target)), else: &1))
    end)
  end

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
