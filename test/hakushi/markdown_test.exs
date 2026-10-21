defmodule Hakushi.MarkdownTest do
  use ExUnit.Case, async: true

  alias Hakushi.{Graph, Kit, Mermaid}
  alias Hakushi.Kits.{Flow, Notes, Schema}

  defp col(id, name, type, key \\ nil),
    do: %{"id" => id, "name" => name, "type" => type, "key" => key}

  defp schema do
    Graph.new(
      nodes: [
        %{
          id: "customers",
          type: "schema-table",
          x: 0,
          y: 30,
          data: %{
            "name" => "customers",
            "columns" => [col("c1", "id", "uuid", "pk"), col("c2", "email", "text")]
          }
        },
        %{
          id: "invoices",
          type: "schema-table",
          x: 320,
          y: 0,
          data: %{
            "name" => "invoices",
            "columns" => [col("i1", "id", "uuid", "pk"), col("i2", "customer_id", "uuid", "fk")]
          }
        }
      ],
      edges: [
        %{
          source: "invoices",
          source_handle: "i2",
          target: "customers",
          target_handle: "c1",
          path: :smooth
        }
      ]
    )
  end

  defp flow do
    Graph.new(
      nodes: [
        %{
          id: "paid",
          type: "flow-trigger",
          x: 0,
          y: 70,
          data: %{"title" => "Invoice \"paid\"", "detail" => "Stripe #webhook"}
        },
        %{
          id: "large",
          type: "flow-condition",
          x: 300,
          y: 70,
          data: %{"title" => "Over €1,000?", "detail" => ""}
        },
        %{
          id: "review",
          type: "flow-step",
          x: 620,
          y: 0,
          data: %{"title" => "Review", "detail" => ""}
        },
        %{
          id: "receipt",
          type: "flow-step",
          x: 620,
          y: 150,
          data: %{"title" => "Receipt", "detail" => ""}
        }
      ],
      edges: [
        %{source: "paid", target: "large"},
        %{source: "large", source_handle: "yes", target: "review", animated: true},
        %{source: "large", source_handle: "no", target: "receipt"}
      ]
    )
  end

  defp notes do
    Graph.new(
      nodes: [
        %{
          id: "q1",
          type: "note",
          x: 0,
          y: 0,
          width: 200,
          height: 140,
          data: %{"text" => "Refunds?\nA table of their own.", "color" => "yellow"}
        },
        %{
          id: "q2",
          type: "note",
          x: 240,
          y: 20,
          width: 220,
          height: 150,
          data: %{"text" => "Taxes per line", "color" => "mint"}
        }
      ],
      edges: [%{source: "q1", target: "q2", path: :straight}]
    )
  end

  # What a canvas is, without the order of its maps.
  defp shape(graph) do
    {Enum.map(Graph.nodes(graph), &Map.take(&1, [:id, :type, :x, :y, :width, :height, :data])),
     Enum.map(
       Graph.edges(graph),
       &Map.take(&1, [
         :id,
         :source,
         :source_handle,
         :target,
         :target_handle,
         :label,
         :path,
         :animated
       ])
     )}
  end

  for {kit, graph} <- [{Schema, :schema}, {Flow, :flow}, {Notes, :notes}] do
    test "#{inspect(kit)}: a canvas comes back from its Markdown as it was" do
      graph = unquote(graph)()
      markdown = unquote(kit).to_markdown(graph)
      assert markdown =~ ~r/\A```mermaid\n%% hakushi kit=#{unquote(kit).name()}\n/
      assert {:ok, back} = unquote(kit).from_markdown(markdown)
      assert shape(back) == shape(graph)
      # Through the dispatcher too.
      assert {:ok, ^back, unquote(kit)} = Kit.from_markdown([Schema, Flow, Notes], markdown)
    end
  end

  test "the Markdown is the diagram people read" do
    assert Schema.to_markdown(schema()) =~ """
           erDiagram
             customers {
               uuid id PK
               text email
             }
             invoices {
               uuid id PK
               uuid customer_id FK
             }
             invoices }o--|| customers : "customer_id"
           """

    flow = Flow.to_markdown(flow())
    assert flow =~ ~s(n1(["Invoice #quot;paid#quot;<br>Stripe #35;webhook"]\))
    assert flow =~ ~s(n2{"Over €1,000?"})
    assert flow =~ "n2 -->|Yes| n3"
    assert flow =~ "n2 -->|No| n4"

    assert Notes.to_markdown(notes()) =~ ~s(n1["Refunds?<br>A table of their own."]:::yellow)
  end

  test "an ER diagram a person wrote: tables, columns, keys, and a foreign key by its column" do
    {:ok, graph} =
      Schema.from_markdown("""
      ```mermaid
      erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER {
          int id PK
          int customer_id FK "who"
        }
        CUSTOMER {
          int id PK
          string name
        }
        ORDER }o--|| CUSTOMER : customer_id
      ```
      """)

    tables = Map.new(Graph.nodes(graph), &{&1.id, &1})
    assert Map.keys(tables) |> Enum.sort() == ["CUSTOMER", "ORDER"]

    assert Enum.map(tables["ORDER"].data["columns"], &{&1["name"], &1["type"], &1["key"]}) == [
             {"id", "int", "pk"},
             {"customer_id", "int", "fk"}
           ]

    [places, fk] = Graph.edges(graph)
    # "places" names no column: the first column, to the other's key.
    assert places.source == "CUSTOMER" and places.target == "ORDER"
    assert fk.source == "ORDER" and fk.target == "CUSTOMER"
    customer_id = Enum.find(tables["ORDER"].data["columns"], &(&1["name"] == "customer_id"))
    assert fk.source_handle == customer_id["id"]
    # Laid out, each table in a place of its own.
    assert {tables["ORDER"].x, tables["ORDER"].y} != {tables["CUSTOMER"].x, tables["CUSTOMER"].y}
  end

  test "a flowchart a person wrote: shapes, chains, labels, and a condition's ways" do
    {:ok, graph} =
      Flow.from_markdown("""
      flowchart TD
        start([Paid]) --> check{Large?}
        check -- yes --> review[Review] --> done(Done)
        check --> send[Send]
      """)

    types = Map.new(Graph.nodes(graph), &{&1.id, &1.type})

    assert types == %{
             "start" => "flow-trigger",
             "check" => "flow-condition",
             "review" => "flow-step",
             "done" => "flow-step",
             "send" => "flow-step"
           }

    ways = for e <- Graph.edges(graph), e.source == "check", do: {e.target, e.source_handle}
    xs = Map.new(Graph.nodes(graph), &{&1.id, &1.x})
    assert xs["start"] < xs["check"] and xs["check"] < xs["review"] and xs["review"] < xs["done"]
    assert ways == [{"review", "yes"}, {"send", "no"}]
    assert Enum.find(Graph.nodes(graph), &(&1.id == "review")).data["title"] == "Review"
  end

  test "each kit reads its own; the marker picks the kit" do
    assert :error = Schema.from_markdown("flowchart LR\n a --> b")
    assert :error = Flow.from_markdown("erDiagram\n A ||--o{ B : x")
    # A flowchart with no marker and no note colours is a flow.
    assert {:ok, _graph, Flow} = Kit.from_markdown([Notes, Flow], "flowchart LR\n a --> b")
    assert :error = Kit.from_markdown([Schema], "not a diagram")
  end

  test "a canvas of several kits: a diagram for each; none for none" do
    graph = Graph.new(nodes: Graph.nodes(schema()) ++ Graph.nodes(notes()))
    markdown = Kit.to_markdown([Schema, Flow, Notes], graph)
    assert [_schema, _notes] = Regex.scan(~r/```mermaid/, markdown)
    assert Kit.to_markdown([Flow], schema()) == nil
  end

  test "labels survive Mermaid's characters" do
    for text <- ["a \"quoted\" #tag", "two\nlines", "plain"] do
      assert text |> Mermaid.label() |> Mermaid.unlabel() == text
    end
  end
end
