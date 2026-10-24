defmodule Hakushi.KitsTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Hakushi.Kits.{Flow, Notes, Schema}

  @endpoint HakushiTest.Endpoint

  # A kit whose lanes hold its cards.
  defmodule Lanes do
    use Hakushi.Kit

    def name, do: "lanes"
    def title(_messages), do: "Lanes"
    def icon, do: "workflow"
    def types, do: ["lane", "lane-card"]
    def elements(_messages), do: []
    def new_node(_item, {x, y}, _messages), do: %{type: "lane-card", x: x, y: y, data: %{}}
    def node(assigns), do: ~H"<div>{@node.id}</div>"
    def edit(_action, _params, _data), do: :error
    def resizable?(type), do: type == "lane"
    def group?(type), do: type == "lane"
  end

  doctest Hakushi.Kits.Schema

  defp open(query \\ "") do
    {:ok, view, html} = live(build_conn(), "/kits" <> query)
    {view, html}
  end

  defp field(view, node, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([data-id="#{node}"] #{selector}))
    |> Enum.map(fn el ->
      case LazyHTML.attribute(el, "value") do
        [value] -> value
        [] -> el |> LazyHTML.text() |> String.trim()
      end
    end)
  end

  describe "a canvas with kits" do
    test "draws the kits' nodes, with their handles" do
      {view, html} = open()

      assert [
               %{id: "orders", type: "schema-table"},
               %{id: "paid", type: "flow-trigger"},
               %{id: "check", type: "flow-condition"},
               %{id: "todo", type: "note"}
             ] = nodes(view, "board")

      assert field(view, "orders", ".hakushi-kit-table-name") == ["orders"]
      assert field(view, "orders", ".hakushi-kit-column-name") == ["id", "customer_id"]
      # A column's handles are its id, on each side, of its type.
      assert html =~ ~s(data-handle="c2")
      assert html =~ ~s(data-type="uuid")
      # Atom keys read as string keys.
      assert field(view, "paid", ".hakushi-kit-step-title") == ["Invoice paid"]
      # A condition has two ways out.
      assert html =~ ~s(data-handle="yes") and html =~ ~s(data-handle="no")
      # A note is resizable; a table is not.
      assert html =~ ~r/data-id="todo"[^>]*data-resizable="true"/
      refute html =~ ~r/data-id="orders"[^>]*data-resizable="true"/
    end

    test "edits a table: its name, a column, its type and key, and adds and removes columns" do
      {view, _html} = open()

      assert :ok = edit(view, "board", "orders", "name", %{"value" => "Customer Orders"})
      assert field(view, "orders", ".hakushi-kit-table-name") == ["customer_orders"]

      assert :ok = edit(view, "board", "orders", "add")

      assert field(view, "orders", ".hakushi-kit-column-name") == [
               "id",
               "customer_id",
               "column_3"
             ]

      assert :ok =
               edit(view, "board", "orders", "column", %{"column" => 2, "value" => "placed_at"})

      assert :ok = edit(view, "board", "orders", "type", %{"column" => 2, "value" => "timestamp"})
      assert :ok = edit(view, "board", "orders", "key", %{"column" => 0})

      html = render(view)

      assert field(view, "orders", ".hakushi-kit-column-name") == [
               "id",
               "customer_id",
               "placed_at"
             ]

      assert html =~ ~s(<option value="timestamp" selected)
      # pk -> fk
      assert html =~ ~r/data-key="fk"[^>]*phx-value-column="0"/

      assert :ok = edit(view, "board", "orders", "remove", %{"column" => 1})
      assert field(view, "orders", ".hakushi-kit-column-name") == ["id", "placed_at"]
    end

    test "an edit is a change of the person's own: undone with undo" do
      {view, _html} = open()

      assert :ok = edit(view, "board", "todo", "text", %{"value" => "Ask finance"})
      assert field(view, "todo", ".hakushi-kit-note-text") == ["Ask finance"]

      assert :ok = undo(view, "board")
      assert field(view, "todo", ".hakushi-kit-note-text") == ["Refunds"]
    end

    test "refuses what a kit refuses, and every edit of a read-only canvas" do
      {view, _html} = open()
      assert {:error, nil} = edit(view, "board", "orders", "name", %{"value" => "!!!"})

      assert {:error, nil} =
               edit(view, "board", "orders", "type", %{"column" => 0, "value" => "nope"})

      assert {:error, nil} =
               edit(view, "board", "orders", "column", %{"column" => 9, "value" => "x"})

      assert {:error, nil} = edit(view, "board", "nowhere", "name", %{"value" => "x"})

      {view, html} = open("?readonly=true")
      refute html =~ "hakushi-kit-field"
      refute html =~ "hakushi-kit-items"
      assert {:error, "This canvas is read-only."} = edit(view, "board", "todo", "color")
    end

    test "makes the kits' nodes for their items, and for a double click" do
      {view, _html} = open()

      assert {:ok, [table]} = drop(view, "board", "schema:table", {40, 400})
      assert {:ok, [step]} = drop(view, "board", "flow:step", {400, 400})
      assert {:ok, [note]} = drop(view, "board", "notes:note", {800, 400})
      # A double click makes the first kit's node.
      assert {:ok, [first]} = drop(view, "board", nil, {40, 800})

      types = Map.new(nodes(view, "board"), &{&1.id, &1.type})
      assert types[table] == "schema-table"
      assert types[step] == "flow-step"
      assert types[note] == "note"
      assert types[first] == "schema-table"

      assert {:error, nil} = drop(view, "board", "schema:nothing", {0, 0}) |> refused()
    end

    test "the embed frame has the kits' items and the full screen button" do
      {_view, html} = open()
      doc = LazyHTML.from_fragment(html)

      items =
        doc
        |> LazyHTML.query(".hakushi-embed-bar .hakushi-kit-item")
        |> Enum.map(&LazyHTML.attribute(&1, "data-hakushi-item"))

      assert items == [
               ["schema:table"],
               ["flow:trigger"],
               ["flow:step"],
               ["flow:condition"],
               ["notes:note"],
               ["shapes:rect"]
             ]

      assert html =~ ~s(aria-label="Full screen")
      assert html =~ "&quot;wheel&quot;:&quot;scroll&quot;"
      assert html =~ "&quot;refit&quot;:true"
    end
  end

  # A kit item it does not know makes the kit's default node; nil from
  # new_node is a refusal.
  defp refused({:ok, _ids}), do: {:error, nil}
  defp refused(other), do: other

  describe "the kits" do
    test "Schema keeps names SQL-like and cycles the key" do
      data = %{"name" => "t", "columns" => [%{"name" => "a", "type" => "text", "key" => nil}]}

      assert {:ok, %{"name" => "line_items"}} =
               Schema.edit("name", %{"value" => " Line Items "}, data)

      assert {:ok, %{"columns" => [%{"key" => "pk"}]}} =
               Schema.edit("key", %{"column" => "0"}, data)

      assert :error = Schema.edit("key", %{"column" => "x"}, data)

      assert {:ok, %{"columns" => [_, %{"name" => "column_2", "id" => "c" <> _}]}} =
               Schema.edit("add", %{}, data)
    end

    test "Schema joins columns of one family of types" do
      for {type, family} <- [
            {"integer", "integer"},
            {"BIGINT", "integer"},
            {"int8", "integer"},
            {"int unsigned", "integer"},
            {"bigserial", "integer"},
            {"numeric(12,2)", "decimal"},
            {"money", "decimal"},
            {"double precision", "float"},
            {"character varying(255)", "text"},
            {"varchar", "text"},
            {"citext", "text"},
            {"uuid", "uuid"},
            {"timestamp(6) with time zone", "timestamp"},
            {"timestamptz", "timestamp"},
            {"datetime", "timestamp"},
            {"time without time zone", "time"},
            {"date", "date"},
            {"tinyint(1)", "boolean"},
            {"tinyint", "integer"},
            {"jsonb", "json"},
            {"bytea", "binary"},
            {"integer[]", "integer[]"},
            {"user defined", "user_defined"},
            {nil, nil}
          ] do
        assert Schema.family(type) == family, "#{inspect(type)}: #{inspect(Schema.family(type))}"
      end

      refute Schema.family("text") == Schema.family("uuid")
    end

    test "a Schema table's handles are of its columns' families" do
      graph =
        Hakushi.Graph.new(
          nodes: [
            %{
              id: "t",
              type: "schema-table",
              x: 0,
              y: 0,
              data: %{
                "name" => "t",
                "columns" => [
                  %{"name" => "id", "type" => "int8", "key" => "pk"},
                  %{"name" => "slug", "type" => "character varying(64)", "key" => nil}
                ]
              }
            }
          ]
        )

      html =
        render_component(&Hakushi.Components.canvas/1,
          id: "families",
          graph: graph,
          kits: [Schema]
        )

      assert html =~
               ~s(data-handle="id" data-kind="both" data-side="left" data-type="integer" data-accepts="integer")

      assert html =~ ~s(data-type="text" data-accepts="text")
    end

    test "a canvas takes the paper, layout and rules its kits like, and its own over them" do
      prefs = Hakushi.Kit.canvas_prefs([Schema, Notes])
      assert prefs[:background] == :lines
      assert prefs[:snap] == true
      assert prefs[:rules] == [loops: false]

      assert Hakushi.Kit.canvas_prefs([Notes, Flow])[:background] == :cross
      assert Hakushi.Kit.canvas_prefs([Notes, Flow])[:rules] == [loops: false, cycles: false]
      assert Hakushi.Kit.canvas_prefs([]) == [rules: []]

      # The test canvas has [Schema, Flow, Notes]: Schema's graph paper.
      {_view, html} = open()
      assert html =~ ~s(data-background="lines")
      assert html =~ "&quot;cycles&quot;:false"
    end

    test "a kit's types are groups by group?/1, and an app's slot wins" do
      graph =
        Hakushi.Graph.new(
          nodes: [
            %{id: "doing", type: "lane", x: 0, y: 0, width: 400, height: 300, data: %{}},
            %{id: "undo", type: "lane-card", x: 20, y: 40, parent: "doing", data: %{}},
            %{id: "todo", type: "note", x: 600, y: 0, data: %{"text" => "Refunds"}}
          ]
        )

      html =
        render_component(&Hakushi.Components.canvas/1,
          id: "road",
          graph: graph,
          kits: [Lanes, Notes]
        )

      assert html =~ ~r/data-id="doing"[^>]*data-group="true"/
      refute html =~ ~r/data-id="undo"[^>]*data-group="true"/
      # A kit with no group?/1 has no groups.
      refute html =~ ~r/data-id="todo"[^>]*data-group="true"/
      assert Hakushi.Kit.group?(Lanes, "lane")
      refute Hakushi.Kit.group?(Notes, "note")

      html =
        render_component(&Hakushi.Components.canvas/1,
          id: "road",
          graph: graph,
          kits: [Lanes],
          node: [%{type: "lane", inner_block: fn _, _ -> "lane" end, __slot__: :node}]
        )

      assert html =~ ~s(data-id="doing")
      refute html =~ ~r/data-id="doing"[^>]*data-group="true"/
    end

    test "Flow and Notes" do
      assert %{type: "flow-condition", data: %{"title" => "Condition"}} =
               Flow.new_node("condition", {0, 0}, Hakushi.Messages.for_locale("en"))

      assert {:ok, %{"color" => "rose"}} = Notes.edit("color", %{}, %{"color" => "yellow"})
      assert {:ok, %{"color" => "yellow"}} = Notes.edit("color", %{}, %{"color" => "lilac"})
      assert Notes.resizable?("note")
    end
  end
end
