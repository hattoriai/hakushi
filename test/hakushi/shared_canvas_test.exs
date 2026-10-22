defmodule Hakushi.SharedCanvasTest do
  # Shared canvases (`issho`): every canvas of a document is a session of one
  # Issho room, whose document is the graph.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Issho.Tool.Context
  alias Phoenix.Socket.Broadcast

  @endpoint HakushiTest.Endpoint

  defp open(topic, user, test \\ nil, query \\ "") do
    conn =
      if test,
        do:
          Plug.Test.init_test_session(build_conn(), %{
            "test" => Base.encode64(:erlang.term_to_binary(test))
          }),
        else: build_conn()

    {:ok, view, _html} = live(conn, "/?live=#{topic}&user=#{user}" <> query)
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

  test "a canvas's own keys are under its document; Issho's stay Issho's" do
    topic = topic()
    ada = open(topic, "ada")
    doc = "canvas:" <> topic
    {:ok, watcher} = Issho.join_as(HakushiTest.Issho, %{id: "watcher"}, doc)

    ada
    |> element("#schema-hook")
    |> render_hook("hakushi:peer", %{"cursor" => [1, 2], "selected" => ["note"]})

    assert_receive {Issho.Participant, ^watcher, "aware", %{"states" => states}}, 1_000
    [state] = for {_session, %{"key" => "ada", "state" => state}} <- states, do: state

    assert %{"blocks" => %{^doc => %{"cursor" => [1, 2], "selected" => ["note"]}}} = state
    refute Map.has_key?(state, "cursor")
    refute Map.has_key?(state, "selected")
  end

  test "the app changes a canvas as someone: on_change gets them as :by" do
    topic = topic()
    _ada = open(topic, "ada", self())
    doc = "canvas:" <> topic

    assert :ok =
             Hakushi.Issho.change(HakushiTest.Issho, doc, Hakushi.Change.move([{"note", 3, 4}]),
               author: %{id: "ops", name: "Ops"}
             )

    assert_receive {:on_change, %Hakushi.Change{by: nil}, %{by: %Issho.Identity{key: "ops"}}}

    assert :ok =
             Hakushi.Issho.change(HakushiTest.Issho, doc, [Hakushi.Change.move([{"note", 5, 6}])])

    assert_receive {:on_change, _change, %{by: %Issho.Identity{key: "server", kind: :service}}}
  end

  test "a canvas joins with issho, whose keys are checked; live and follow say what replaces them" do
    canvas = fn assigns ->
      render_component(
        &Hakushi.Components.canvas/1,
        [id: "c", graph: Hakushi.Graph.new()] ++ assigns
      )
    end

    assert_raise ArgumentError, ~r/issho=/, fn -> canvas.(live: {HakushiTest.Issho, "c:1"}) end
    assert_raise ArgumentError, ~r/follow: false/, fn -> canvas.(follow: false) end

    assert_raise ArgumentError, ~r/not \[:room\]/, fn ->
      canvas.(issho: [instance: HakushiTest.Issho, document: "c:1", room: "c:1"])
    end
  end

  test "a canvas with people: false leaves the room's people to the page" do
    topic = topic()
    _ada = open(topic, "ada")
    grace = open(topic, "grace", nil, "&people=false")
    settle(grace)
    refute has_element?(grace, "[data-hakushi-people]")

    ken = open(topic, "ken")
    settle(ken)
    assert has_element?(ken, "[data-hakushi-people]")
  end

  test "a place on a canvas is a point, a node or nodes" do
    alias Hakushi.Issho.Place

    for place <- [nil, %{"point" => [1, 2.5]}, %{"node" => "a"}, %{"nodes" => ["a", "b"]}],
        do: assert(:ok = Place.validate(place))

    for place <- [%{"point" => [1]}, %{"node" => 7}, %{"nodes" => [1]}, %{"x" => 1}, "a"],
        do: assert({:error, _} = Place.validate(place))

    assert Hakushi.Issho.place() == Place
  end

  test "a peer's viewport goes to the others, apart from Issho's view of the page" do
    topic = topic()
    ada = open(topic, "ada")
    grace = open(topic, "grace")

    ada
    |> element("#schema-hook")
    |> render_hook("hakushi:peer", %{"cursor" => [1, 2], "viewport" => [0, 0, 800, 600]})

    assert_push_event(
      grace,
      "hakushi:peer",
      %{"person" => "ada", "viewport" => [0, 0, 800, 600]} = peer
    )

    # A person's `view` is Issho's (the page they have open), in the same state.
    refute Map.has_key?(peer, "view")
  end

  test "a read-only canvas is a viewer of the room, whose cursor still goes" do
    topic = topic()
    ada = open(topic, "ada", nil, "&readonly=true")
    grace = open(topic, "grace")

    assert %{"ada" => %{metas: [%{"can" => "read"}]}} =
             Issho.Presence.list(Issho.Presence.topic("canvas:" <> topic))

    ada |> element("#schema-hook") |> render_hook("hakushi:peer", %{"cursor" => [3, 4]})
    assert_push_event(grace, "hakushi:peer", %{"person" => "ada", "cursor" => [3, 4]})
  end

  test "the app's user is the room's actor: its key, and Issho's colours" do
    topic = topic()
    ada = open(topic, "ada", nil, "&member=true")
    grace = open(topic, "grace")
    settle(ada)

    assert_push_event(grace, "hakushi:people", %{
      "people" => [%{"id" => "member:ada", "color" => color}]
    })

    assert color =~ ~r/^var\(--issho-person-\d, #[0-9a-f]{6}\)$/

    ada |> element("#schema-hook") |> render_hook("hakushi:peer", %{"cursor" => [1, 1]})
    assert_push_event(grace, "hakushi:peer", %{"person" => "member:ada"})
    # Not to the person's own canvas.
    settle(ada)
    refute_push_event(ada, "hakushi:peer", %{"person" => "member:ada"})
  end

  test "a page of the room with Issho's pointers says whether they draw a person here" do
    topic = topic()
    room = "canvas:" <> topic
    ada = open(topic, "ada")

    # Grace's page: Issho's pointers, her pointer on this canvas.
    Issho.Awareness.put(HakushiTest.Issho, room, "grace", %{
      "pointer" => %{"doc" => room, "at" => %{"point" => [1, 2]}},
      "view" => %{"page" => true}
    })

    assert_push_event(ada, "hakushi:peer", %{"person" => "grace", "paged" => true})
    refute_push_event(ada, "hakushi:peer", %{"person" => "grace", "cursor" => _})
  end

  test "a canvas that goes while its LiveView stays lets its room go" do
    topic = topic()
    Phoenix.PubSub.subscribe(HakushiTest.PubSub, Issho.Presence.topic("canvas:" <> topic))
    _ada = open(topic, "ada")
    grace = open(topic, "grace")
    assert_receive %Broadcast{payload: %{joins: %{"grace" => _}}}

    # The canvas's hook, destroyed.
    render_hook(grace, "issho:release", %{"room" => "canvas:" <> topic, "component" => "schema"})

    assert_receive %Broadcast{payload: %{leaves: %{"grace" => _}}}
    assert Process.alive?(grace.pid)
  end

  test "on_change runs once for each change, whoever makes it, and a refusal goes back" do
    topic = topic()
    # Ada opens first: her canvas gives the room its on_change.
    ada = open(topic, "ada", self())
    grace = open(topic, "grace")

    assert :ok = move(grace, "schema", "note", {40, 50})

    assert_receive {:on_change, %Hakushi.Change{op: :move, by: %{id: "grace"}},
                    %{result: result, by: by}}

    assert Hakushi.Graph.node(result, "note").x == 40
    # Who made it, as Issho says them: the same in every component's callback.
    assert %Issho.Identity{key: "grace", name: "Grace", kind: :human} = by
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

  test "an agent waits while the browsers draw its way, unless it does not travel" do
    topic = topic()
    ada = open(topic, "ada")
    tools = Hakushi.Issho.tools()
    agent = Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})
    move = %{"canvas" => "canvas:" <> topic, "node" => "note", "x" => 40, "y" => 80}

    # To the node (Issho's flight, 450ms), then the drag (a step within the
    # canvas, 300ms): only where it goes is sent, each a wait.
    {travelled, {:ok, _}} = :timer.tc(fn -> Issho.Tools.call(tools, "move_node", move, agent) end)
    assert travelled >= 700_000

    Application.put_env(:hakushi, Hakushi.Issho, travel: false)
    on_exit(fn -> Application.delete_env(:hakushi, Hakushi.Issho) end)

    {at_once, {:ok, _}} =
      :timer.tc(fn -> Issho.Tools.call(tools, "move_node", %{move | "x" => 60}, agent) end)

    assert at_once < 400_000
    settle(ada)
    assert %{x: 60, y: 80} = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))
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

  test "an agent reads what a person of the room selected on the canvas" do
    topic = topic()
    ada = open(topic, "ada")

    render_hook(element(ada, "#schema-hook"), "hakushi:peer", %{
      "cursor" => [10, 20],
      "selected" => ["note", "gone"]
    })

    settle(ada)

    agent = Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})

    assert {:ok, %{"of" => %{"selected" => ["note"], "pointer" => [10, 20]}}} =
             Issho.Tools.call(
               Hakushi.Issho.tools(),
               "read_canvas",
               %{"canvas" => "canvas:" <> topic, "of" => "ada"},
               agent
             )
  end
end
