# Testing

`Hakushi.Test` reads and changes the canvases of a LiveView in
`Phoenix.LiveViewTest`, with no browser.

```elixir
import Hakushi.Test

test "a foreign key joins columns of one type", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/schema")

  assert :ok = connect(view, "schema", {"orders", "user_id"}, {"users", "id"})
  assert %{target: "users"} = Enum.find(edges(view, "schema"), &(&1.source == "orders"))

  assert {:error, "These columns are not of one type."} =
           connect(view, "schema", {"orders", "total"}, {"users", "id"})
end
```

The functions send the events the browser sends, so each change goes
the way of a person's: the rules, `on_change`, the room of a shared
canvas. A change the canvas refuses gives `{:error, reason}`, with the
words the person sees.

| | |
| --- | --- |
| `nodes/2`, `edges/2` | what the canvas shows, as maps |
| `move/4` | `move(view, id, "node", {x, y})`, or several with sizes |
| `connect/4` | ends as a node's id or `{node, handle}` |
| `remove/3` | `nodes:` and `edges:` (not `delete`, which `Phoenix.ConnTest` has) |
| `label/4` | an edge's label |
| `copy_paste/4`, `duplicate/3` | `{:ok, ids}` of the copies |
| `drop/4` | an item, through `new_node` |
| `undo/2`, `redo/2` | the LiveView's person's own changes |
| `notice/2` | the reason the canvas shows for its last refusal |
| `people/2` | the others on a shared canvas |

A shared canvas in a test is shared with the other LiveViews of its
topic in the test: open two, as two people, to test what one sees of the
other. Give the rooms a short life in `config/test.exs`:

```elixir
config :hakushi, room_timeout: 50
```
