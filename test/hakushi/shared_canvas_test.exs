defmodule Hakushi.SharedCanvasTest do
  # Shared canvases (`live`): every canvas of a topic is a session of one
  # Issho room, whose document is the graph.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Issho.Tool.Context
  alias Phoenix.Socket.Broadcast

  @endpoint HakushiTest.Endpoint

  defp open(topic, user, test \\ nil) do
    conn =
      if test,
        do:
          Plug.Test.init_test_session(build_conn(), %{
            "test" => Base.encode64(:erlang.term_to_binary(test))
          }),
        else: build_conn()

    {:ok, view, _html} = live(conn, "/?live=#{topic}&user=#{user}")
    view
  end

  defp topic, do: "t#{System.unique_integer([:positive])}"

  # Waits until a LiveView has handled what is in its mailbox, and the
  # updates it sent its components meanwhile.
  defp settle(view) do
    :sys.get_state(view.pid)
    :sys.get_state(view.pid)
  end

  test "people on one topic share the changes, in one room" do
    topic = topic()
    ada = open(topic, "ada")
    grace = open(topic, "grace")

    assert :ok = move(ada, "schema", "note", {11, 22})
    settle(grace)
    assert %{x: 11, y: 22} = Enum.find(nodes(grace, "schema"), &(&1.id == "note"))

    assert :ok = connect(grace, "schema", "note", "orders")
    settle(ada)
    assert Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))

    assert %Hakushi.Graph{} = graph = Hakushi.Issho.graph(HakushiTest.Issho, "canvas:" <> topic)
    assert Hakushi.Graph.node(graph, "note").x == 11

    # The others' changes are not a person's to undo.
    assert :ok = undo(grace, "schema")
    assert {:error, "Nothing to undo."} = undo(grace, "schema")
    settle(ada)
    refute Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))
    assert %{x: 11} = Enum.find(nodes(grace, "schema"), &(&1.id == "note"))
  end

  test "a late joiner gets the room's graph, and everyone sees who is here" do
    topic = topic()
    Phoenix.PubSub.subscribe(HakushiTest.PubSub, Issho.Presence.topic("canvas:" <> topic))
    ada = open(topic, "ada")
    :ok = move(ada, "schema", "users", {500, 500})

    grace = open(topic, "grace")
    assert %{x: 500} = Enum.find(nodes(grace, "schema"), &(&1.id == "users"))
    assert people(grace, "schema") == ["ada"]

    assert_receive %Broadcast{event: "presence_diff", payload: %{joins: %{"grace" => _}}}
    settle(ada)
    assert people(ada, "schema") == ["grace"]
  end

  test "the app's changes go through the room; the room stops when everyone leaves" do
    topic = "canvas:" <> topic()
    ada = open(String.replace_prefix(topic, "canvas:", ""), "ada")
    room = Issho.Documents.whereis(HakushiTest.Issho, topic)
    assert is_pid(room)

    assert :ok =
             Hakushi.Issho.change(HakushiTest.Issho, topic, Hakushi.Change.move([{"note", 3, 4}]))

    settle(ada)
    assert %{x: 3, y: 4} = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))

    assert {:error, :locked} =
             Hakushi.Issho.change(
               HakushiTest.Issho,
               topic,
               Hakushi.Change.move([{"pinned", 0, 0}])
             )

    ref = Process.monitor(room)
    GenServer.stop(ada.pid)
    assert_receive {:DOWN, ^ref, :process, ^room, :normal}, 1000

    assert Hakushi.Issho.change(HakushiTest.Issho, topic, Hakushi.Change.move([{"note", 3, 4}])) ==
             {:error, :not_running}
  end

  test "peers' cursors go to the others" do
    topic = topic()
    ada = open(topic, "ada")
    grace = open(topic, "grace")

    ada
    |> element("#schema-hook")
    |> render_hook("hakushi:peer", %{"cursor" => [1, 2], "selected" => ["note"]})

    assert_push_event(grace, "hakushi:peer", %{
      "person" => "ada",
      "cursor" => [1, 2],
      "selected" => ["note"]
    })
  end

  test "on_change runs once for each change, whoever makes it, and a refusal goes back" do
    topic = topic()
    # Ada opens first: her canvas gives the room its on_change.
    ada = open(topic, "ada", self())
    grace = open(topic, "grace")

    assert :ok = move(grace, "schema", "note", {40, 50})
    assert_receive {:on_change, %Hakushi.Change{op: :move, by: %{id: "grace"}}, %{result: result}}
    assert Hakushi.Graph.node(result, "note").x == 40
    refute_received {:on_change, _, _}

    assert {:error, "The users table stays."} = remove(grace, "schema", nodes: ["users"])
    settle(ada)
    assert Enum.any?(nodes(ada, "schema"), &(&1.id == "users"))
  end

  test "the hook asks about each change of a transaction with the graph the ones before made" do
    test = self()
    on_change = fn change, context -> send(test, {:asked, change.op, context.graph}) && :ok end
    graph = Hakushi.Graph.new(nodes: [%{id: "a", x: 0, y: 0}])
    spec = Hakushi.Issho.spec(graph, Hakushi.Rules.new([]), on_change, "flow")

    changes = [
      Hakushi.Change.add([%{id: "b", x: 10, y: 0}]),
      Hakushi.Change.connect(%{id: "ab", source: "a", target: "b"})
    ]

    assert :ok = spec.on_transaction.(changes, %{before: graph})
    assert_received {:asked, :add, before_add}
    assert_received {:asked, :connect, before_connect}
    refute Hakushi.Graph.node(before_add, "b")
    assert Hakushi.Graph.node(before_connect, "b")
  end

  test "an agent of the app moves, connects and renames through the canvas's tools" do
    topic = topic()
    ada = open(topic, "ada")
    tools = Hakushi.Issho.tools()

    agent =
      Context.new(HakushiTest.Issho, %{
        id: "assistant",
        name: "Assistant",
        kind: :agent
      })

    canvas = "canvas:" <> topic

    assert {:ok, %{"nodes" => nodes}} =
             Issho.Tools.call(tools, "read_canvas", %{"canvas" => canvas}, agent)

    assert Enum.any?(nodes, &(&1.id == "note"))

    assert {:ok, _} =
             Issho.Tools.call(
               tools,
               "move_node",
               %{"canvas" => canvas, "node" => "note", "x" => 40, "y" => 80},
               agent
             )

    settle(ada)
    assert %{x: 40, y: 80} = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))

    # The canvas's rules (no cycles here) answer an agent as anyone.
    assert {:error, _reason} =
             Issho.Tools.call(
               tools,
               "connect_nodes",
               %{"canvas" => canvas, "source" => "users", "target" => "orders"},
               agent
             )

    assert {:ok, _} =
             Issho.Tools.call(
               tools,
               "update_node",
               %{"canvas" => canvas, "node" => "note", "data" => %{"label" => "Renamed"}},
               agent
             )

    settle(ada)
    assert %{label: "Renamed"} = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))
  end

  test "an agent works on a board no one has open, which the app's policy says" do
    tools = Hakushi.Issho.tools()
    agent = Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})
    board = "board:" <> Base.encode64(:erlang.term_to_binary(self()))

    assert {:ok, %{"nodes" => [%{id: "first"}]}} =
             Issho.Tools.call(tools, "read_canvas", %{"canvas" => board}, agent)

    assert {:ok, %{"id" => id}} =
             Issho.Tools.call(
               tools,
               "add_node",
               %{"canvas" => board, "x" => 100, "y" => 40, "data" => %{"label" => "Second"}},
               agent
             )

    # The app saves it, through the canvas's on_change.
    assert_receive {:saved, graph}
    assert Hakushi.Graph.node(graph, id)
  end
end
