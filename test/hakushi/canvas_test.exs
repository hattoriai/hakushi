defmodule Hakushi.CanvasTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  @endpoint HakushiTest.Endpoint

  defp open(query \\ "") do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"test" => Base.encode64(:erlang.term_to_binary(self()))})

    {:ok, view, html} = live(conn, "/" <> query)
    {view, html}
  end

  test "renders the nodes with their slots, the edges and the config" do
    {view, html} = open()

    assert [
             %{id: "users", type: "table", x: 0, y: 0, label: "users"},
             %{id: "orders", x: 320, y: 40},
             %{id: "note", type: "default", label: "A note"},
             %{id: "pinned", locked: true}
           ] = nodes(view, "schema")

    assert [
             %{
               id: "fk",
               source: "orders",
               source_handle: "user_id",
               target: "users",
               target_handle: "id"
             }
           ] =
             edges(view, "schema")

    assert html =~ ~s(data-handle="user_id")
    assert html =~ ~s(phx-hook="Hakushi")
    assert html =~ ~s(aria-label="Schema")
    assert html =~ "hakushi-default-node"
    assert html =~ "&quot;cycles&quot;:false"
  end

  test "moves nodes, and refuses a locked one" do
    {view, _html} = open()
    assert :ok = move(view, "schema", "users", {40, 60})
    assert_receive {:on_change, %Hakushi.Change{op: :move}, %{graph: _, result: result}}
    assert Hakushi.Graph.node(result, "users").x == 40
    assert %{x: 40, y: 60} = Enum.find(nodes(view, "schema"), &(&1.id == "users"))

    assert {:error, "This node is locked."} = move(view, "schema", "pinned", {1, 1})
    assert notice(view, "schema") == "This node is locked."
    assert :ok = move(view, "schema", [{"note", 1, 2, 200, 100}])
    assert notice(view, "schema") == nil
    assert %{width: 200, height: 100} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
  end

  test "connects with the rules, and the app's on_change" do
    {view, _html} = open()

    assert {:error, "A node cannot connect to itself."} =
             connect(view, "schema", "users", "users")

    assert {:error, "This connection would close a loop."} =
             connect(view, "schema", {"users", "id"}, {"orders", "id"})

    assert :ok = connect(view, "schema", "note", "users")
    assert length(edges(view, "schema")) == 2
    assert {:error, "These are already connected."} = connect(view, "schema", "note", "users")
  end

  test "deletes with the edges, asks the app, and undoes" do
    {view, _html} = open()
    assert {:error, "The users table stays."} = remove(view, "schema", nodes: ["users"])
    assert :ok = remove(view, "schema", nodes: ["orders"])
    assert edges(view, "schema") == []
    refute Enum.any?(nodes(view, "schema"), &(&1.id == "orders"))

    assert :ok = undo(view, "schema")
    assert Enum.any?(nodes(view, "schema"), &(&1.id == "orders"))
    assert [%{id: "fk"}] = edges(view, "schema")

    assert :ok = redo(view, "schema")
    assert edges(view, "schema") == []
    assert {:error, "Nothing to redo."} = redo(view, "schema")
  end

  test "undo takes back a person's moves in order" do
    {view, _html} = open()
    :ok = move(view, "schema", "note", {10, 10})
    :ok = move(view, "schema", "note", {20, 20})
    :ok = undo(view, "schema")
    assert %{x: 10} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
    :ok = undo(view, "schema")
    assert %{x: 0, y: 300} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
    assert {:error, "Nothing to undo."} = undo(view, "schema")
  end

  test "drops a node into another, and a delete of it takes the node in it" do
    {view, _html} = open()
    assert :ok = move(view, "schema", [%{id: "note", x: 10, y: 10, parent: "users"}])
    assert %{parent: "users"} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))

    assert :ok = move(view, "schema", "users", {100, 100})
    assert %{x: 110, y: 110} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))

    assert {:error, "A group cannot go inside itself."} =
             move(view, "schema", [%{id: "users", x: 0, y: 0, parent: "note"}])

    assert {:ok, [copy_users, copy_note]} = copy_paste(view, "schema", ["users"], {2000, 0})
    assert %{parent: ^copy_users} = Enum.find(nodes(view, "schema"), &(&1.id == copy_note))
  end

  test "reconnects an edge with the rules" do
    {view, _html} = open()
    assert :ok = reconnect(view, "schema", "fk", target: "note")

    assert [%{id: "fk", source: "orders", target: "note", target_handle: nil}] =
             edges(view, "schema")

    assert {:error, "A node cannot connect to itself."} =
             reconnect(view, "schema", "fk", target: "orders")

    assert :ok = undo(view, "schema")
    assert [%{target: "users", target_handle: "id"}] = edges(view, "schema")
  end

  test "labels an edge" do
    {view, _html} = open()
    assert :ok = label(view, "schema", "fk", "  belongs to ")
    assert [%{label: "belongs to"}] = edges(view, "schema")
  end

  test "copies, pastes and duplicates with new ids and their edges" do
    {view, _html} = open()
    assert {:ok, [users, orders]} = copy_paste(view, "schema", ["users", "orders"], {1000, 1000})
    assert %{x: 1000, y: 1000} = Enum.find(nodes(view, "schema"), &(&1.id == users))
    assert %{x: 1320, y: 1040} = Enum.find(nodes(view, "schema"), &(&1.id == orders))
    assert Enum.any?(edges(view, "schema"), &(&1.source == orders and &1.target == users))

    assert {:ok, [copy]} = duplicate(view, "schema", ["note"])
    assert %{x: 24, y: 324} = Enum.find(nodes(view, "schema"), &(&1.id == copy))
  end

  test "drops items through new_node" do
    {view, _html} = open()
    assert {:ok, [id]} = drop(view, "schema", "table", {50, 60})
    assert %{type: "table", x: 50, y: 60} = Enum.find(nodes(view, "schema"), &(&1.id == id))
    assert {:ok, [_id]} = drop(view, "schema", nil, {0, 0})
    assert {:error, nil} = drop(view, "schema", "unknown", {0, 0})

    assert {:ok, [inside]} = drop(view, "schema", nil, {5, 5}, parent: "users")
    assert %{parent: "users"} = Enum.find(nodes(view, "schema"), &(&1.id == inside))
    assert {:ok, [nowhere]} = drop(view, "schema", nil, {5, 5}, parent: "gone")
    assert %{parent: nil} = Enum.find(nodes(view, "schema"), &(&1.id == nowhere))
  end

  test "a new graph from the LiveView, and the app's own changes" do
    {view, _html} = open()
    render_click(view, "replace", %{})
    assert %{label: "Changed"} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))

    render_click(view, "app_change", %{})
    assert %{x: 7, y: 7} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
    assert {:error, "Nothing to undo."} = undo(view, "schema")
  end

  test "a read-only canvas changes nothing" do
    {view, _html} = open("?readonly=true")
    assert {:error, "This canvas is read-only."} = move(view, "schema", "note", {1, 1})
  end

  describe "an arrange-only canvas" do
    test "moves nodes, and undoes and redoes the moves" do
      {view, html} = open("?readonly=arrange")
      assert html =~ ~s(&quot;arrange&quot;:true)
      assert html =~ ~s(&quot;readonly&quot;:true)

      assert :ok = move(view, "schema", "note", {11, 12})
      assert %{x: 11, y: 12} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))

      assert :ok = undo(view, "schema")
      refute match?(%{x: 11}, Enum.find(nodes(view, "schema"), &(&1.id == "note")))
      assert :ok = redo(view, "schema")
      assert %{x: 11, y: 12} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
    end

    test "changes nothing else" do
      {view, _html} = open("?readonly=arrange")
      readonly = {:error, "This canvas is read-only."}

      assert ^readonly = move(view, "schema", [{"note", 1, 1, 50, 50}])
      assert ^readonly = move(view, "schema", [%{id: "note", x: 1, y: 1, parent: nil}])
      assert ^readonly = connect(view, "schema", "users", "note")
      assert ^readonly = remove(view, "schema", nodes: ["note"])
      assert ^readonly = drop(view, "schema", nil, {5, 5})
      assert ^readonly = label(view, "schema", "fk", "owns")
    end

    test "a read-only canvas does not arrange" do
      {view, html} = open("?readonly=true")
      assert html =~ ~s(&quot;arrange&quot;:false)
      assert {:error, "This canvas is read-only."} = undo(view, "schema")
    end
  end

  describe "layout" do
    test "the canvas's way to lay out goes to the browser, as an algorithm and a direction" do
      {_view, html} = open()
      assert html =~ "&quot;layout&quot;:&quot;right&quot;"
      assert html =~ "&quot;algorithm&quot;:&quot;layered&quot;"

      {_view, html} = open("?layout=force")
      assert html =~ "&quot;algorithm&quot;:&quot;force&quot;"

      {_view, html} = open("?layout=down")
      assert html =~ "&quot;layout&quot;:&quot;down&quot;"
      assert html =~ "&quot;algorithm&quot;:&quot;layered&quot;"
    end

    test "a canvas that should be read says so" do
      html =
        render_component(&Hakushi.Components.canvas/1,
          id: "big",
          graph: Hakushi.Graph.new(),
          fit: :readable
        )

      assert html =~ "&quot;fit&quot;:&quot;readable&quot;"
    end

    test "layout!/1 takes the forms of the attribute, and refuses others" do
      assert Hakushi.Canvas.layout!(:right) == {:layered, :right}
      assert Hakushi.Canvas.layout!(:down) == {:layered, :down}
      assert Hakushi.Canvas.layout!(:grid) == {:grid, :right}
      assert Hakushi.Canvas.layout!({:layered, :down}) == {:layered, :down}
      assert_raise ArgumentError, fn -> Hakushi.Canvas.layout!(:spiral) end
      assert_raise ArgumentError, fn -> Hakushi.Canvas.layout!({:force, :up}) end
    end

    test "the app tidies up with an algorithm" do
      {view, _html} = open()
      render_click(view, "app_layout", %{"algorithm" => "force"})
      assert_push_event(view, "hakushi:layout", %{"canvas" => "schema", "algorithm" => "force"})

      render_click(view, "app_layout", %{"direction" => "down"})
      assert_push_event(view, "hakushi:layout", %{"direction" => "down"} = payload)
      refute Map.has_key?(payload, "algorithm")
    end
  end

  describe "the app and the view" do
    test "on_select hears what the person selects, of what the canvas has" do
      {view, _html} = open()
      assert :ok = select(view, "schema", ["users", "gone"], ["fk"])
      assert_receive {:on_select, %{canvas: "schema", nodes: ["users"], edges: ["fk"]}}

      assert :ok = select(view, "schema", [])
      assert_receive {:on_select, %{nodes: [], edges: []}}
    end

    test "on_viewport hears where the view came to rest, checked" do
      {view, _html} = open()
      assert :ok = viewport(view, "schema", {-20, 10.5, 800, 600}, 1.25)

      assert_receive {:on_viewport,
                      %{canvas: "schema", x: -20, y: 10.5, width: 800, height: 600, zoom: 1.25}}

      assert :ok = viewport(view, "schema", {0, 0, 0, 600}, 1)
      assert :ok = viewport(view, "schema", {0, 0, 800, 600}, -1)
      refute_receive {:on_viewport, _}
    end

    test "a read-only canvas tells the app what is selected and seen too" do
      {view, _html} = open("?readonly=true")
      assert :ok = select(view, "schema", ["orders"])
      assert_receive {:on_select, %{nodes: ["orders"]}}
      assert :ok = viewport(view, "schema", {0, 0, 100, 100}, 1)
      assert_receive {:on_viewport, %{width: 100}}
    end

    test "the browser reports only to a canvas that listens" do
      {_view, html} = open()
      assert html =~ "&quot;reportSelect&quot;:true"
      assert html =~ "&quot;reportView&quot;:true"

      html =
        render_component(&Hakushi.Components.canvas/1, id: "quiet", graph: Hakushi.Graph.new())

      assert html =~ "&quot;reportSelect&quot;:false"
      assert html =~ "&quot;reportView&quot;:false"
    end

    test "fit/2 shows every node, some, or a box" do
      {view, _html} = open()
      render_click(view, "app_view", %{"fun" => "fit"})

      assert_push_event(
        view,
        "hakushi:view",
        %{
          "canvas" => "schema",
          "padding" => 48,
          "animate" => true
        } = payload
      )

      refute Map.has_key?(payload, "nodes")

      render_click(view, "app_view", %{"fun" => "fit", "nodes" => ["users"], "padding" => 0})
      assert_push_event(view, "hakushi:view", %{"nodes" => ["users"], "padding" => 0})

      render_click(view, "app_view", %{
        "fun" => "fit",
        "box" => [0, 0, 400, 300],
        "animate" => false
      })

      assert_push_event(view, "hakushi:view", %{"box" => [0, 0, 400, 300], "animate" => false})
    end

    test "focus/3 goes to nodes and selects them, unless told not to" do
      {view, _html} = open()
      render_click(view, "app_view", %{"fun" => "focus", "ids" => "orders"})

      assert_push_event(
        view,
        "hakushi:view",
        %{"focus" => ["orders"], "select" => true} = payload
      )

      refute Map.has_key?(payload, "zoom")

      render_click(view, "app_view", %{
        "fun" => "focus",
        "ids" => ["users", "orders"],
        "select" => false,
        "zoom" => 2
      })

      assert_push_event(view, "hakushi:view", %{
        "focus" => ["users", "orders"],
        "select" => false,
        "zoom" => 2
      })
    end

    test "select/3 selects nodes and edges in the browser" do
      {view, _html} = open()
      render_click(view, "app_view", %{"fun" => "select", "ids" => ["users"], "edges" => ["fk"]})

      assert_push_event(view, "hakushi:select", %{
        "nodes" => ["users"],
        "edges" => ["fk"],
        "reveal" => false
      })

      render_click(view, "app_view", %{"fun" => "select", "ids" => [], "reveal" => true})
      assert_push_event(view, "hakushi:select", %{"nodes" => [], "reveal" => true})
    end

    test "the view's functions refuse what they cannot do" do
      assert_raise ArgumentError, fn -> Hakushi.Live.fit("c", nodes: ["a"], box: {0, 0, 1, 1}) end
      assert_raise ArgumentError, fn -> Hakushi.Live.fit("c", box: {0, 0, 0, 1}) end
      assert_raise ArgumentError, fn -> Hakushi.Live.fit("c", padding: -1) end
      assert_raise ArgumentError, fn -> Hakushi.Live.focus("c", [:a]) end
      assert_raise ArgumentError, fn -> Hakushi.Live.focus("c", "a", zoom: 0) end
      assert_raise ArgumentError, fn -> Hakushi.Live.select("c", nil) end
    end
  end

  describe "tidy as it opens" do
    test "the canvas says so, and hides its nodes until the browser has laid them out" do
      {_view, html} = open("?tidy=true")
      assert html =~ ~s(data-tidy="true")
      assert html =~ "&quot;tidy&quot;:true"

      {_view, html} = open()
      refute html =~ "data-tidy"
      assert html =~ "&quot;tidy&quot;:false"
    end

    test "the places it opens with are kept, and no undo takes them back" do
      {view, _html} = open("?tidy=true&readonly=arrange")

      view
      |> element("#schema-hook")
      |> render_hook("hakushi:change", %{
        "op" => "move",
        "opened" => true,
        "nodes" => [%{"id" => "note", "x" => 40, "y" => 50}]
      })

      assert_reply(view, %{"ok" => true})
      assert %{x: 40, y: 50} = Enum.find(nodes(view, "schema"), &(&1.id == "note"))
      assert {:error, "Nothing to undo."} = undo(view, "schema")
    end

    test "only a move goes without an undo" do
      {view, _html} = open()

      view
      |> element("#schema-hook")
      |> render_hook("hakushi:change", %{"op" => "delete", "opened" => true, "nodes" => ["note"]})

      assert_reply(view, %{"ok" => true})
      refute Enum.find(nodes(view, "schema"), &(&1.id == "note"))
      assert :ok = undo(view, "schema")
    end
  end

  describe "a selection in words, the label of its place" do
    alias Hakushi.{Canvas, Graph, Kits, Messages}

    @kits [Kits.Notes, Kits.Flow, Kits.Shapes, Kits.Images, Kits.Ink]

    defp label(nodes, ids, opts \\ []) do
      assigns = %{
        graph: Graph.new(nodes: nodes),
        kits: @kits,
        messages: Messages.for_locale(opts[:locale] || "en", %{}),
        node_label: opts[:node_label] || (&Canvas.label/1)
      }

      Canvas.place_label(assigns, ids)
    end

    test "a node's words: its title, text, alt or name" do
      flow = %{id: "f", type: "flow-step", data: %{"title" => "Invoice paid", "detail" => "x"}}
      note = %{id: "n", type: "note", data: %{"text" => "  Ask finance\nabout refunds "}}
      image = %{id: "i", type: "image", data: %{"alt" => "The palette", "url" => "/a.png"}}
      table = %{id: "t", data: %{name: "users"}}

      assert label([flow], ["f"]) == "Invoice paid"
      assert label([note], ["n"]) == "Ask finance about refunds"
      assert label([image], ["i"]) == "The palette"
      assert label([table], ["t"]) == "users"
    end

    test "the first words of a long text, whole, in 60 characters" do
      text = String.duplicate("Fold it again and ", 10)
      words = label([%{id: "n", type: "note", data: %{"text" => text}}], ["n"])

      assert words == "Fold it again and Fold it again and Fold it again and Fold…"
      assert String.length(words) <= 60
    end

    test "a node without words: its kind, never its id" do
      assert label([%{id: "n", type: "note", data: %{"text" => ""}}], ["n"]) == "Note"
      assert label([%{id: "i", type: "image", data: %{"url" => "/a.png"}}], ["i"]) == "Image"

      assert label([%{id: "s", type: "ink-stroke", data: %{"points" => []}}], ["s"]) ==
               Messages.for_locale("en", %{})["drawing"]

      assert label([%{id: "x", type: "default", data: %{}}], ["x"]) == nil
    end

    test "the app's node_label says it" do
      nodes = [%{id: "t", data: %{name: "users"}}]
      assert label(nodes, ["t"], node_label: &"Table #{&1.data.name}") == "Table users"
    end

    test "several nodes: how many, in the canvas's language" do
      nodes = [%{id: "a", data: %{}}, %{id: "b", data: %{}}, %{id: "c", data: %{}}]

      assert label(nodes, ["a", "b", "c"]) == "3 nodes"
      assert label(nodes, ["a", "b", "gone"]) == "2 nodes"
      assert label(nodes, ["a", "b"], locale: "fr") == "2 nœuds"
      assert label(nodes, ["gone"]) == nil
    end
  end

  test "refuses what a browser should not send" do
    {view, _html} = open()
    assert {:error, _} = Hakushi.Test.move(view, "schema", [{"note", "x", 1}])
  end
end
