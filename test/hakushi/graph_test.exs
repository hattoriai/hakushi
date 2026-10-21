defmodule Hakushi.GraphTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Hakushi.{Change, Edge, Graph, Node}

  defp graph do
    Graph.new(
      nodes: [
        %{id: "a", x: 0, y: 0},
        %{id: "b", x: 200, y: 0, width: 100, height: 50},
        [id: "c", x: 0, y: 200, data: %{"name" => "C"}],
        %{"id" => "locked", "x" => 400, "y" => 400, "locked" => true}
      ],
      edges: [
        %{source: "a", target: "b"},
        %{id: "bc", source: "b", source_handle: "out", target: "c", label: "next"}
      ]
    )
  end

  describe "new/1" do
    test "keeps the order of the nodes and edges" do
      graph = graph()
      assert Enum.map(Graph.nodes(graph), & &1.id) == ~w(a b c locked)
      assert Enum.map(Graph.edges(graph), & &1.id) == ["a:->b:", "bc"]
      assert %Node{data: %{"name" => "C"}} = Graph.node(graph, "c")
      assert %Node{locked: true, x: 400} = Graph.node(graph, "locked")
    end

    test "refuses two nodes with one id, and edges to nowhere" do
      assert_raise ArgumentError, ~r/same id/, fn ->
        Graph.new(nodes: [%{id: "a"}, %{id: "a"}])
      end

      assert_raise ArgumentError, ~r/does not have/, fn ->
        Graph.new(edges: [%{source: "a", target: "b"}])
      end

      assert_raise ArgumentError, ~r/must be a number/, fn ->
        Graph.new(nodes: [%{id: "a", x: "1"}])
      end

      assert_raise ArgumentError, ~r/path/, fn ->
        Edge.new(source: "a", target: "b", path: "wiggly")
      end
    end
  end

  test "bounds/1" do
    assert Graph.bounds(Graph.new()) == nil
    assert Graph.bounds(graph()) == {0, 0, 400, 400}
  end

  describe "apply/2" do
    test "moves and resizes, and gives back the old places" do
      change = Change.move([{"a", 10, 20}, %{id: "b", x: 5, y: 5, width: 300, height: 90}])
      assert {:ok, graph, ^change, inverse} = Graph.apply(graph(), change)
      assert %Node{x: 10, y: 20, width: nil} = Graph.node(graph, "a")
      assert %Node{x: 5, y: 5, width: 300, height: 90} = Graph.node(graph, "b")

      assert inverse.nodes == [
               %{id: "a", x: 0, y: 0},
               %{id: "b", x: 200, y: 0, width: 100, height: 50}
             ]

      assert {:ok, back, _change, _inverse} = Graph.apply(graph, inverse)
      assert back == graph()
    end

    test "refuses a missing or locked node, and changes nothing" do
      assert Graph.apply(graph(), Change.move([{"a", 1, 1}, {"nope", 0, 0}])) ==
               {:error, :missing, "nope"}

      assert Graph.apply(graph(), Change.move([{"locked", 1, 1}])) == {:error, :locked, "locked"}
      assert Graph.apply(graph(), Change.delete(nodes: ["locked"])) == {:error, :locked, "locked"}
    end

    test "a delete takes the edges of its nodes, and its inverse brings them back" do
      assert {:ok, graph, change, inverse} = Graph.apply(graph(), Change.delete(nodes: ["b"]))
      assert change.edges == ["a:->b:", "bc"]
      assert Graph.edges(graph) == []
      assert Enum.map(Graph.nodes(graph), & &1.id) == ~w(a c locked)

      assert %Change{op: :add, nodes: [%Node{id: "b"}], edges: [%Edge{}, %Edge{id: "bc"}]} =
               inverse

      assert {:ok, back, _change, _inverse} = Graph.apply(graph, inverse)
      assert Graph.edges(back) == Graph.edges(graph())
      assert Enum.map(Graph.nodes(back), & &1.id) == ~w(a c locked b)
    end

    test "adds and connects" do
      change = Change.add([%{id: "d", x: 1, y: 2}], [%{source: "d", target: "a"}])
      assert {:ok, graph, _change, inverse} = Graph.apply(graph(), change)
      assert %Node{id: "d"} = Graph.node(graph, "d")
      assert inverse == %Change{op: :delete, nodes: ["d"], edges: ["d:->a:"]}

      assert Graph.apply(graph, change) == {:error, :exists, "d"}

      assert Graph.apply(graph, Change.connect(%{source: "x", target: "a"})) ==
               {:error, :dangling, "x"}
    end

    test "updates data and labels, with an inverse" do
      change =
        Change.update(
          nodes: [%{id: "c", data: %{"name" => "Z"}}],
          edges: [%{id: "bc", label: nil}]
        )

      assert {:ok, graph, _change, inverse} = Graph.apply(graph(), change)
      assert Graph.node(graph, "c").data == %{"name" => "Z"}
      assert Graph.edge(graph, "bc").label == nil
      assert {:ok, back, _change, _inverse} = Graph.apply(graph, inverse)
      assert back == graph()
    end
  end

  test "diff/2" do
    {:ok, changed, _change, _inverse} = Graph.apply(graph(), Change.move([{"a", 9, 9}]))
    {:ok, changed, _change, _inverse} = Graph.apply(changed, Change.delete(edges: ["bc"]))

    assert %{nodes: [%Node{id: "a", x: 9}], edges: [], deleted_nodes: [], deleted_edges: ["bc"]} =
             Graph.diff(graph(), changed)
  end

  test "dump/1 and load/1 round trip through JSON" do
    graph = graph()
    json = graph |> Graph.dump() |> JSON.encode!() |> JSON.decode!()
    assert Graph.load(json) == graph
  end

  property "a change and its inverse give back the graph" do
    check all(
            moves <-
              list_of({member_of(~w(a b c)), integer(-1000..1000), integer(-1000..1000)},
                min_length: 1
              ),
            deleted <- list_of(member_of(~w(a b c)), max_length: 3)
          ) do
      start = graph()

      {:ok, moved, _change, undo_move} =
        Graph.apply(start, Change.move(Enum.uniq_by(moves, &elem(&1, 0))))

      {:ok, deleted, _change, undo_delete} =
        Graph.apply(moved, Change.delete(nodes: Enum.uniq(deleted)))

      {:ok, restored, _change, _inverse} = Graph.apply(deleted, undo_delete)

      assert Map.new(Graph.nodes(restored), &{&1.id, &1}) ==
               Map.new(Graph.nodes(moved), &{&1.id, &1})

      assert Enum.sort(Graph.edges(restored)) == Enum.sort(Graph.edges(moved))

      {:ok, back, _change, _inverse} = Graph.apply(moved, undo_move)
      assert back == start
    end
  end
end
