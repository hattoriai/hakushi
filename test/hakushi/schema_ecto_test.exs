defmodule Hakushi.SchemaEctoTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hakushi.Graph
  alias Hakushi.Kits.Schema
  alias HakushiTest.Blog

  @blog [Blog.User, Blog.Post, Blog.Tag, Blog.Comment]

  defp table(graph, id), do: Graph.node(graph, id).data

  defp columns(graph, id),
    do: Map.new(table(graph, id)["columns"], &{&1["name"], {&1["type"], &1["key"]}})

  test "a table for each schema, its fields as columns, with their types and keys" do
    graph = Schema.from_ecto(@blog)

    assert %{"name" => "users"} = table(graph, "users")
    assert Graph.node(graph, "users").type == "schema-table"

    assert columns(graph, "users") == %{
             "id" => {"id", "pk"},
             "email" => {"string", nil},
             "roles" => {"string[]", nil},
             "inserted_at" => {"utc_datetime", nil},
             "updated_at" => {"utc_datetime", nil}
           }

    # The column's name in the table; an enum as the type it is stored as.
    assert columns(graph, "posts") == %{
             "id" => {"binary_id", "pk"},
             "post_title" => {"string", nil},
             "state" => {"string", nil},
             "body" => {"map", nil},
             "author_id" => {"id", "fk"}
           }

    # A column's handle is its name: a foreign key stays as the table changes.
    assert Enum.all?(table(graph, "posts")["columns"], &(&1["id"] == &1["name"]))
  end

  test "a foreign key for each belongs_to, from its column to the key it refers to" do
    graph = Schema.from_ecto(@blog)

    edges =
      Enum.map(Graph.edges(graph), &{&1.source, &1.source_handle, &1.target, &1.target_handle})

    assert {"posts", "author_id", "users", "id"} in edges
    assert {"comments", "post_id", "posts", "id"} in edges
    assert {"posts_tags", "post_id", "posts", "id"} in edges
    assert {"posts_tags", "tag_id", "tags", "id"} in edges
    assert Enum.all?(Graph.edges(graph), &(&1.path == "smooth"))
  end

  test "a join table of no schema of its own, with its two keys" do
    graph = Schema.from_ecto(@blog)

    assert columns(graph, "posts_tags") == %{
             "post_id" => {"binary_id", "fk"},
             "tag_id" => {"id", "fk"}
           }
  end

  test "a schema not among them is a stub, or nothing" do
    graph = Schema.from_ecto(@blog)

    assert %{
             "external" => true,
             "schema" => "billing",
             "name" => "accounts",
             "columns" => [%{"name" => "id", "key" => "pk"}]
           } =
             table(graph, "billing.accounts")

    assert Enum.any?(
             Graph.edges(graph),
             &(&1.source == "comments" and &1.target == "billing.accounts")
           )

    assert columns(graph, "comments")["account_id"] == {"id", "fk"}

    graph = Schema.from_ecto(@blog, stubs: false)
    refute Graph.node(graph, "billing.accounts")
    refute Enum.any?(Graph.edges(graph), &(&1.target == "billing.accounts"))
  end

  test "a prefix is the table's schema, and its id" do
    graph = Schema.from_ecto([Blog.Comment, HakushiTest.Billing.Account])
    assert %{"schema" => "billing", "name" => "accounts"} = table(graph, "billing.accounts")
    refute table(graph, "billing.accounts")["external"]
  end

  test "the schemas of an app, but the embedded ones, laid out" do
    graph = Schema.from_ecto(:hakushi)
    ids = Enum.map(Graph.nodes(graph), & &1.id)
    assert "users" in ids and "billing.accounts" in ids
    refute Enum.any?(Graph.nodes(graph), &(&1.data["name"] == nil))

    places = Enum.map(Graph.nodes(graph), &{&1.x, &1.y})
    assert length(Enum.uniq(places)) == length(places)
  end

  test "the Schema kit draws it, the stub faint" do
    html =
      render_component(&Hakushi.Components.canvas/1,
        id: "db",
        graph: Schema.from_ecto(@blog),
        kits: [Schema],
        tidy: true
      )

    assert html =~ ~s(data-id="posts")
    assert html =~ "post_title"
    assert html =~ "billing.accounts"
    assert html =~ "data-hakushi-faint"
  end

  test "a module that is no schema of a table" do
    assert_raise ArgumentError, ~r/not an Ecto schema/, fn ->
      Schema.from_ecto([Blog.Settings])
    end

    assert_raise ArgumentError, ~r/not an Ecto schema/, fn -> Schema.from_ecto([String]) end
  end
end
