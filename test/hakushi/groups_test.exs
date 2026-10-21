defmodule Hakushi.GroupsTest do
  use ExUnit.Case, async: true

  alias Hakushi.{Change, Graph}

  # A frame with a note and an inner frame, which has a card.
  defp graph do
    Graph.new(
      nodes: [
        %{id: "frame", x: 0, y: 0, width: 600, height: 400},
        %{id: "note", x: 20, y: 40, parent: "frame"},
        %{id: "inner", x: 200, y: 40, width: 300, height: 200, parent: "frame"},
        %{id: "card", x: 220, y: 80, parent: "inner"},
        %{id: "outside", x: 900, y: 0}
      ],
      edges: [
        %{id: "e1", source: "note", target: "card"},
        %{id: "e2", source: "card", target: "outside"}
      ]
    )
  end

  test "children and descendants" do
    assert Graph.children(graph(), "frame") == ["note", "inner"]
    assert Graph.descendants(graph(), "frame") == ["note", "inner", "card"]
    assert Graph.descendants(graph(), "card") == []
  end

  test "a parent the graph does not have, or a node in itself, is refused" do
    assert_raise ArgumentError, ~r/does not have/, fn ->
      Graph.new(nodes: [%{id: "a", parent: "nope"}])
    end

    assert_raise ArgumentError, ~r/another node/, fn ->
      Graph.new(nodes: [%{id: "a", parent: "a"}])
    end
  end

  test "a move of a group moves what is in it, and the undo takes it all back" do
    assert {:ok, moved, change, inverse} = Graph.apply(graph(), Change.move([{"frame", 100, 50}]))
    assert %{x: 120, y: 90} = Graph.node(moved, "note")
    assert %{x: 320, y: 130} = Graph.node(moved, "card")
    assert %{x: 900} = Graph.node(moved, "outside")
    assert change.nodes |> Enum.map(& &1.id) |> Enum.sort() == ~w(card frame inner note)

    assert {:ok, back, _change, _inverse} = Graph.apply(moved, inverse)
    assert back == graph()
  end

  test "a node the change places itself is not moved again" do
    change = Change.move([{"frame", 100, 0}, {"note", 5, 5}])
    assert {:ok, moved, _change, _inverse} = Graph.apply(graph(), change)
    assert %{x: 5, y: 5} = Graph.node(moved, "note")
    assert %{x: 300} = Graph.node(moved, "inner")
  end

  test "a resize moves the corner, not the nodes inside" do
    change = Change.move([%{id: "frame", x: -100, y: 0, width: 700, height: 400}])
    assert {:ok, moved, _change, _inverse} = Graph.apply(graph(), change)
    assert %{x: 20} = Graph.node(moved, "note")
  end

  test "a move puts a node in a group, or takes it out, and undoes" do
    change = Change.move([%{id: "outside", x: 30, y: 300, parent: "frame"}])
    assert {:ok, moved, _change, inverse} = Graph.apply(graph(), change)
    assert %{parent: "frame"} = Graph.node(moved, "outside")
    assert {:ok, back, _change, _inverse} = Graph.apply(moved, inverse)
    assert %{parent: nil, x: 900} = Graph.node(back, "outside")

    assert {:ok, out, _change, _inverse} =
             Graph.apply(graph(), Change.move([%{id: "card", x: 1000, y: 0, parent: nil}]))

    assert Graph.descendants(out, "frame") == ["note", "inner"]
  end

  test "a group does not go inside itself, nor into a group it holds" do
    assert Graph.apply(graph(), Change.move([%{id: "frame", x: 0, y: 0, parent: "card"}])) ==
             {:error, :nested, "card"}

    assert Graph.apply(graph(), Change.move([%{id: "frame", x: 0, y: 0, parent: "frame"}])) ==
             {:error, :nested, "frame"}

    assert Graph.apply(graph(), Change.move([%{id: "note", x: 0, y: 0, parent: "nope"}])) ==
             {:error, :dangling, "nope"}
  end

  test "a delete of a group takes what is in it, and its edges, and the undo brings them back" do
    assert {:ok, deleted, change, inverse} = Graph.apply(graph(), Change.delete(nodes: ["inner"]))
    assert change.nodes == ["inner", "card"]
    assert change.edges |> Enum.sort() == ["e1", "e2"]
    assert Enum.map(Graph.nodes(deleted), & &1.id) == ~w(frame note outside)

    assert {:ok, back, _change, _inverse} = Graph.apply(deleted, inverse)
    assert %{parent: "inner"} = Graph.node(back, "card")
    assert length(Graph.edges(back)) == 2
  end

  test "a group's nodes come back with it when added in any order" do
    change = Change.add([%{id: "child", parent: "box"}, %{id: "box"}])
    assert {:ok, added, _change, _inverse} = Graph.apply(Graph.new(), change)
    assert Graph.children(added, "box") == ["child"]
  end

  test "dump and load keep the parents" do
    assert graph() |> Graph.dump() |> JSON.encode!() |> JSON.decode!() |> Graph.load() == graph()
  end

  test "reconnect moves an end of an edge, and undoes" do
    change = Change.reconnect([%{id: "e2", source: "note", source_handle: "out"}])
    assert {:ok, moved, _change, inverse} = Graph.apply(graph(), change)
    assert %{source: "note", source_handle: "out", target: "outside"} = Graph.edge(moved, "e2")
    assert {:ok, back, _change, _inverse} = Graph.apply(moved, inverse)
    assert back == graph()

    assert Graph.apply(graph(), Change.reconnect([%{id: "nope", source: "note"}])) ==
             {:error, :missing, "nope"}

    assert Graph.apply(graph(), Change.reconnect([%{id: "e2", target: "nope"}])) ==
             {:error, :dangling, "nope"}
  end
end
