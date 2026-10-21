# Collaboration

A canvas that several people open at once, as a shared design file is:
each sees the others' changes as they happen, their cursors, the nodes
they selected and those they drag, in their colours.

A shared canvas is a room of [Issho](https://hex.pm/packages/issho),
collaboration for Phoenix: Hakushi on its own is a canvas for one person,
and Issho makes it a canvas for many, with the people's own permissions
and no service besides your app.

```heex
<.canvas
  id="schema"
  graph={@schema.graph}
  on_change={&Schemas.change(&1, &2, @schema)}
  live={{MyApp.Issho, "schema:#{@schema.id}"}}
  user={%{id: @current_user.id, name: @current_user.name}}
>
```

## Setting up

1. Issho in your dependencies:

   ```elixir
   {:issho, "~> 0.2"}
   ```

2. An Issho instance in your supervision tree, after the PubSub, with
   your policy: who may open which canvas, and change it.

   ```elixir
   {Issho,
    name: MyApp.Issho,
    pubsub: MyApp.PubSub,
    endpoint: MyAppWeb.Endpoint,
    policy: MyApp.Collaboration}
   ```

   ```elixir
   defmodule MyApp.Collaboration do
     @behaviour Issho.Policy

     @impl true
     def authorize(%Issho.Identity{key: user_id}, "schema:" <> id, action) do
       if MyApp.Schemas.allowed?(user_id, id, action), do: :ok, else: {:error, :forbidden}
     end
   end
   ```

   `action` is `:join` (open the canvas, see who is here), `:read`
   (receive the changes), `:write` (change it) or `:lock`. The policy is
   asked as each person opens the canvas, and again for each change, in
   both directions: a person whose access you take away stops seeing the
   changes, and `Issho.revoke(MyApp.Issho, topic, user_id)` takes them
   out of the room at once.

3. The hook, in the LiveView or its `live_session`:

   ```elixir
   live_session :default, on_mount: [Hakushi.Live] do
   ```

   (`Hakushi.Live` is Issho's hook, `Issho.Live`: a LiveView with either
   needs no other.)

## The room's document

The canvases of a topic share one document, the graph, with one process
in your cluster that puts the changes of everyone in order. The first
canvas to open it gives it its `graph`, `rules` and `on_change`; the
others get the graph as it is then.

Each change of each person goes to that process, which checks the rules,
applies it, asks `on_change` (once, whoever made it, with the graph
before and after it), and only then sends it to every canvas of the
topic. So `on_change` runs once for each change, and two people never
save over each other: the second change applies to the graph the first
one made. A change that no longer makes sense (an edge to a node someone
deleted a moment before) is refused, with the reason.

The document lasts while a canvas has it open, and a few seconds more,
so that a reload finds it. Your tables, which `on_change` writes, are
the truth: the next canvas to open the topic starts from the graph you
give it.

## People

`user` is a map with an `:id`, and a `:name`, a `:color` (any CSS
colour) and an `:avatar` (an image's URL) if you have them. A person with
no colour gets one of eight, by their id, the same everywhere. A person
with the canvas open in two tabs is one person, and does not see
themselves. Without a `user`, a canvas joins as someone anonymous.

The avatars of the others show in the corner of the canvas. Draw them
yourself with the `:person` slot, which gets a map with `"id"`,
`"name"`, `"color"` and `"avatar"`.

## Cursors and drags

Each person's cursor, the nodes they selected and the nodes they drag go
to the others as they move, in Issho's awareness frames: one frame of
what changed, about twenty times a second, whatever the number of people.
A node someone drags moves for everyone while they drag it, with their
name; it lands where they drop it when the room has the move.

## A cluster

The room's process is found from every node of a cluster (`:global`,
unless your Issho instance names another registry), and the PubSub must
reach every node, as Phoenix's does.

## The app's own changes

In the LiveView of the canvas, `Hakushi.Live.change/2`. From anywhere (a
job, another LiveView), `Hakushi.Issho.change(MyApp.Issho, topic,
change)`, while someone has the canvas open; it answers
`{:error, :not_running}` when no one has, and then you change your own
tables. `Hakushi.Issho.graph/2` reads the graph a room has.

## Agents

An agent works on a shared canvas as a person does, and the people see
it: its avatar in the corner, its pointer with its name, the node it
drags going with its pointer, its changes landing. `Hakushi.Issho.tools/0`
gives it the canvas's verbs, however it reaches your app:

| Tool | What it does |
|---|---|
| `read_canvas` | the nodes (place, size, data, group) and edges |
| `point_at` | moves its pointer to a node or a point, and selects nodes |
| `add_node` | a node of a type the canvas draws, at a place |
| `move_node` | drags a node to a place: the people see it go |
| `connect_nodes` | an edge, from a handle to a handle |
| `update_node` | a node's data, type or lock |
| `delete_items` | nodes, with their edges, and edges |

Its pointer goes to where it works and drags as a hand does, in a straight
line: only where it goes is sent, and each browser draws the way there
(the pointer, and the node it drags), so the people follow it. Others'
pointers glide the same way, which smooths a person's too. For changes
that land at once:

```elixir
config :hakushi, Hakushi.Issho, travel: false
```

It moves with Issho's motion (`Issho.Motion`): only when someone of the
room sees the canvas, within a tool call's time budget.

### Following, and the page

A click on someone's avatar, on the canvas or in the page's people list
(`Issho.Components.people/1`), follows them: the canvas shows what theirs
shows, or keeps an agent's pointer on the screen. A wheel, a press or a
key on the canvas stops following. On a page with Issho's pointers
(`Issho.Components.pointers/1`), they draw everyone's pointer on the
canvas too, at the same point of the canvas for each person, and one
pointer goes from the page onto the canvas and back.

A canvas that shows its people (its avatars) says whom it follows:
"Following Ada", with Stop, under the avatars, in their colour, and a ring
of it around the canvas. The look is Issho's, the same as its people
list's and every other block's on the page: the line carries Issho's
classes (`issho-following`, `issho-following-stop`) besides its own
(`.hakushi-following`, the ring `.hakushi-following-ring`), the canvas
carries `data-ui-following` while it follows, and Issho's properties, on
the page, restyle all of them at once:

```css
:root {
  --issho-following-background: #111827; /* the person's colour */
  --issho-following-text: #fff;
  --issho-following-ring: none;          /* a ring of the person's colour */
}
```

`--hakushi-follow-color` is the followed person's colour, for your own
rules; the words are the `following` and `stopFollowing` messages.

A canvas that should take no part in following, though the other blocks
of its room do, says so with `follow={false}`: its avatars are not
buttons, it shows no one followed, and its view stays its person's.

Its changes go the way of everyone's: the canvas's rules check them, and
your `on_change` is asked once for each. It works on a canvas someone has
open, whose first canvas gave the room its graph, rules and `on_change`.

Give them to your app's own model, through its API, with Issho's room
tools:

```elixir
tools = Issho.Tools.room() ++ Hakushi.Issho.tools()
ctx = Issho.Tool.Context.new(MyApp.Issho, assistant, on_behalf_of: current_user)

Issho.Tools.schemas(tools)                    # the tools of a request to the model
Issho.Tools.call(tools, name, input, ctx)     # each tool use in its answer
```

or serve the same tools to MCP clients (with `{:sake, "~> 0.4"}`):

```elixir
defmodule MyApp.MCP do
  use Issho.MCP,
    name: "my-app",
    version: "1.0.0",
    tools: Issho.Tools.room() ++ Hakushi.Issho.tools()
end
```

See Issho's agents guide for who an agent is, and for whom it acts.

The repository's development app serves them at `/mcp`. With `mix dev`
running and the schema open at http://localhost:4099, connect Claude Code
with `claude mcp add --transport http hakushi-dev http://localhost:4099/mcp`,
ask it to lay out the tables of `atelier:schema`, and watch.
