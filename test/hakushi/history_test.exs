defmodule Hakushi.HistoryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hakushi.{Change, Graph, History}

  defp graph do
    Graph.new(
      nodes: [
        %{id: "a", x: 0, y: 0, data: %{"title" => "A"}},
        %{id: "b", x: 200, y: 0},
        %{id: "group", x: 0, y: 200, width: 400, height: 200},
        %{id: "in", x: 20, y: 220, parent: "group"}
      ],
      edges: [%{id: "ab", source: "a", target: "b", label: "next"}]
    )
  end

  describe "Graph.compare/2" do
    test "what was added, removed, moved and changed, nodes and edges" do
      old = graph()

      {:ok, new, _, _} = Graph.apply(old, Change.move([{"a", 10, 0}]))

      {:ok, new, _, _} =
        Graph.apply(
          new,
          Change.update(
            nodes: [%{id: "b", data: %{"n" => 1}}],
            edges: [%{id: "ab", label: "then"}]
          )
        )

      {:ok, new, _, _} = Graph.apply(new, Change.delete(nodes: ["group"]))

      {:ok, new, _, _} =
        Graph.apply(
          new,
          Change.add([%{id: "c", x: 0, y: 0}], [%{id: "bc", source: "b", target: "c"}])
        )

      assert Graph.compare(old, new) == %{
               added: %{nodes: ["c"], edges: ["bc"]},
               removed: %{nodes: ["group", "in"], edges: []},
               moved: ["a"],
               changed: %{nodes: %{"b" => [:data]}, edges: %{"ab" => [:label]}},
               paper: false
             }

      assert Graph.compare(old, old).moved == []
    end
  end

  describe "Change.dump/1 and load/1" do
    test "every op goes and comes back" do
      changes = [
        Change.add([%{id: "n", x: 1, y: 2, data: %{"k" => "v"}, parent: "g"}], [
          %{id: "e", source: "n", target: "m", label: "x"}
        ]),
        Change.connect(%{id: "e2", source: "a", target: "b", source_handle: "out"}),
        Change.move([%{id: "a", x: 1, y: 2, width: 30, height: 40, parent: nil}]),
        Change.reconnect([%{id: "ab", source: "b", target_handle: "in"}]),
        Change.update(
          nodes: [%{id: "a", data: %{"t" => 1}, locked: true}],
          edges: [%{id: "ab", label: nil}]
        ),
        Change.delete(nodes: ["a"], edges: ["ab"]),
        Change.paper(background: :lines, grid: 24),
        %{Change.move([{"a", 0, 0}]) | by: %{id: "ada", name: "Ada", secret: "no"}}
      ]

      for change <- changes do
        json = change |> Change.dump() |> JSON.encode!() |> JSON.decode!()
        loaded = Change.load(json)

        expected =
          if change.by, do: %{change | by: Map.take(change.by, [:id, :name])}, else: change

        assert loaded == expected
      end
    end
  end

  describe "History" do
    defp history do
      h = History.new(graph())

      {:ok, h} =
        History.record(h, Change.move([{"a", 50, 50}]), by: "ada", at: ~U[2026-10-01 10:00:00Z])

      {:ok, h} =
        History.record(h, Change.delete(nodes: ["b"]), by: "kenji", at: ~U[2026-10-01 10:05:00Z])

      {:ok, h} = History.record(h, Change.add([%{id: "c", x: 0, y: 0}]), by: "ada")
      h
    end

    test "records each change as a version, and gives each version back" do
      h = history()
      assert History.version(h) == 3
      assert History.first(h) == 0

      assert [
               %{version: 1, op: :move, nodes: ["a"], by: "ada", at: ~U[2026-10-01 10:00:00Z]},
               %{version: 2, op: :delete, nodes: ["b"], edges: ["ab"], by: "kenji"},
               %{version: 3, op: :add, nodes: ["c"], at: %DateTime{}}
             ] = History.versions(h)

      assert History.at(h, 0) == graph()
      assert Graph.node(History.at(h, 1), "a").x == 50
      assert Graph.node(History.at(h, 1), "b")
      refute Graph.node(History.at(h, 2), "b")
      assert History.at(h, 3) == History.graph(h)
      assert %{added: %{nodes: ["c"]}, removed: %{nodes: ["b"]}} = History.compare(h, 1)
      assert %{change: %Change{op: :delete}} = History.entry(h, 2)
      assert_raise ArgumentError, fn -> History.at(h, 4) end
    end

    test "a change that does not apply is not recorded" do
      assert {:error, :missing, "nope"} =
               History.record(history(), Change.delete(nodes: ["nope"]))
    end

    test "a limit keeps the last changes, and the numbers of their versions" do
      h = History.new(graph(), limit: 2)
      {:ok, h} = History.record(h, Change.move([{"a", 1, 1}]))
      {:ok, h} = History.record(h, Change.move([{"a", 2, 2}]))
      {:ok, h} = History.record(h, Change.move([{"a", 3, 3}]))

      assert History.first(h) == 1
      assert Enum.map(History.versions(h), & &1.version) == [2, 3]
      assert Graph.node(History.at(h, 1), "a").x == 1
      assert_raise ArgumentError, fn -> History.at(h, 0) end
      assert_raise ArgumentError, fn -> History.new(graph(), limit: 0) end
    end

    test "goes to JSON and back" do
      h = history()
      json = h |> History.dump() |> JSON.encode!() |> JSON.decode!()
      loaded = History.load(json)

      assert History.graph(loaded) == Graph.load(Graph.dump(History.graph(h)))

      assert Enum.map(History.versions(loaded), &Map.take(&1, [:version, :op, :by])) ==
               Enum.map(History.versions(h), &Map.take(&1, [:version, :op, :by]))

      assert History.versions(loaded) |> hd() |> Map.get(:at) == ~U[2026-10-01 10:00:00Z]
    end
  end

  describe "a canvas that compares" do
    test "marks what was added, changed and moved, shows what was removed, and changes nothing" do
      h = history()
      {:ok, h} = History.record(h, Change.update(nodes: [%{id: "a", data: %{"title" => "A2"}}]))

      html =
        render_component(&Hakushi.Components.canvas/1,
          id: "then",
          graph: History.graph(h),
          compare: History.at(h, 0)
        )

      assert html =~ ~s(data-compare="true")
      assert html =~ "&quot;readonly&quot;:true"
      doc = LazyHTML.from_fragment(html)

      diff =
        for node <- LazyHTML.query(doc, ".hakushi-node"), into: %{} do
          {LazyHTML.attribute(node, "data-id") |> hd(),
           LazyHTML.attribute(node, "data-diff") |> List.first()}
        end

      assert diff == %{
               "a" => "changed",
               "b" => "removed",
               "c" => "added",
               "group" => nil,
               "in" => nil
             }

      assert html =~ ~r/data-id="ab"[^>]*data-diff="removed"/
    end

    test "is not shared" do
      assert_raise ArgumentError, ~r/compare/, fn ->
        render_component(&Hakushi.Components.canvas/1,
          id: "then",
          graph: graph(),
          compare: graph(),
          issho: [instance: HakushiTest.Issho, document: "x"]
        )
      end
    end

    test "overlay keeps the ghosts in their groups, or in none" do
      old = graph()
      {:ok, new, _, _} = Graph.apply(old, Change.delete(nodes: ["in"]))
      {shown, diff} = Hakushi.Canvas.overlay(old, new)
      assert %{parent: "group", locked: true} = Graph.node(shown, "in")
      assert diff.nodes == %{"in" => :removed}
    end
  end
end
