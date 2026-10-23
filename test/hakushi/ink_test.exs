defmodule Hakushi.InkTest do
  # Ink (Hakushi.Kits.Ink): strokes drawn with a pen, as nodes; the lines
  # being drawn, for the others; and an agent that draws.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Hakushi.{Ink, Kits}
  alias Issho.Tool.Context

  @endpoint HakushiTest.Endpoint

  describe "the outline of a stroke" do
    # The browser draws a stroke in progress with ink.ts, and the fixture is
    # what it draws (assets/test/ink.test.ts checks it there): the node the
    # stroke becomes is the same shape.
    @fixture "test/fixtures/ink.json" |> File.read!() |> JSON.decode!()

    test "is the browser's, to the character" do
      for %{"name" => name} = stroke <- @fixture["strokes"] do
        assert Ink.outline(stroke["points"], stroke["size"], stroke["flat"]) == stroke["outline"],
               name

        assert Ink.centerline(stroke["points"]) == stroke["centerline"], name
      end
    end

    test "writes numbers as the browser does" do
      for [n, text] <- @fixture["numbers"], do: assert(Ink.fmt(n) == text, inspect(n))
    end

    test "is thinner with less pressure, and one width for a highlighter" do
      assert Ink.outline([[0, 0, 0], [100, 0, 0]], 10) =~ ~r/^M0 2\.5L100 2\.5/
      assert Ink.outline([[0, 0, 1], [100, 0, 1]], 10) =~ ~r/^M0 7\.5L100 7\.5/
      # [x, y] has no pressure: the width of 0.5.
      assert Ink.outline([[0, 0], [100, 0]], 10) == Ink.outline([[0, 0, 0.5], [100, 0, 0.5]], 10)

      assert Ink.outline([[0, 0, 0], [100, 0, 1]], 10, true) ==
               Ink.outline([[0, 0], [100, 0]], 10)

      assert Ink.outline([], 4) == ""
    end
  end

  describe "a stroke's node" do
    test "is a box around its points, which are relative to it" do
      assert {:ok, node} = Kits.Ink.stroke([[100, 50], [140, 70, 1]], color: "red", size: 4)

      # Room for the widest line (0.75 of the size) and a pixel.
      assert %{type: "ink-stroke", x: 96.0, y: 46.0, width: 48.0, height: 28.0} = node

      assert node.data == %{
               "tool" => "pen",
               "color" => "red",
               "size" => 4,
               "points" => [[4.0, 4.0, 0.5], [44.0, 24.0, 1.0]]
             }
    end

    test "has its tool's colour and width unless given, and none it does not have" do
      assert {:ok, %{data: %{"color" => "ink", "size" => 4}}} = Kits.Ink.stroke([[0, 0]])

      assert {:ok, %{data: %{"tool" => "highlighter", "color" => "yellow", "size" => 20}}} =
               Kits.Ink.stroke([[0, 0]], tool: "highlighter", color: "magenta", size: -1)

      assert {:ok, %{data: %{"size" => 64}}} = Kits.Ink.stroke([[0, 0]], size: 500)
      assert :error = Kits.Ink.stroke([[0, 0]], tool: "brush")
    end

    test "takes points of numbers, and thins a stroke of too many" do
      assert :error = Kits.Ink.stroke([])
      assert :error = Kits.Ink.stroke([[0, "1"]])
      assert :error = Kits.Ink.stroke(nil)
      assert {:ok, %{data: %{"points" => [[_, _, 1.0]]}}} = Kits.Ink.stroke([[0, 0, 7]])

      long = for i <- 0..4_999, do: [i, 0]
      assert {:ok, %{data: %{"points" => points}, width: width}} = Kits.Ink.stroke(long)
      assert length(points) <= 2_000
      # Its last point stays: the stroke is as long.
      assert width == 4_999 + 8
    end
  end

  describe "a canvas with ink" do
    defp open(query \\ "") do
      {:ok, view, html} = live(build_conn(), "/kits" <> query)
      {view, html}
    end

    test "has the kit's tools in its bar, and nothing to drop" do
      {_view, html} = open()
      [config] = Regex.run(~r/data-config="([^"]+)"/, html, capture: :all_but_first)

      tools =
        config |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> JSON.decode!()

      assert [
               %{"kit" => "ink", "tool" => "pen", "mode" => "draw", "colors" => colors},
               %{"tool" => "highlighter", "flat" => true},
               %{"tool" => "eraser", "mode" => "erase", "types" => ["ink-stroke"]},
               %{"tool" => "lasso", "mode" => "lasso"}
             ] = Enum.filter(tools["tools"], &(&1["kit"] == "ink"))

      assert "red" in colors
      refute html =~ ~s(data-hakushi-item="ink:)
    end

    test "makes a node of a line drawn, which erases and comes back as any" do
      {view, _html} = open()

      assert {:ok, id} =
               draw(view, "board", "ink:pen", [[10, 400, 0.3], [60, 420, 0.8]], color: "blue")

      assert %{type: "ink-stroke", label: "Drawing", width: w, height: h} =
               Enum.find(nodes(view, "board"), &(&1.id == id))

      assert w > 50 and h > 20

      html = render(view)
      assert html =~ ~r/data-id="#{id}"[^>]*aria-label="Drawing"/
      assert html =~ ~s(class="hakushi-ink" data-tool="pen" data-color="blue")
      assert html =~ ~s(class="hakushi-ink-line" d="M)

      # The eraser deletes it; ⌘Z brings it back.
      assert :ok = remove(view, "board", nodes: [id])
      refute Enum.any?(nodes(view, "board"), &(&1.id == id))
      assert :ok = undo(view, "board")
      assert Enum.any?(nodes(view, "board"), &(&1.id == id))
    end

    test "draws a highlighter's line, and refuses a tool it does not have" do
      {view, _html} = open()

      assert {:ok, id} = draw(view, "board", "ink:highlighter", [[0, 0], [80, 0]])
      assert render(view) =~ ~s(data-tool="highlighter" data-color="yellow")
      assert Enum.any?(nodes(view, "board"), &(&1.id == id))

      assert {:error, nil} = draw(view, "board", "ink:brush", [[0, 0], [80, 0]])
      assert {:error, nil} = draw(view, "board", "notes:pen", [[0, 0], [80, 0]])
      assert {:error, nil} = draw(view, "board", "ink:pen", [])
    end

    test "draws nothing on a read-only canvas" do
      {view, _html} = open("?readonly=true")
      assert {:error, "This canvas is read-only."} = draw(view, "board", "ink:pen", [[0, 0]])
    end
  end

  describe "a line being drawn, for the others" do
    test "is numbers and names, and no more points than a stroke has" do
      line = %{"tool" => "ink:pen", "color" => "red", "size" => 4, "points" => [[1, 2, 0.5]]}
      assert Hakushi.Canvas.ink(line) == line

      assert %{"points" => points} =
               Hakushi.Canvas.ink(%{line | "points" => List.duplicate([1, 2, 0.5], 5_000)})

      assert length(points) == 1_500
      assert %{"size" => 64} = Hakushi.Canvas.ink(%{line | "size" => 1_000})

      assert %{"points" => [[1, 2, 0.5]]} =
               Hakushi.Canvas.ink(%{line | "points" => [[1, 2, 0.5], ["x", 2, 0.5], [1, 2]]})

      assert nil == Hakushi.Canvas.ink(%{line | "color" => "url(javascript:1)"})
      assert nil == Hakushi.Canvas.ink(%{line | "points" => []})
      assert nil == Hakushi.Canvas.ink(%{line | "size" => 0})
      assert nil == Hakushi.Canvas.ink(nil)
    end
  end

  describe "an agent that draws" do
    defp shared(topic) do
      {:ok, view, _html} = live(build_conn(), "/?live=#{topic}&user=ada")
      view
    end

    defp agent,
      do: Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})

    defp ink_nodes(view), do: Enum.filter(nodes(view, "schema"), &(&1.type == "ink-stroke"))

    setup do
      on_exit(fn -> Application.delete_env(:hakushi, Hakushi.Issho) end)
      %{topic: "ink#{System.unique_integer([:positive])}"}
    end

    test "circles a node, and the people see its pen draw the ring", %{topic: topic} do
      ada = shared(topic)
      args = %{"canvas" => "canvas:" <> topic, "around" => "note"}

      {took, result} =
        :timer.tc(fn ->
          Issho.Tools.call(Hakushi.Issho.tools(), "draw_on_canvas", args, agent())
        end)

      assert {:ok, %{"strokes" => [id]}} = result
      # To the ring's start, then the ring, as fast as the pen goes.
      assert took >= 500_000

      # Ada's canvas got the line as it grew, with the agent's pointer at
      # its tip, then the node; then no line.
      assert_push_event(ada, "hakushi:peer", %{
        "ink" => %{"color" => "red", "points" => [_ | _] = first}
      })

      assert_push_event(ada, "hakushi:peer", %{"ink" => %{"points" => later}, "cursor" => [_, _]})
      assert length(later) > length(first)

      assert [%{id: ^id}] = ink_nodes(ada)
      note = Enum.find(nodes(ada, "schema"), &(&1.id == "note"))
      ring = hd(ink_nodes(ada))
      # Around the note.
      assert ring.x < note.x and ring.y < note.y
    end

    test "draws strokes at once when it is told to, or the app says", %{topic: topic} do
      ada = shared(topic)
      canvas = "canvas:" <> topic

      strokes = [
        %{"points" => [[0, 0], [100, 40]], "color" => "blue"},
        %{"points" => [[0, 60], [100, 60]]}
      ]

      tools = Hakushi.Issho.tools()

      {took, {:ok, %{"strokes" => [_, _]}}} =
        :timer.tc(fn ->
          Issho.Tools.call(
            tools,
            "draw_on_canvas",
            %{"canvas" => canvas, "strokes" => strokes, "live" => false},
            agent()
          )
        end)

      assert took < 300_000
      refute_push_event(ada, "hakushi:peer", %{"ink" => %{}})

      Application.put_env(:hakushi, Hakushi.Issho, ink: [live: false])

      {took, {:ok, _}} =
        :timer.tc(fn ->
          Issho.Tools.call(
            tools,
            "draw_on_canvas",
            %{"canvas" => canvas, "strokes" => strokes},
            agent()
          )
        end)

      assert took < 300_000
      assert [_, _, _, _] = ink_nodes(ada)
    end

    test "draws for as long as the app says, then at once", %{topic: topic} do
      _ada = shared(topic)
      Application.put_env(:hakushi, Hakushi.Issho, ink: [speed: 50, max: 300])
      long = %{"points" => [[0, 0], [2_000, 0]]}
      args = %{"canvas" => "canvas:" <> topic, "strokes" => [long, long]}

      {took, {:ok, _}} =
        :timer.tc(fn ->
          Issho.Tools.call(Hakushi.Issho.tools(), "draw_on_canvas", args, agent())
        end)

      # 40 seconds at that speed: the glides, and 300ms of drawing.
      assert took < 2_500_000
    end

    test "says what is wrong", %{topic: topic} do
      _ada = shared(topic)
      canvas = "canvas:" <> topic
      tools = Hakushi.Issho.tools()

      assert {:error, "Say what to draw" <> _} =
               Issho.Tools.call(tools, "draw_on_canvas", %{"canvas" => canvas}, agent())

      assert {:error, "The canvas has no node" <> _} =
               Issho.Tools.call(
                 tools,
                 "draw_on_canvas",
                 %{"canvas" => canvas, "around" => "nope"},
                 agent()
               )

      assert {:error, "A stroke needs points" <> _} =
               Issho.Tools.call(
                 tools,
                 "draw_on_canvas",
                 %{"canvas" => canvas, "strokes" => [%{"points" => []}]},
                 agent()
               )
    end
  end
end
