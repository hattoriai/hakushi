defmodule HakushiTest.KitsLive do
  @moduledoc "A LiveView with a canvas of the built-in kits, for the kit tests."
  use Phoenix.LiveView

  import Hakushi.Components

  alias Hakushi.Graph
  alias Hakushi.Kits.{Flow, Notes, Schema}

  @kits [Schema, Flow, Notes]

  def graph do
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
              %{"id" => "c1", "name" => "id", "type" => "uuid", "key" => "pk"},
              %{"id" => "c2", "name" => "customer_id", "type" => "uuid", "key" => "fk"}
            ]
          }
        },
        %{id: "paid", type: "flow-trigger", x: 0, y: 300, data: %{title: "Invoice paid"}},
        %{id: "check", type: "flow-condition", x: 300, y: 300, data: %{"title" => "Over 1000?"}},
        %{id: "todo", type: "note", x: 600, y: 0, data: %{"text" => "Refunds", "color" => "sky"}}
      ]
    )
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, graph: graph(), readonly: params["readonly"] == "true", kits: @kits)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.canvas_embed title="Model" for="board" kits={@kits} readonly={@readonly} on_full="full">
      <.canvas id="board" graph={@graph} kits={@kits} readonly={@readonly} wheel={:scroll} refit />
    </.canvas_embed>
    """
  end

  @impl true
  def handle_event("full", _params, socket), do: {:noreply, socket}
end
