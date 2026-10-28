# Marks

What a node or an edge is now, which is not saved: a step that runs, a
table that failed a check, the results of a search, the path between two
nodes. The app marks them from the LiveView, and the canvas draws the
marks on them. They are not part of the graph: `on_change` never sees
them, no one undoes them, and they go when the page goes.

```elixir
Hakushi.Live.mark("flow", "send-receipt", status: :running, progress: 0.4)
Hakushi.Live.mark("flow", "send-receipt", status: :done, progress: nil, badge: "✓")
Hakushi.Live.mark_edges("flow", ["e1", "e2"], status: :running)
```

## A node's mark

| Key | Shows |
| --- | --- |
| `status` | `:running` (a ring of the accent that breathes), `:done` (green), `:failed` (red), `:warning` (orange), `:waiting` (a dashed ring), or a word of the app's own; `data-mark-status` on the node either way |
| `badge` | a few words or a number in a corner: `3`, `"✓"`, `"2 errors"` |
| `progress` | a bar along its foot, from `0` to `1` |
| `highlight` | a ring: `true` for the accent, or a colour (`"#e5484d"`, `"oklch(70% 0.1 200)"`, `"var(--brand)"`) |
| `dim` | `true`: faded, for the nodes that do not matter now |
| `title` | the words a pointer over the node shows |
| `class` | classes of the app's own, for a mark of its own look |

A mark adds to the node's: a key given `nil` goes, and a mark of `nil`
takes them all away. `Hakushi.Live.clear_marks/1` takes away every mark
of the canvas.

```elixir
Hakushi.Live.mark("flow", "check", status: :failed, badge: "2", title: "2 rows did not match")
Hakushi.Live.mark("flow", "check", badge: nil)
Hakushi.Live.mark("flow", "check", nil)
```

An edge's mark is `status`, `highlight`, `dim` and `title`
(`Hakushi.Live.mark_edges/3`): a `:running` edge flows, and a status or
a highlight colours it.

## The spotlight

`Hakushi.Live.spotlight/2` fades every node and edge but some: the path
from one node to another, a part of a flow, what a search found. The
selection stays as it is. `nil` takes it away.

```elixir
way = Hakushi.Graph.path(graph, "start", "send-receipt")
Hakushi.Live.spotlight("flow", nodes: way, edges: Hakushi.Graph.edges_along(graph, way))
Hakushi.Live.spotlight("flow", nil)
```

## A run, step by step

A flow that runs on the server marks each step as it goes: the marks
come to the person's canvas as the LiveView makes them.

```elixir
def handle_event("run", _params, socket) do
  Hakushi.Live.clear_marks("flow")
  Hakushi.Live.mark("flow", Enum.map(steps, & &1.id), status: :waiting)
  Task.start(fn -> Flows.run(flow, notify: self()) end)
  {:noreply, socket}
end

def handle_info({:step, id, :started}, socket) do
  Hakushi.Live.mark("flow", id, status: :running)
  {:noreply, socket}
end

def handle_info({:step, id, {:failed, reason}}, socket) do
  Hakushi.Live.mark("flow", id, status: :failed, title: reason)
  {:noreply, socket}
end
```

## Whose marks they are

Marks are the LiveView's, in its canvas. On a shared canvas each
person's are their own: to show everyone a run, mark it in each
LiveView, from a message they all hear (`Phoenix.PubSub`). A LiveView
that mounts again (a reload, a reconnect) has none: mark again in
`mount`, from what the app knows.

A node that moves, or changes, keeps its mark; a node deleted takes it
with it. `Hakushi.Test.marks/2` reads them in a test.

## Their look

Each status has its colour, `--hakushi-mark-running`, `-done`,
`-failed`, `-warning` and `-waiting`, and a highlight
`--hakushi-mark-highlight`; a node or an edge with a mark has its colour
as `--hakushi-mark`. What fades fades to `--hakushi-mark-dim` (0.32). A
status of the app's own takes its look from the app's styles:

```css
.hakushi-node[data-mark-status="queued"] {
  --hakushi-mark: #8e4ec6;
  box-shadow: 0 0 0 2px var(--hakushi-mark);
}
```

With reduced motion, a running node does not breathe and a running edge
does not flow.
