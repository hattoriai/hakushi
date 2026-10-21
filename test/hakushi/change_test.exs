defmodule Hakushi.ChangeTest do
  use ExUnit.Case, async: true

  alias Hakushi.{Change, Edge}

  test "from_client/1 takes moves, connections, deletes and labels" do
    assert {:ok, %Change{op: :move, nodes: [%{id: "a", x: 1, y: 2.5}]}} =
             Change.from_client(%{
               "op" => "move",
               "nodes" => [%{"id" => "a", "x" => 1, "y" => 2.5}]
             })

    assert {:ok, %Change{nodes: [%{width: 10, height: 20}]}} =
             Change.from_client(%{
               "op" => "move",
               "nodes" => [%{"id" => "a", "x" => 1, "y" => 2, "width" => 10, "height" => 20}]
             })

    assert {:ok,
            %Change{op: :connect, edges: [%Edge{source: "a", source_handle: "out", target: "b"}]}} =
             Change.from_client(%{
               "op" => "connect",
               "edges" => [%{"source" => "a", "sourceHandle" => "out", "target" => "b"}]
             })

    assert {:ok, %Change{op: :delete, nodes: ["a"], edges: []}} =
             Change.from_client(%{"op" => "delete", "nodes" => ["a", "a"]})

    assert {:ok, %Change{op: :update, edges: [%{id: "e", label: "yes"}]}} =
             Change.from_client(%{
               "op" => "update",
               "edges" => [%{"id" => "e", "label" => "  yes "}]
             })
  end

  test "from_client/1 refuses anything else" do
    for params <- [
          %{"op" => "move", "nodes" => [%{"id" => "a", "x" => "1", "y" => 2}]},
          %{
            "op" => "move",
            "nodes" => [%{"id" => "a", "x" => 1, "y" => 2, "width" => -1, "height" => 2}]
          },
          %{"op" => "move", "nodes" => []},
          %{"op" => "add", "nodes" => [%{"id" => "x"}]},
          %{"op" => "delete", "nodes" => [1]},
          %{"op" => "delete"},
          %{"op" => "connect", "edges" => [%{"source" => "a"}]},
          %{"op" => "update", "nodes" => [%{"id" => "a", "data" => %{}}]},
          %{}
        ] do
      assert Change.from_client(params) == :error, inspect(params)
    end
  end
end
