defmodule Hakushi.RulesTest do
  use ExUnit.Case, async: true

  alias Hakushi.{Edge, Graph, Rules}

  defp graph do
    Graph.new(
      nodes: for(id <- ~w(a b c), do: %{id: id}),
      edges: [%{source: "a", source_handle: "out", target: "b"}, %{source: "b", target: "c"}]
    )
  end

  test "loops, duplicates and cycles" do
    rules = Rules.new([])
    assert Rules.check(rules, graph(), Edge.new(source: "a", target: "a")) == {:error, :loop}

    assert Rules.check(rules, graph(), Edge.new(source: "a", source_handle: "out", target: "b")) ==
             {:error, :duplicate}

    assert Rules.check(rules, graph(), Edge.new(source: "a", source_handle: "other", target: "b")) ==
             :ok

    assert Rules.check(rules, graph(), Edge.new(source: "c", target: "a")) == :ok

    strict = Rules.new(cycles: false)
    assert Rules.check(strict, graph(), Edge.new(source: "c", target: "a")) == {:error, :cycle}
    assert Rules.check(strict, graph(), Edge.new(source: "a", target: "c")) == :ok

    free = Rules.new(loops: true, duplicates: true)
    assert Rules.check(free, graph(), Edge.new(source: "a", target: "a")) == :ok
  end

  test "unknown rules raise" do
    assert_raise ArgumentError, ~r/unknown rule/, fn -> Rules.new(acyclic: true) end
  end
end
