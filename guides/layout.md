# Layout and export

## Tidy up

The tidy up button of the controls, or ⇧L, lays the nodes out in layers
along their edges: each node after the nodes its edges come from, the
nodes of a layer ordered to cross as few edges as it can, and each one
level with its neighbours.

```heex
<.canvas id="flow" graph={@graph} layout={:down}>
```

`layout` is the way of the layers: `:right` (the default, as a workflow
reads) or `:down` (as an org chart does).

* With two or more nodes selected, it lays out those, and the others
  stay.
* A group is laid out as one box, with what is in it; locked nodes stay.
* The parts of a canvas that no edge joins are laid out apart, side by
  side.
* The nodes glide to their places (at once with reduced motion), and
  keep the top left corner they had.

The new places are one `:move` change, as a drag's: the server checks it,
`on_change` saves it, everyone on a shared canvas sees it, and ⌘Z undoes
it in one step.

The app can tidy up too, from the canvas's LiveView:

```elixir
Hakushi.Live.layout("flow", direction: :down)
```

The layout runs in the person's browser, which knows the size of each
node as it is drawn.

## Export

The download button of the controls saves the canvas as a PNG: every node
and edge, not only those on the screen, at twice its size, on the paper's
colour. `export={false}` takes the button away.

From the LiveView, in the person's browser:

```elixir
Hakushi.Live.export("flow", format: :svg, filename: "invoice-flow")
```

And from your own JavaScript, as a `Blob`:

```js
import { canvasOf } from "hakushi"

const blob = await canvasOf(document.getElementById("flow")).exportImage({ format: "png", scale: 2, padding: 32, transparent: false })
```

The image is the nodes as the page draws them (your HEEx, with the
page's style sheets) and the edges, without the handles. Fonts of the
page's own origin are put in the image; a font, a style sheet or an
image of another origin may not be, and a browser that will not draw
such an image to a PNG gives the SVG instead (see
[Known limits](limits.md)).
