# Versions

A canvas's past: what it was, what changed since, and who changed it.
`Hakushi.History` keeps the versions, and a canvas with `compare` shows
the graph against an older one.

## What changed

`Hakushi.Graph.compare/2` says how one graph became another: the nodes
and edges added and removed, the nodes moved (their place or size), and
those changed, with the fields that changed.

```elixir
Hakushi.Graph.compare(yesterday, today)
#=> %{
#=>   added: %{nodes: ["send-receipt"], edges: ["e7"]},
#=>   removed: %{nodes: ["wait"], edges: ["e4"]},
#=>   moved: ["start"],
#=>   changed: %{nodes: %{"check" => [:data]}, edges: %{}},
#=>   paper: false
#=> }
```

## Seeing it

A canvas with `compare`, an older graph, shows its `graph` against it:
what was added is ringed in green, what changed in orange, what moved
with a dotted ring, and what was removed is there as a ghost, dashed and
faded, where it was. It changes nothing: a canvas that compares is
read-only, and alone (no `issho`).

```heex
<.canvas id="then" graph={@graph} compare={@then} />
```

Each node and edge has `data-diff` (`added`, `removed`, `changed`,
`moved`), and `--hakushi-diff-added`, `-removed`, `-changed` and
`-moved` colour them (see [Theming](theming.md)). `Hakushi.Test.diff/2`
reads them in a test.

## Keeping the versions

`Hakushi.History` is the graph a canvas started from and each change
since, with who made it and when. Record each change in `on_change`, and
keep the history with the canvas (`dump/1` to a column of JSON, `load/1`
back):

```elixir
def change(change, %{by: by}, flow) do
  case Hakushi.History.record(flow.history, change, by: by && by.name) do
    {:ok, history} -> Flows.save(flow, history)
    {:error, _reason, _id} -> {:error, "This flow changed meanwhile."}
  end
end
```

Version 0 is the graph it started from, and each change the next.
`versions/1` lists them (the op, the nodes and edges it touched, `by`,
`at`), `at/2` gives the graph of one, and `compare/3` what changed from
one to another:

```elixir
for v <- Hakushi.History.versions(history), do: {v.version, v.op, v.by, v.at}

then = Hakushi.History.at(history, 12)
```

```heex
<.canvas id="flow-then" graph={Hakushi.History.graph(@history)} compare={@then} />
```

`limit: n` keeps the last `n` changes, and the graph before them: the
versions keep their numbers, and `first/1` is the oldest one it gives
back. A change is kept as it applied (a delete with the edges that went
with it), so a version replays as it was. `Hakushi.Change.dump/1` and
`load/1` keep a change of its own, in a log of the app's.
