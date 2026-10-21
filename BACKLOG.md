# Backlog

Known gaps in Hakushi, each to become an issue. None is planned yet.

## Groups and frames

A node inside another (`parent`), which moves with it and stays in it: a
frame of a moodboard, a lane of a workflow, a schema of a database. A
drop into a group makes the node its child; the group grows to hold its
children.

## Automatic layout

Arrange the nodes by their edges: layered (left to right, top to bottom)
for workflows and schemas, a tree for mind maps. In a Web Worker, as one
`:move` change, so that it undoes. ELK is the best layered layout, under
the EPL-2.0 licence: an optional add-on, or a layout of our own for the
common cases.

## Edges

- Moving the end of an edge to another handle (a `:reconnect` change).
- Points of an edge of its own, which people drag.
- Edges that take the focus, for the keyboard and screen readers.
- An edge's label of HEEx (a `:edge_label` slot).

## Scale

- A spatial index (a grid of buckets) for culling, so that a pan of
  10,000 nodes has no slow frames.
- Nodes drawn as plain boxes when zoomed far out (level of detail).
- A canvas that sends the nodes near the view first, and the others as
  the view moves.

## Collaboration

- A lock on a node while someone drags it, as Masu locks a cell.
- Comments on a node, in threads, with a store of the app's.
- Following a person: the view moves with theirs.
- Presence across the pages of an app, not only one canvas.

## Export

The canvas as SVG and PNG, in the browser; the graph as JSON from the
controls.

## The installer

`mix hakushi.install`: the hook in `app.js` and the style sheet in
`app.css`, as the other libraries of the family have.

## Pages without LiveView

`mountHakushi()` for a read-only canvas in a controller's template.

## Together with the family

- Jumon: actions of the canvas in the palette ("Add a node", "Fit",
  "Go to node…").
- Kotoba: notes of rich text in nodes, edited in place.
- Masu: a grid of the nodes of a canvas, as an inspector.
