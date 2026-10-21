# Collaboration

A canvas that several people open at once, as a shared design file is:
each sees the others' changes as they happen, their cursors, the nodes
they selected and those they drag, in their colours.

```heex
<.canvas
  id="schema"
  graph={@schema.graph}
  on_change={&Schemas.change(&1, &2, @schema)}
  live={{MyApp.PubSub, "schema:#{@schema.id}"}}
  user={%{id: @current_user.id, name: @current_user.name}}
>
```

and the hook, in the LiveView or its `live_session`:

```elixir
live_session :default, on_mount: [Hakushi.Live] do
```

That is all: no `Phoenix.Presence`, no CRDT, no service.

## The room

The people of a topic share one process, its room (`Hakushi.Room`). The
first canvas to open starts it, with its `graph`, `rules` and
`on_change`; the others get the room's graph as it is then.

Each change of each person goes to the room, which applies it, checks
the rules, asks `on_change`, and sends it on the topic. Every canvas
applies it to its own graph, in the order the room sent it. So
`on_change` runs once for each change, and two people never save over
each other: the second change applies to the graph the first one made.
A change that no longer makes sense (an edge to a node someone deleted a
moment before) is refused, with the reason.

When the last person leaves, the room waits five seconds (`config
:hakushi, room_timeout:`, in milliseconds), so that a reload finds it,
and stops. The next person to open the canvas starts a room with the
graph you give it, from your database.

## People

`user` is a map with an `:id`, and a `:name`, a `:color` (any CSS
colour) and an `:avatar` (an image's URL) if you have them. A person with
no colour gets one of eight, by their id, the same everywhere. A person
with the canvas open in two tabs is one person, and does not see
themselves.

The avatars of the others show in the corner of the canvas. Draw them
yourself with the `:person` slot, which gets a map with `"id"`,
`"name"`, `"color"` and `"avatar"`.

## Cursors and drags

Each person's cursor, the nodes they selected and the nodes they drag go
to the others as they move, at most twenty times a second, straight
through the PubSub (not through the room, which only orders changes).
A node someone drags moves for everyone while they drag it, with their
name; it lands where they drop it when the room has the move.

## A cluster

The room is registered with `:global`: the canvases of a topic on every
node of a cluster share one room, and the PubSub must reach every node,
as Phoenix's does.

## Who may open a canvas

A person who can open a LiveView with a topic shares that canvas. Check
the person in `mount`, give each canvas a topic of its record
(`"schema:#{schema.id}"`), and check again in `on_change`, which knows
the `user` of each change.
