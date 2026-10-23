defmodule Hakushi.PaperTest do
  # The paper of a canvas: its own, or the one people chose with its picker
  # (`papers`), which is the graph's: a change, which undoes, and which a
  # shared canvas shares.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Hakushi.{Change, Graph, Paper}

  @endpoint HakushiTest.Endpoint

  describe "a paper" do
    test "is a pattern's name and a size of squares" do
      assert Paper.new(background: :lines, grid: 24) == %{background: "lines", grid: 24}
      assert Paper.new(%{"background" => "iso"}) == %{background: "iso", grid: nil}
      assert Paper.new(nil) == nil
      assert_raise ArgumentError, ~r/background/, fn -> Paper.new(background: "Iso Metric") end
      assert_raise ArgumentError, ~r/background/, fn -> Paper.new(background: "url(x)") end
      assert_raise ArgumentError, ~r/grid/, fn -> Paper.new(background: :dots, grid: 2) end
      assert_raise ArgumentError, ~r/grid/, fn -> Paper.new(background: :dots, grid: 20.5) end
    end

    test "offered: Hakushi's, and the app's own with their labels" do
      assert Paper.offered(nil) == []
      assert Paper.offered(false) == []
      assert Enum.map(Paper.offered(true), & &1.name) == ["dots", "lines", "cross", "none"]

      assert Paper.offered([:dots, {"grid-fine", "Fine"}, %{name: "iso", label: "Isometric"}]) ==
               [
                 %{name: "dots", label: nil},
                 %{name: "grid-fine", label: "Fine"},
                 %{name: "iso", label: "Isometric"}
               ]

      assert_raise ArgumentError, fn -> Paper.offered(["no good"]) end
      assert_raise ArgumentError, fn -> Paper.offered(:dots) end
    end
  end

  describe "the graph's paper" do
    test "a change, whose inverse is the paper before" do
      graph = Graph.new(nodes: [%{id: "a"}])
      assert graph.paper == nil

      assert {:ok, graph, %Change{paper: %{background: "lines", grid: 40}}, inverse} =
               Graph.apply(graph, Change.paper(background: :lines, grid: 40))

      assert graph.paper == %{background: "lines", grid: 40}
      assert inverse == %Change{op: :paper, paper: nil}
      assert {:ok, %Graph{paper: nil}, _, _} = Graph.apply(graph, inverse)
    end

    test "stays when nodes go, and is in the diff" do
      graph = Graph.new(nodes: [%{id: "a"}, %{id: "b"}], paper: [background: :cross, grid: 20])
      assert {:ok, after_delete, _, _} = Graph.apply(graph, Change.delete(nodes: ["a"]))
      assert after_delete.paper == %{background: "cross", grid: 20}

      assert %{paper: false} = Graph.diff(graph, after_delete)
      assert %{paper: true} = Graph.diff(graph, %{graph | paper: nil})
    end

    test "dumps and loads with the graph" do
      graph = Graph.new(nodes: [%{id: "a"}], paper: [background: "iso", grid: 10])
      dumped = Graph.dump(graph)
      assert dumped["paper"] == %{"background" => "iso", "grid" => 10}
      assert Graph.load(dumped).paper == graph.paper
      refute Map.has_key?(Graph.dump(Graph.new()), "paper")
    end
  end

  describe "the picker of a canvas" do
    defp open(query) do
      {:ok, view, html} = live(build_conn(), "/" <> query)
      {view, html}
    end

    defp config(html) do
      [config] = Regex.run(~r/data-config="([^"]+)"/, html, capture: :all_but_first)
      config |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> JSON.decode!()
    end

    test "offers the canvas's papers, in its words, and the sizes of squares" do
      {view, html} = open("")

      assert %{
               "papers" => [
                 %{"name" => "dots", "label" => "Dots"},
                 %{"name" => "lines", "label" => "Graph paper"},
                 %{"name" => "iso", "label" => "Isometric"}
               ],
               "paperGrids" => [10, 20, 40]
             } = config(html)

      # Until someone chooses, the canvas's own paper.
      assert paper(view, "schema") == %{background: "dots", grid: 20}
      assert html =~ ~s(data-background="dots")
    end

    test "a paper chosen is a change: the canvas shows it, on_change sees it, ⌘Z takes it back" do
      session =
        Plug.Test.init_test_session(build_conn(), %{
          "test" => Base.encode64(:erlang.term_to_binary(self()))
        })

      {:ok, view, _html} = live(session, "/")

      assert :ok = paper(view, "schema", "iso", 40)
      assert paper(view, "schema") == %{background: "iso", grid: 40}
      assert render(view) =~ ~s(data-background="iso")

      assert_received {:on_change, %Change{op: :paper, paper: %{background: "iso", grid: 40}},
                       _context}

      assert :ok = undo(view, "schema")
      assert paper(view, "schema") == %{background: "dots", grid: 20}
      assert :ok = redo(view, "schema")
      assert paper(view, "schema") == %{background: "iso", grid: 40}
    end

    test "refuses a paper it does not offer, a size of its own, and a viewer" do
      {view, _html} = open("")
      assert {:error, _} = paper(view, "schema", "cross", 20)
      assert {:error, _} = paper(view, "schema", "lines", 30)
      assert paper(view, "schema") == %{background: "dots", grid: 20}

      {viewer, html} = open("?readonly=true")
      assert %{"papers" => []} = config(html)
      assert {:error, "This canvas is read-only."} = paper(viewer, "schema", "lines", 20)
    end

    test "on a shared canvas, everyone sees the paper chosen" do
      topic = "paper#{System.unique_integer([:positive])}"
      {ada, _html} = open("?live=#{topic}&user=ada")
      {grace, _html} = open("?live=#{topic}&user=grace")

      assert :ok = paper(ada, "schema", "lines", 10)
      assert paper(grace, "schema") == %{background: "lines", grid: 10}

      # The app's own change of the paper, as any change.
      assert :ok =
               Hakushi.Issho.change(HakushiTest.Issho, "canvas:" <> topic, Change.paper(nil))

      assert paper(ada, "schema") == %{background: "dots", grid: 20}
    end
  end
end
