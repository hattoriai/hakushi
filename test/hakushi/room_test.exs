defmodule Hakushi.RoomTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  @endpoint HakushiTest.Endpoint

  defp open(topic, user) do
    {:ok, view, _html} = live(build_conn(), "/?live=#{topic}&user=#{user}")
    view
  end

  defp topic, do: "t#{System.unique_integer([:positive])}"

  test "people on one topic share the changes, in one room" do
    topic = topic()
    ada = open(topic, "ada")
    grace = open(topic, "grace")

    assert :ok = move(ada, "schema", "note", {11, 22})
    assert %{x: 11, y: 22} = Enum.find(nodes(grace, "schema"), &(&1.id == "note"))

    assert :ok = connect(grace, "schema", "note", "orders")
    assert Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))

    assert %Hakushi.Graph{} = graph = Hakushi.Room.graph("canvas:" <> topic)
    assert Hakushi.Graph.node(graph, "note").x == 11

    # The others' changes are not a person's to undo.
    assert :ok = undo(grace, "schema")
    assert {:error, "Nothing to undo."} = undo(grace, "schema")
    refute Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))
    assert %{x: 11} = Enum.find(nodes(grace, "schema"), &(&1.id == "note"))
  end

  test "a late joiner gets the room's graph, and everyone sees who is here" do
    topic = topic()
    ada = open(topic, "ada")
    :ok = move(ada, "schema", "users", {500, 500})

    grace = open(topic, "grace")
    assert %{x: 500} = Enum.find(nodes(grace, "schema"), &(&1.id == "users"))
    assert people(grace, "schema") == ["ada"]
    assert people(ada, "schema") == ["grace"]
  end

  test "the app's changes through the room, and the room stops when everyone leaves" do
    topic = topic()
    ada = open(topic, "ada")
    room = Hakushi.Room.whereis("canvas:" <> topic)
    assert is_pid(room)

    assert :ok = Hakushi.Room.change("canvas:" <> topic, Hakushi.Change.move([{"note", 3, 4}]))
    assert %{x: 3, y: 4} = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))

    assert {:error, :locked} =
             Hakushi.Room.change("canvas:" <> topic, Hakushi.Change.move([{"pinned", 0, 0}]))

    ref = Process.monitor(room)
    GenServer.stop(ada.pid)
    assert_receive {:DOWN, ^ref, :process, ^room, :normal}, 1000

    assert Hakushi.Room.change("canvas:" <> topic, Hakushi.Change.move([{"note", 3, 4}])) ==
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
end
