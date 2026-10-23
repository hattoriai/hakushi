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

  test "refuses what a browser should not send" do
    {view, _html} = open()
    assert {:error, _} = Hakushi.Test.move(view, "schema", [{"note", "x", 1}])
  end
end
