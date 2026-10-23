# Upgrading

## To Hakushi 0.5

Update `{:hakushi, "~> 0.5"}`. A canvas's code stays as it was, with two
things to know:

* The Images kit takes Storehouse 0.2: update `{:storehouse, "~> 0.2"}`
  if your app uses it.
* Tidy up packs the parts of a graph that no edge joins in rows, where it
  laid them out in one line: a canvas of many such parts tidies up more
  compactly than before.

What is new is opt-in: the `:force` and `:grid` layouts and the menu of
ways to tidy up, `readonly={:arrange}`, `tidy`, `fit={:readable}`, and in
the Schema kit, families of types and stubs of other schemas' tables. See
[Layout and export](layout.md) and [Kits](kits.md).

## To Hakushi 0.4, on Issho 0.4

Update `{:hakushi, "~> 0.4"}`. Shared canvases now run on [Issho](https://hex.pm/packages/issho) 0.4:
`{:issho, "~> 0.4.2"}`. Nothing else changes in your code: the canvas, its
document, `Hakushi.Issho.change/4` and the agents' tools are as they
were. What is new is Issho's, and the canvas's part in it:

* Each change of a shared canvas is an event of its room (`canvas.added`,
  `canvas.moved`, ...): agents wait for them, and your app hears them.
  See [Events](collaboration.md#events).
* Issho's comments go on a canvas's nodes, said by name with
  `Hakushi.Issho.Place.label/3`. See [Comments](collaboration.md#comments).
* An agent that a person paused or stopped changes nothing on the
  canvas, and is told why.

If you read Issho's processes yourself: a participant is now a state
machine, so `:sys.get_state/1` of one is `{state, data}` (see Issho's
changelog).

## To Hakushi 0.3

Hakushi 0.3 runs on [Issho](https://hex.pm/packages/issho) 0.3: the canvas
is a block of an Issho page, its agents move with Issho's motion, and
following someone is the room's. A canvas that is not shared needs nothing.

### What changes

| 0.2 | 0.3 |
| --- | --- |
| `{:issho, "~> 0.2"}` | `{:issho, "~> 0.3"}` |
| an agent's moves were the canvas's own | they are Issho's motion: only when someone sees the canvas, within a tool call's budget |
| the canvas drew every cursor on it | on a page with Issho's pointers, they draw everyone's pointer on the canvas too, at the same point of the canvas for each person; alone, the canvas draws its own |
| the avatars were images | they are buttons that follow someone, in the room |
| `live={{MyApp.Issho, topic}}` | `issho={[instance: MyApp.Issho, document: topic]}`: the keys of every component (`Issho.Join`), with `can:`, `people:` and `follow:` |
| `follow={false}` | `issho={[..., follow: false]}` |
| `on_change`'s `user` (`%{id, name}`, agents named "agent") | `by`, an `Issho.Identity`: the person, the agent and whom it acts for, or the server (`user` stays, for now) |
| `Hakushi.Issho.change(instance, topic, change)` (author `"app"`) | `Hakushi.Issho.change(instance, document, change_or_changes, author: ...)` (author `"server"` unless given) |
| the canvas's `cursor`, `selected`, `viewport` and `dragging` at the top of a person's state | under the canvas's document, in `"blocks"` |

### Steps

1. **Update** `{:hakushi, "~> 0.3"}` and `{:issho, "~> 0.3"}`.
2. **On a page of several blocks**, add Issho's pointers and people list
   (`Issho.Components.pointers/1`, `Issho.Components.people/1`): one
   pointer for each person across the page, the canvas included, and
   following from the page.
3. **Join with `issho`.** `live` and `follow` raise with what to write
   instead:

   ```diff
   -<.canvas id="schema" graph={@graph} live={{MyApp.Issho, "schema:42"}} follow={false} user={@user} />
   +<.canvas id="schema" graph={@graph} issho={[instance: MyApp.Issho, document: "schema:42", follow: false]} user={@user} />
   ```
4. **In `on_change`**, read `by` rather than `user`. On a shared canvas it
   is an `Issho.Identity` (`by.key`, `by.kind`, `by.on_behalf_of`).
5. **If you read a person's canvas state** (in an Issho room of your
   own), read it under the canvas's document:
   `Issho.Awareness.block(state, document)`.
6. **If you styled `.hakushi-person`**, it is a `<button>` now, with
   `aria-pressed` on the one followed.
