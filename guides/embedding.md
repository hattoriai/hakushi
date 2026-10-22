# In a page

A canvas fills the box you give it. In a page that is the canvas (an
editor of diagrams), that is all; in a page that has other things, a
document, a card, a panel, the canvas is a part of it, and a few things
change.

## The embed frame

`canvas_embed/1` frames a canvas: a bar with its icon and title, the
items of its kits, your own actions, and a button that takes it full
screen and back.

```heex
<.canvas_embed
  title={@diagram.title}
  icon="database"
  subtitle="Database schema"
  for="diagram"
  kits={[Hakushi.Kits.Schema]}
  full={@full}
  on_full={JS.push("toggle_full")}
>
  <.canvas id="diagram" graph={@diagram.graph} kits={[Hakushi.Kits.Schema]} wheel={:scroll} refit minimap={@full} />
</.canvas_embed>
```

The frame takes the height of its parent (`--hakushi-embed-height`,
24rem, when the parent has none). It does not go full screen by itself:
`on_full` is yours, and `full` says which way its button goes. Your page
puts the frame in a layer over the page (a fixed element), or a Kotoba
embed does it for you (below). Its `:heading` slot replaces the title, as
a field that renames the canvas, and `readonly` leaves the kits' items
out.

## The wheel and the page

A canvas takes the wheel to pan, which, in a page that scrolls, stops the
page where the canvas is. `wheel={:scroll}` leaves the wheel to the page:
the page scrolls past the canvas, ⌘ or Ctrl and the wheel (and a pinch)
zoom it, and a drag of the paper pans it. On a touch screen, one finger
scrolls the page, two pan and zoom the canvas, and a node is still
dragged with one.

## A box that changes size

`refit` shows all of the nodes again when the canvas's box changes size:
an embed that goes full screen opens on the whole canvas, and comes back
to the whole of it in the page. Without it, the canvas keeps its view
when its box changes.

## In a Kotoba document

[Kotoba](https://github.com/hattoriai/kotoba) embeds your app's live
things in a document (its [Embeds](https://hexdocs.pm/kotoba/embeds.html)
guide). A canvas is one: the document keeps its kind and ref, and your
LiveView renders the frame and its canvas for it.

```heex
<.kotoba field={@form[:body]} id="doc" embeds />

<.kotoba_embeds for="doc" label="Canvas" icon="canvas" readonly={@reading}>
  <:embed :let={embed}>
    <% diagram = @diagrams[embed.ref] %>
    <.canvas_embed
      title={diagram.title}
      icon={hd(diagram.kits).icon()}
      for={"canvas-" <> embed.id}
      kits={diagram.kits}
      readonly={embed.readonly}
      full={embed.full}
      on_full={embed.toggle_full}
    >
      <.canvas
        id={"canvas-" <> embed.id}
        graph={diagram.graph}
        kits={diagram.kits}
        readonly={embed.readonly}
        on_change={&Diagrams.save(diagram, &1, &2)}
        wheel={:scroll}
        refit
        minimap={embed.full}
      />
    </.canvas_embed>
  </:embed>
  <:picker>
    <.kotoba_embed_option phx-click="new_diagram" phx-value-kit="schema" title="Database schema" />
  </:picker>
</.kotoba_embeds>
```

* Give the canvas an id of the embed's (`"canvas-" <> embed.id`): the same
  diagram can be in a document twice. Its document (`issho`'s `:document`)
  stays the diagram's: each copy has its own element id, and all of them are one
  canvas.
* The embed's `ref` is the person's input: whoever edits the document can
  put any ref there. Load what it shows as the diagram's own page does,
  with the viewer's permission (`Diagrams.get_for(user, embed.ref)`, not
  `@diagrams[embed.ref]` of every diagram), and render nothing, or its
  title, for a ref they may not see.
* Kotoba keeps the keys of an embed in it: Delete in the canvas deletes
  its nodes, not the embed.
* Full screen is Kotoba's (`embed.full`, `embed.toggle_full`): the same
  canvas goes into a layer over the page and comes back, and `refit`
  shows it whole there.
* A page that reads the document (`readonly`) shows the canvas read-only:
  people pan, zoom and go full screen, and change nothing.

### Shared, in a document

A canvas with `issho` in a document is shared in its own room, the
canvas's, whatever the document's room: everyone with the canvas open, in
the document or on its own page, is there, and sees the others' cursors,
changes and avatars.

```heex
<.canvas
  id={"canvas-" <> embed.id}
  graph={diagram.graph}
  issho={[instance: MyApp.Issho, document: "diagram:" <> diagram.id]}
  user={@current_user}
  readonly={embed.readonly}
  ...
/>
```

* The document's LiveView renders this canvas: the canvas's own page (a
  LiveView of its own) need not be open, and when it is, the two are one
  canvas, through the room.
* Define the canvas's document in your Issho policy
  (`Hakushi.Issho.document/2`, see
  [The room's document](collaboration.md#the-room-s-document)): its
  graph, rules and `on_change` are then the same whichever opens it first,
  its page or an embed. Without it, the first to open it gives them, and
  the embed's or the page's own are not used.
* Give it the same `user` as the document's editor (`Kotoba.Collab.token/3`)
  and Issho's lists: the person is one in every room of the page.
* On a page with Issho's pointers of the document's room, the canvas
  still draws its people: those pointers leave a block of another room to
  that room. Following someone in the document who goes into the canvas
  follows them on the canvas too.
* Full screen moves the canvas, as it is: it stays in its room, its
  people and its view.
* An embed that is deleted lets the canvas's room go; undo brings the
  canvas back, in its room again.
* A reader (`embed.readonly`) is a viewer of the canvas's room.

### Markdown

A document with a canvas in it exports as Markdown with the canvas's
diagram in it, and reads back to the same canvas: give Kotoba's renderer
the kits' Markdown (`Hakushi.Kit.to_markdown/2`), and its reader
`Hakushi.Kit.from_markdown/2`. See [Kits](kits.md).
