# Backlog

Known gaps in Hakushi, each to become an issue. None is planned yet.

## Edges

- Points of an edge of its own, which people drag.
- Edges that take the focus, for the keyboard and screen readers.
- An edge's label of HEEx (a `:edge_label` slot).

## Scale

- Nodes drawn as plain boxes when zoomed far out (level of detail).
- A canvas that sends the nodes near the view first, and the others as
  the view moves.

## Collaboration

- A lock on a node while someone drags it, as Masu locks a cell.
- Comments on a node, in threads, with a store of the app's.
- Following a person: the view moves with theirs.
- Presence across the pages of an app, not only one canvas.

## Pages without LiveView

`mountHakushi()` for a read-only canvas in a controller's template.

## Layout

- Edges routed around the nodes in their way.
- A layout of the nodes in a group, within it.
- A force-directed layout, for graphs that do not flow (a mind map, a
  network).

## Together with the family

- Jumon: actions of the canvas in the palette ("Add a node", "Fit",
  "Go to node…").
- Kotoba: notes of rich text in nodes, edited in place.
- Masu: a grid of the nodes of a canvas, as an inspector.
