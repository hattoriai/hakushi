# Known limits

What Hakushi does not do yet, or does with a cost to know.

## Browsers

The canvas needs a browser with `ResizeObserver`, pointer events and
CSS `translate`: every browser of the last few years. It is tested in
Chromium, Firefox and WebKit.

## How many nodes

The nodes are your HEEx in the page, which is what lets them be anything
(a form, a table, your components). The canvas lays out only the nodes
near the screen (from 150 nodes on), paints only the edges near it, and
moves the edges as one layer, so a pan does not repaint them.

Measured with the development app's `/scale` page, in headless Chromium with software rendering on a cloud machine (a laptop with a GPU does better):

| | 300 nodes | 2,000 nodes | 10,000 nodes |
| --- | --- | --- | --- |
| The canvas's own work in a frame of a pan, the median | 0.8 ms | 0.3 ms | 0.3 ms |
| Frames of a pan, the median | 16.7 ms | 16.7 ms | 16.7 ms |
| The slowest frames of a pan (the 95th percentile) | 17 ms | 85 ms | 300 to 450 ms |

The slow frames are the frames where the canvas lays out the nodes that
come into view, every half a screen of a pan: at 10,000 nodes it looks
at each node to find them. A spatial index will make them cheaper (see
the backlog).

The server sends every node when the canvas opens, in the page and again
when the LiveView connects, as LiveView does: the 10,000 nodes of
`/scale` (a label and two handles each, and an edge) are about 6 MB of
HTML. Each change after that sends the nodes it touches.

## Nodes on the server

A node draws from itself (its data), and draws again when it changes.
A node whose look depends on the LiveView's other assigns does not
follow them: put what it shows in its data.

## The handles are the browser's

The server does not know the handles (they are in each node's HEEx). The
rules of `type`, `accepts` and `max` are the browser's; check what an
edge means in `on_change`. The rules of the graph (`loops`,
`duplicates`, `cycles`) are checked on both.

## A shared canvas

* The room keeps the graph in memory while anyone has the canvas open.
  A change made to your database by other means (a migration, a script)
  does not reach an open room: make it through `Hakushi.Issho.change/4`.
* `on_change` runs in the room's process: a slow `on_change` makes the
  others' changes wait for it.
* The room is registered with `:global` (unless your Issho instance
  names another registry); in a split cluster, each side may start its
  own.

## Export

An image of the canvas is the page's HTML in an SVG. The browser draws it
without what it may not read: a style sheet or a font of another origin
(a font from a CDN falls back to the next font of the stack), and an
image of another origin, which Chromium draws but Safari and Firefox may
not put in a PNG; the download is then the SVG. A PNG has at most 16,384
pixels a side: a larger canvas is drawn at a smaller scale.

## Layout

The tidy up is a layered layout, for graphs that flow (workflows,
schemas, trees). It does not route edges around nodes, and it lays out a
group as one box without arranging what is in it.

## Not yet

* An edge's points of your own, which people drag.
* Edges that take the focus.
* Pages without LiveView.

See the [backlog](https://github.com/hattoriai/hakushi/blob/main/BACKLOG.md).
