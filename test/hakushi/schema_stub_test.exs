defmodule Hakushi.SchemaStubTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hakushi.{Graph, Kit}
  alias Hakushi.Kits.Schema

  defp graph do
    Graph.new(
      nodes: [
        %{
          id: "orders",
          type: "schema-table",
          x: 0,
          y: 0,
          data: %{
            "name" => "orders",
            "columns" => [
              %{"name" => "id", "type" => "bigint", "key" => "pk"},
              %{"name" => "invoice_id", "type" => "uuid", "key" => "fk"}
            ]
          }
        },
        %{
          id: "billing.invoices",
          type: "schema-table",
          x: 400,
          y: 0,
          data: %{
            "name" => "invoices",
            "schema" => "billing",
            "external" => true,
            "columns" => [%{"name" => "id", "type" => "uuid", "key" => "pk"}]
          }
        }
      ],
      edges: [
        %{
          source: "orders",
          source_handle: "invoice_id",
          target: "billing.invoices",
          target_handle: "id"
        }
      ]
    )
  end

  test "a stub is faint, qualified, and has no fields even on a canvas people edit" do
    html =
      render_component(&Hakushi.Components.canvas/1, id: "db", graph: graph(), kits: [Schema])

    doc = LazyHTML.from_fragment(html)

    stub = LazyHTML.query(doc, ~s([data-id="billing.invoices"] .hakushi-kit-table))
    assert LazyHTML.attribute(stub, "data-hakushi-faint") == [""]
    assert LazyHTML.text(LazyHTML.query(stub, ".hakushi-kit-table-schema")) == "billing."
    assert LazyHTML.query(stub, "input") |> Enum.count() == 0
    assert LazyHTML.query(stub, ".hakushi-kit-add") |> Enum.count() == 0

    table = LazyHTML.query(doc, ~s([data-id="orders"] .hakushi-kit-table))
    assert LazyHTML.attribute(table, "data-hakushi-faint") == []
    assert LazyHTML.query(table, "input") |> Enum.count() > 0
  end

  test "nobody edits a stub" do
    data = Kit.stringify(Graph.node(graph(), "billing.invoices").data)
    assert :error = Schema.edit("name", %{"value" => "bills"}, data)
    assert :error = Schema.edit("add", %{}, data)
    assert :error = Schema.edit("key", %{"column" => "0"}, data)
  end

  test "Markdown names a stub by its schema, and reads it back a stub" do
    markdown = Kit.to_markdown([Schema], graph())
    assert markdown =~ "billing_invoices {"
    assert markdown =~ "orders }o--|| billing_invoices"

    {:ok, read, Schema} = Kit.from_markdown([Schema], markdown)
    stub = Enum.find(Graph.nodes(read), &(&1.data["name"] == "invoices"))
    assert stub.data["external"] == true
    assert stub.data["schema"] == "billing"

    refute Map.has_key?(
             Enum.find(Graph.nodes(read), &(&1.data["name"] == "orders")).data,
             "external"
           )
  end
end
