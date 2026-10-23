defmodule Hakushi.ShapesTest do
  # Shapes (Hakushi.Kits.Shapes): rectangles, ellipses, diamonds,
  # triangles, text and lines, drawn with the kit's tools, written in,
  # styled from the panel, turned; Markdown in and out; and an agent that
  # draws them.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Hakushi.{Graph, Kit}
  alias Hakushi.Kits.Shapes
  alias Issho.Tool.Context

  @endpoint HakushiTest.Endpoint

  describe "a shape's node" do
    test "is its box, its kind's style, and its text" do
      assert %{type: "shape", x: 10, y: 20, width: 200, height: 80, data: data} =
               Shapes.shape("rect", [10, 20, 200, 80], %{"text" => "Ship", "fill" => "green"})

      assert %{
               "kind" => "rect",
               "text" => "Ship",
               "fill" => "green",
               "stroke" => "blue",
               "radius" => 8
             } =
               data

      # A box drawn the other way, and a click: the kind's size.
      assert %{width: 200, height: 80} = Shapes.shape("ellipse", [10, 20, -200, -80], %{})
      assert %{width: 180, height: 40} = Shapes.shape("text", [0, 0, 0, 0], nil)

      # Text has no fill or stroke of its own.
      assert %{data: %{"fill" => "none", "stroke" => "none", "align" => "left"}} =
               Shapes.shape("text", [0, 0, 0, 0], %{})
    end

    test "takes the style it has, and leaves the rest" do
      %{data: data} =
        Shapes.shape("diamond", [0, 0, 100, 100], %{
          "fill" => "magenta",
          "width" => 4,
          "dash" => "yes",
          "size" => "l",
          "rotation" => -30,
          "onclick" => "x"
        })

      assert data["fill"] == "blue"
      assert data["width"] == 4
      assert data["dash"] == false
      assert data["size"] == "l"
      assert data["rotation"] == 330
      refute Map.has_key?(data, "onclick")
    end

    test "has the app's colours too" do
      refute "brand" in Shapes.colors()
      Application.put_env(:hakushi, Shapes, colors: ["brand"])
      on_exit(fn -> Application.delete_env(:hakushi, Shapes) end)
      assert "brand" in Shapes.colors()

      assert %{data: %{"fill" => "brand"}} =
               Shapes.shape("rect", [0, 0, 10, 10], %{"fill" => "brand"})
    end

    test "a line: its box around its ends, its ends relative to it" do
      assert {:ok, %{type: "shape-line", x: 88, y: 38, width: 124, height: 84, data: data}} =
               Shapes.line({200, 50}, {100, 110}, %{"arrow" => "both"})

      assert data["from"] == [112, 12]
      assert data["to"] == [12, 72]
      assert data["arrow"] == "both"
    end
  end

  describe "a canvas with shapes" do
    defp open do
      {:ok, view, html} = live(build_conn(), "/kits")
      {view, html}
    end

    defp node(view, id), do: Enum.find(nodes(view, "board"), &(&1.id == id))

    defp style(view, id) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([data-id="#{id}"] [data-hakushi-style]))
      |> LazyHTML.attribute("data-hakushi-style")
      |> hd()
      |> JSON.decode!()
    end

    test "has the kit's tools, its style panel, and a rectangle to drop" do
      {_view, html} = open()
      [config] = Regex.run(~r/data-config="([^"]+)"/, html, capture: :all_but_first)

      config =
        config |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> JSON.decode!()

      assert [
               %{"tool" => "rect", "mode" => "box", "key" => "r"},
               %{"tool" => "ellipse", "key" => "o"},
               %{"tool" => "diamond"},
               %{"tool" => "triangle"},
               %{"tool" => "text", "key" => "t"},
               %{"tool" => "line", "mode" => "line", "key" => "a"}
             ] = Enum.filter(config["tools"], &(&1["kit"] == "shapes"))

      assert [%{"kit" => "shapes", "types" => ["shape", "shape-line"], "groups" => groups}] =
               config["styles"]

      assert Enum.map(groups, & &1["key"]) == ~w(fill stroke width dash radius size align arrow)
      assert html =~ ~s(data-hakushi-item="shapes:rect")
    end

    test "draws a shape as a box, and a line, as nodes of the kit" do
      {view, _html} = open()

      assert {:ok, id} = draw_box(view, "board", "shapes:ellipse", [100, 500, 120, 80])
      assert %{type: "shape", label: "Ellipse", width: 120, height: 80} = node(view, id)
      html = render(view)
      assert html =~ ~r/data-id="#{id}"[^>]*data-resizable="true"/
      assert html =~ ~s(data-kind="ellipse")
      assert html =~ "<ellipse"
      # A handle on each side, for edges.
      handles =
        html |> LazyHTML.from_fragment() |> LazyHTML.query(~s([data-id="#{id}"] .hakushi-handle))

      assert Enum.count(handles) == 4

      assert {:ok, line} =
               view
               |> render_hook_draw("shapes:line", %{"points" => [[0, 600], [200, 700]]})

      assert %{type: "shape-line", label: "Line"} = node(view, line)
      assert {:error, nil} = draw_box(view, "board", "shapes:hexagon", [0, 0, 10, 10])
    end

    test "text in a shape, written in place: its name says it" do
      {view, _html} = open()
      {:ok, id} = draw_box(view, "board", "shapes:diamond", [100, 500, 120, 80])

      assert :ok = edit(view, "board", id, "text", %{"value" => "Paid?\n"})
      assert %{label: "Diamond: Paid?"} = node(view, id)
      assert render(view) =~ ~s(data-hakushi-text="Paid?")
    end

    test "a style for many shapes is one change, which ⌘Z takes back" do
      {view, _html} = open()
      {:ok, a} = draw_box(view, "board", "shapes:rect", [100, 500, 120, 80])
      {:ok, b} = draw_box(view, "board", "shapes:triangle", [300, 500, 120, 80])

      assert :ok =
               edit(view, "board", [a, b], "style", %{
                 "style" => %{"fill" => "red", "radius" => 0}
               })

      assert %{"fill" => "red", "radius" => 0} = style(view, a)
      # A triangle has no corners.
      assert style(view, b)["fill"] == "red"
      refute Map.has_key?(style(view, b), "radius")

      assert :ok = undo(view, "board")
      assert style(view, a)["fill"] == "blue"
      assert style(view, b)["fill"] == "blue"
    end

    test "turns, by degrees" do
      {view, _html} = open()
      {:ok, id} = draw_box(view, "board", "shapes:rect", [100, 500, 120, 80])
      assert :ok = edit(view, "board", id, "rotate", %{"value" => 405.4})
      assert render(view) =~ "--hakushi-rotation: 45deg"
      assert {:error, nil} = edit(view, "board", id, "rotate", %{"value" => "a lot"})
    end
  end

  # A line drawn with the kit's line tool.
  defp render_hook_draw(view, tool, params) do
    render(view)

    view
    |> element("#board-hook")
    |> render_hook("hakushi:draw", Map.put(params, "tool", tool))

    %{proxy: {ref, _topic, _pid}} = view

    receive do
      {^ref, {:reply, %{"drawn" => id}}} -> {:ok, id}
    after
      1_000 -> :error
    end
  end

  describe "Markdown" do
    test "a Mermaid flowchart of the shapes, and back as they were" do
      graph =
        Graph.new(
          nodes: [
            Map.put(
              Shapes.shape("ellipse", [0, 0, 150, 96], %{"text" => "Idea", "fill" => "yellow"}),
              :id,
              "idea"
            ),
            Map.put(
              Shapes.shape("rect", [200, 0, 160, 96], %{"text" => "Sketch", "radius" => 0}),
              :id,
              "sketch"
            ),
            Map.put(
              Shapes.shape("diamond", [400, 0, 140, 112], %{"text" => "Good?", "rotation" => 15}),
              :id,
              "good"
            ),
            Map.put(
              Shapes.shape("triangle", [600, 0, 140, 112], %{"text" => "Again"}),
              :id,
              "again"
            ),
            Map.put(Shapes.shape("text", [0, 200, 180, 40], %{"text" => "Notes"}), :id, "notes")
          ],
          edges: [
            %{source: "idea", target: "sketch"},
            %{source: "good", target: "again", label: "No"}
          ]
        )

      markdown = Kit.to_markdown([Shapes], graph)
      assert markdown =~ "%% hakushi kit=shapes"
      assert markdown =~ ~s{(("Idea"))}
      assert markdown =~ ~s{["Sketch"]}
      assert markdown =~ ~s({"Good?"})
      assert markdown =~ ~s{[/"Again"\\]}
      assert markdown =~ ~s{["Notes"]:::text}
      assert markdown =~ ~s{-->|"No"|}

      assert {:ok, back, Shapes} = Kit.from_markdown([Shapes], markdown)
      assert Graph.nodes(back) == Graph.nodes(graph)

      assert Enum.map(Graph.edges(back), &{&1.source, &1.target, &1.label}) ==
               [{"idea", "sketch", nil}, {"good", "again", "No"}]
    end

    test "a flowchart a person wrote" do
      text = """
      flowchart LR
        a((Start)) --> b(Round) --> c[Square] --> d{Choose} --> e[/Up\\]
      """

      assert {:ok, graph} = Shapes.from_markdown(text)

      assert Enum.map(Graph.nodes(graph), &{&1.data["kind"], &1.data["text"], &1.data["radius"]}) ==
               [
                 {"ellipse", "Start", 8},
                 {"rect", "Round", 8},
                 {"rect", "Square", 0},
                 {"diamond", "Choose", 8},
                 {"triangle", "Up", 8}
               ]

      assert Enum.all?(Graph.nodes(graph), &(&1.width && &1.height))
      assert length(Graph.edges(graph)) == 4
    end
  end

  describe "an agent that draws shapes" do
    defp shared(topic) do
      {:ok, view, _html} = live(build_conn(), "/?live=#{topic}&user=ada")
      view
    end

    defp agent,
      do: Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})

    setup do
      Application.put_env(:hakushi, Hakushi.Issho, travel: false)
      on_exit(fn -> Application.delete_env(:hakushi, Hakushi.Issho) end)
      topic = "shapes#{System.unique_integer([:positive])}"
      %{topic: topic, canvas: "canvas:" <> topic, tools: Hakushi.Issho.tools()}
    end

    test "adds a shape, labels and styles it, and draws a line", %{
      topic: topic,
      canvas: canvas,
      tools: tools
    } do
      ada = shared(topic)

      assert {:ok, %{"id" => id}} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{
                   "canvas" => canvas,
                   "kind" => "diamond",
                   "x" => 0,
                   "y" => 300,
                   "text" => "Paid?",
                   "style" => %{"fill" => "green"}
                 },
                 agent()
               )

      assert %{type: "shape", width: 140, height: 112} =
               Enum.find(nodes(ada, "schema"), &(&1.id == id))

      graph = Hakushi.Issho.graph(HakushiTest.Issho, canvas)

      assert %{"kind" => "diamond", "text" => "Paid?", "fill" => "green"} =
               Graph.node(graph, id).data

      assert {:ok, _} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{
                   "canvas" => canvas,
                   "node" => id,
                   "text" => "Paid in full?",
                   "style" => %{"stroke" => "red", "rotation" => 90}
                 },
                 agent()
               )

      assert %{"text" => "Paid in full?", "stroke" => "red", "rotation" => 90} =
               Graph.node(Hakushi.Issho.graph(HakushiTest.Issho, canvas), id).data

      assert {:ok, %{"id" => line}} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{
                   "canvas" => canvas,
                   "kind" => "line",
                   "x" => 0,
                   "y" => 0,
                   "to_x" => 100,
                   "to_y" => 50
                 },
                 agent()
               )

      assert %{type: "shape-line"} =
               Graph.node(Hakushi.Issho.graph(HakushiTest.Issho, canvas), line)
    end

    test "says what is wrong", %{topic: topic, canvas: canvas, tools: tools} do
      _ada = shared(topic)

      assert {:error, "Say where" <> _} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{"canvas" => canvas, "kind" => "rect"},
                 agent()
               )

      assert {:error, "A line needs" <> _} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{"canvas" => canvas, "kind" => "line", "x" => 1, "y" => 1},
                 agent()
               )

      assert {:error, ~s("note" is not a shape.)} =
               Issho.Tools.call(
                 tools,
                 "draw_shape",
                 %{"canvas" => canvas, "node" => "note", "text" => "x"},
                 agent()
               )
    end
  end
end
