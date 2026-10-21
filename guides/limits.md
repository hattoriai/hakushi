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
  does not reach an open room: make it through `Hakushi.Room.change/2`.
* `on_change` runs in the room's process: a slow `on_change` makes the
  others' changes wait for it.
* The room is registered with `:global`; in a split cluster, each side
  may start its own.

## Not yet

* Groups: nodes inside a node, which move with it.
* Automatic layout.
* An edge's points of your own, and an edge moved to another handle by
  dragging its end.
* Edges that take the focus.
* An export of the canvas as an image.
* Pages without LiveView.

See the [backlog](https://github.com/hattoriai/hakushi/blob/main/BACKLOG.md).
