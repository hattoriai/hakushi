defmodule HakushiTest.Member do
  @moduledoc false
  # A user of the app's own, whose key in every room is the app's.
  defstruct [:id, :name]

  defimpl Issho.Actor do
    def key(member), do: "member:#{member.id}"
    def display(member), do: %{name: member.name}
  end
end

defmodule HakushiTest.CanvasLive do
  @moduledoc "A LiveView with a canvas, for the canvas tests."
  use Phoenix.LiveView

  import Hakushi.Components

  alias Hakushi.Graph

  on_mount(Hakushi.Live)

  def graph do
    Graph.new(
      nodes: [
        %{
          id: "users",
          type: "table",
          x: 0,
          y: 0,
          data: %{name: "users", columns: ["id", "name"]}
        },
        %{
          id: "orders",
          type: "table",
          x: 320,
          y: 40,
          data: %{name: "orders", columns: ["id", "user_id"]}
        },
        %{id: "note", x: 0, y: 300, data: %{label: "A note"}},
        %{id: "pinned", x: 600, y: 0, locked: true}
      ],
      edges: [
        %{
          id: "fk",
          source: "orders",
          source_handle: "user_id",
          target: "users",
          target_handle: "id"
        }
      ]
    )
  end

  @impl true
  def mount(params, session, socket) do
    test = self_test(session)

    {:ok,
     assign(socket,
       graph: graph(),
       test: test,
       issho:
         if(params["live"],
           do: [
             instance: HakushiTest.Issho,
             document: "canvas:" <> params["live"],
             people: params["people"] != "false"
           ]
         ),
       user: user(params),
       readonly: params["readonly"] == "true"
     )}
  end

  # ?member=true: a user of the app's own struct, whose Issho.Actor says its key.
  defp user(%{"user" => id, "member" => "true"}),
    do: %HakushiTest.Member{id: id, name: String.capitalize(id)}

  defp user(%{"user" => id}), do: %{id: id, name: String.capitalize(id)}
  defp user(_params), do: nil

  defp self_test(session),
    do: session["test"] && :erlang.binary_to_term(Base.decode64!(session["test"]))

  @impl true
  def handle_event("replace", _params, socket) do
    {:ok, graph, _change, _inverse} =
      Graph.apply(
        socket.assigns.graph,
        Hakushi.Change.update(nodes: [%{id: "note", data: %{label: "Changed"}}])
      )

    {:noreply, assign(socket, :graph, graph)}
  end

  def handle_event("app_change", _params, socket) do
    Hakushi.Live.change("schema", Hakushi.Change.move([{"note", 7, 7}]))
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.canvas
      id="schema"
      graph={@graph}
      on_change={&on_change(&1, &2, @test)}
      new_node={&new_node/2}
      issho={@issho}
      user={@user}
      readonly={@readonly}
      rules={[cycles: false]}
      papers={[:dots, :lines, %{name: "iso", label: "Isometric"}]}
      label="Schema"
    >
      <:node type="table" :let={node}>
        <div class="table">
          <strong>{node.data.name}</strong>
          <div :for={column <- node.data.columns} class="relative" data-column={column}>
            <.handle id={column} kind={:target} side={:left} />
            {column}
            <.handle id={column} kind={:source} side={:right} />
          </div>
        </div>
      </:node>
      <:empty>Drop a table here.</:empty>
    </.canvas>
    <.canvas_item for="schema" item="table">New table</.canvas_item>
    """
  end

  defp on_change(change, context, test) do
    if test, do: send(test, {:on_change, change, context})

    case change do
      %{op: :delete, nodes: ["users"]} -> {:error, "The users table stays."}
      _other -> :ok
    end
  end

  defp new_node("table", {x, y}),
    do: %{type: "table", x: x, y: y, data: %{name: "new", columns: ["id"]}}

  defp new_node(nil, {x, y}), do: %{x: x, y: y, data: %{label: "Note"}}
  defp new_node(_item, _place), do: nil
end
