defmodule Hakushi.DragOutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hakushi.Graph
  alias Hakushi.Kits.Schema

  # A table of the canvas's schema, and a stub of another's.
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
      ]
    )
  end

  defp outs(attrs) do
    html =
      render_component(
        &Hakushi.Components.canvas/1,
        [id: "db", graph: graph(), kits: [Schema]] ++ attrs
      )

    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([data-hakushi-out][draggable="true"]))
    |> Enum.map(
      &{LazyHTML.attribute(&1, "class") |> hd(),
       LazyHTML.attribute(&1, "data-hakushi-out") |> hd()}
    )
  end

  test "without drag_out, nothing of the Schema kit drags out" do
    assert outs(readonly: :arrange) == []
    assert outs([]) == []
  end

  test "a read-only schema's tables drag out by their icons, a stub's qualified, and columns by their names" do
    assert outs(readonly: :arrange, drag_out: true) == [
             {"hakushi-kit-table-grip", "orders"},
             {"hakushi-kit-column-name", "id"},
             {"hakushi-kit-column-name", "invoice_id"},
             {"hakushi-kit-table-grip", "billing.invoices"},
             {"hakushi-kit-column-name", "id"}
           ]
  end

  test "on a canvas people edit, a table drags out by its icon, and its fields stay fields" do
    assert outs(drag_out: true) == [
             {"hakushi-kit-table-grip", "orders"},
             {"hakushi-kit-table-grip", "billing.invoices"},
             {"hakushi-kit-column-name", "id"}
           ]
  end
end
