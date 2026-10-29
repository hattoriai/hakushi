defmodule Hakushi.GraphTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Hakushi.{Change, Edge, Graph, Node}

  doctest Hakushi.Graph

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

  describe "paths" do
    # start -> check -> (yes) pay -> receipt
    #                -> (no)  remind
    # alone
    defp flow do
      Graph.new(
        nodes: Enum.map(~w(start check pay receipt remind alone), &%{id: &1}),
        edges: [
          %{id: "e1", source: "start", target: "check"},
          %{id: "yes", source: "check", target: "pay"},
          %{id: "no", source: "check", target: "remind"},
          %{id: "e3", source: "pay", target: "receipt"}
        ]
      )
    end

    test "successors and predecessors, near and far" do
      graph = flow()
      assert Graph.successors(graph, "check") == ["pay", "remind"]
      assert Graph.predecessors(graph, "pay") == ["check"]
      assert Graph.successors(graph, "alone") == []
      assert Graph.downstream(graph, "start") == ~w(check pay remind receipt)
      assert Graph.upstream(graph, "receipt") == ~w(pay check start)
      assert Graph.upstream(graph, "start") == []
    end

    test "roots and leaves" do
      assert Graph.roots(flow()) == ~w(start alone)
      assert Graph.leaves(flow()) == ~w(receipt remind alone)
    end

    test "a topological order, and the cycle that has none" do
      assert {:ok, ~w(start check pay receipt remind alone)} = Graph.topological_sort(flow())
      assert Graph.cycle(flow()) == nil

      looped =
        Graph.new(
          nodes: Enum.map(~w(a b c d), &%{id: &1}),
          edges: [
            %{source: "a", target: "b"},
            %{source: "b", target: "c"},
            %{source: "c", target: "b"},
            %{source: "c", target: "d"}
          ]
        )

      assert {:error, {:cycle, cycle}} = Graph.topological_sort(looped)
      assert Enum.sort(cycle) == ["b", "c"]

      itself = Graph.new(nodes: [%{id: "a"}], edges: [%{source: "a", target: "a"}])
      assert Graph.cycle(itself) == ["a"]
    end

    test "the shortest way, and its edges" do
      graph = flow()
      assert Graph.path(graph, "start", "receipt") == ~w(start check pay receipt)
      assert Graph.edges_along(graph, ~w(start check pay receipt)) == ~w(e1 yes e3)
      assert Graph.path(graph, "receipt", "start") == nil
      assert Graph.path(graph, "remind", "pay", directed: false) == ~w(remind check pay)
      assert Graph.edges_along(graph, ~w(remind check pay)) == ["yes"]
      assert Graph.edges_along(graph, ~w(remind check pay), directed: false) == ~w(no yes)
      assert Graph.path(graph, "start", "alone") == nil
      assert Graph.path(graph, "start", "start") == ["start"]
      assert Graph.path(graph, "start", "nowhere") == nil
    end

    test "the parts the edges join" do
      assert Graph.components(flow()) == [~w(start check pay receipt remind), ["alone"]]
      assert Graph.components(Graph.new()) == []
    end
  end

  # A graph of n nodes and some edges between them, forward only (no
  # cycle) or any way.
  defp random_graph(forward) do
    gen all(
          n <- integer(1..12),
          pairs <- list_of(tuple({integer(0..(n - 1)), integer(0..(n - 1))}), max_length: 30)
        ) do
      ids = Enum.map(0..(n - 1), &"n#{&1}")

      edges =
        for {a, b} <- Enum.uniq(pairs), a != b, not forward or a < b do
          %{source: "n#{a}", target: "n#{b}"}
        end

      # Drawn in another order than the edges go.
      Graph.new(nodes: ids |> Enum.reverse() |> Enum.map(&%{id: &1}), edges: edges)
    end
  end

  property "a graph without a cycle has an order with every edge forward" do
    check all(graph <- random_graph(true)) do
      assert {:ok, order} = Graph.topological_sort(graph)
      assert Enum.sort(order) == Enum.sort(graph.node_order)
      at = order |> Enum.with_index() |> Map.new()
      for edge <- Graph.edges(graph), do: assert(at[edge.source] < at[edge.target])
      assert Graph.cycle(graph) == nil
    end
  end

  property "a cycle found is one, and an order exists exactly when none is" do
    check all(graph <- random_graph(false)) do
      case Graph.cycle(graph) do
        nil ->
          assert {:ok, _order} = Graph.topological_sort(graph)

        cycle ->
          assert {:error, {:cycle, _}} = Graph.topological_sort(graph)
          ring = Enum.zip(cycle, tl(cycle) ++ [hd(cycle)])
          for {a, b} <- ring, do: assert(b in Graph.successors(graph, a))
      end
    end
  end

  property "a way found goes along edges, and is there when downstream says so" do
    check all(
            graph <- random_graph(false),
            from <- member_of(graph.node_order),
            to <- member_of(graph.node_order)
          ) do
      way = Graph.path(graph, from, to)
      assert way != nil == (from == to or to in Graph.downstream(graph, from))

      if way do
        assert hd(way) == from and List.last(way) == to
        assert length(Graph.edges_along(graph, way)) == length(way) - 1
        assert length(Enum.uniq(way)) == length(way)
      end
    end
  end

  property "the parts the edges join are each node once" do
    check all(graph <- random_graph(false)) do
      parts = Graph.components(graph)
      assert Enum.sort(List.flatten(parts)) == Enum.sort(graph.node_order)

      for edge <- Graph.edges(graph),
          do:
            assert(
              Enum.find(parts, &(edge.source in &1)) == Enum.find(parts, &(edge.target in &1))
            )
    end
  end
end
