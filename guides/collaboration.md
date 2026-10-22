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
  issho={[instance: MyApp.Issho, document: "schema:#{@schema.id}"]}
  user={%{id: @current_user.id, name: @current_user.name}}
>
```

`issho` takes the keys of every component of an Issho page (`Issho.Join`,
the same for Kotoba's editor and Masu's grid): `:instance` and
`:document` (required: the canvas's document; its room is the part
before the first `"/"`, so the blocks of a page whose documents share a
room share its people); `:can`, `:read` for a viewer (as `readonly`);
`:people`, `false` to hide the canvas's avatars on a page that lists the
room's people (`Issho.Components.people/1`); `:follow`, `false` for a
canvas that takes no part in following; `:on_behalf_of` and `:claims`,
for your policy. Any other key raises.

## Setting up

1. Issho in your dependencies:

   ```elixir
   {:issho, "~> 0.3"}
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
in your cluster that puts the changes of everyone in order. It runs while
anyone has the canvas open, wherever: on its own page, embedded in a
document of another page (see [In a page](embedding.md)), or for an
agent. Nobody needs to be on the canvas's page for the others to share it.

What the document is (its graph, rules and `on_change`) comes from your
Issho policy when it says, whoever opens it first:

```elixir
defmodule MyApp.Collaboration do
  @behaviour Issho.Policy

  @impl true
  def document(_who, "schema:" <> id) do
    schema = MyApp.Schemas.get!(id)
    Hakushi.Issho.document(schema.graph, rules: [cycles: false], on_change: &MyApp.Schemas.change(schema, &1, &2))
  end
end
```

Define it there when the canvas opens in more than one place, or for
agents: it is then the same document whichever opens it first, and an
agent works on it with no browser at all. Without it, the first canvas to
open the topic gives it its `graph`, `rules` and `on_change`, the others
get the graph as it is then, and their own `rules` and `on_change` are not
used: two places that pass different ones would differ by who came first.

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

`user` is your user: a struct of yours for which you implement
`Issho.Actor` (its key, `"user:4"`, and what others see of it), or a map
with an `:id`, and a `:name`, a `:color` (any CSS colour) and an
`:avatar` (an image's URL) if you have them. Give the canvas the same
user as your other blocks (a Kotoba editor, Issho's people list), and
the person is one person in all of them. A person with no colour gets
one of Issho's eight (`--issho-person-1` to `-8`, the same as in Issho's
lists), else one of Hakushi's, by their key. A person with the canvas
open in two tabs is one person, and does not see themselves. Without a
`user`, a canvas joins as someone anonymous.

A read-only canvas (`readonly`, or `issho`'s `can: :read`) is a viewer of the room: Issho's lists
show them viewing, their cursor still goes to the others, and the room
takes no change from them.

The avatars of the others show in the corner of the canvas (not with
`people: false`). Draw them yourself with the `:person` slot, which gets
a map with `"id"`, `"name"`, `"color"` and `"avatar"`.

## Cursors and drags

Each person's cursor, the nodes they selected and the nodes they drag go
to the others as they move, in Issho's awareness frames: one frame of
what changed, about twenty times a second, whatever the number of people.
A node someone drags moves for everyone while they drag it, with their
name; it lands where they drop it when the room has the move.

They are the canvas's own keys of the person's state, under the canvas's
document (`"blocks"`, see `Issho.Awareness`): `cursor`, `selected`,
`viewport` and `dragging`. Issho's own keys (`place`, `pointer`, `view`,
`motion`) stay Issho's, so the other blocks of the page never collide
with the canvas's.

## A place on the canvas

Where someone is on the canvas, in a pointer, in an agent's motion or in
what your app keeps, is a place of the canvas's document, in the
canvas's own terms (never screen pixels, as each person has their own
pan and zoom). Its format is part of Hakushi's API, and only grows
(`Hakushi.Issho.Place`):

```elixir
%{"point" => [x, y]}          # a point, in the canvas's coordinates
%{"node" => node_id}          # a node
%{"nodes" => [node_id, ...]}  # nodes (the first is where it is drawn)
```

## A cluster

The room's process is found from every node of a cluster (`:global`,
unless your Issho instance names another registry), and the PubSub must
reach every node, as Phoenix's does.

## The app's own changes

In the LiveView of the canvas, `Hakushi.Live.change/2`. From anywhere (a
job, another LiveView), `Hakushi.Issho.change(MyApp.Issho, document,
change, author: current_user)`, while someone has the canvas open; it
answers `{:error, :not_running}` when no one has, and then you change
your own tables. `:author` is a key (`"server"`, the default) or your
actor: `on_change` gets it as `by`, as everyone's. `Hakushi.Issho.graph/2` reads the graph a room has.

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

### A canvas in a page of another room

A canvas shared in its own room, in a page of another room (a canvas
embedded in a Kotoba document): its people are its room's, wherever they
are. Someone reading the document sees the cursor of someone on the
canvas's own page, and the other way round, and the same canvas's
changes, avatars and following. The page's pointers, of the document's
room, draw no one on the canvas (see Issho's guide): the canvas draws its
people, except those whom Issho's pointers of its own room draw (on the
canvas's own page, when it has them).

* Following someone into the canvas, from the page's people list, follows
  them on the canvas too; following someone from the canvas's avatars
  brings the canvas into view, once, when it is off the screen.
* A canvas in a page twice (the same canvas, two embeds) is one person in
  the room: the copy they use (their pointer, a press, the focus) says
  where they are, and the other copies say nothing.
* A canvas that goes while its LiveView stays (an embed deleted from the
  document) lets its room go: the LiveView leaves the room with its last
  canvas there, and the others see the person go.

See [In a page](embedding.md).

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
of its room do, says so with `issho`'s `follow: false`: its avatars are not
buttons, it shows no one followed, and its view stays its person's.

Its changes go the way of everyone's: the canvas's rules check them, and
your `on_change` is asked once for each. A canvas no one has open is the
document your policy defines for it (`Hakushi.Issho.document/2`, see
[The room's document](#the-room-s-document)): the agent opens it from
there, with no browser at all, and people who open the canvas later see
its changes. Without it, the agent works only on a canvas someone has
open.

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
