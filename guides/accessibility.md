# Accessibility

A canvas is a picture, and the hardest thing on the web to make usable
without one. Hakushi makes each part of it reachable and named, and says
what happens.

## The name of a canvas

Give each canvas a name: `label="The tables of the shop"`. The canvas
has the `application` role, so that a screen reader passes the keys to
it, with "Canvas" as its role description, in the canvas's language.

## Nodes

Each node is a `group` with "node" as its role description, named by
`node_label` (its data's `label` or `name`, or its id, unless you give
your own). When a node gets the focus, its description says its
connections: "2 connections: → users, ← invoices (paid by)".

The focus goes from node to node with Tab, and to the nearest node in a
direction with Alt and an arrow; a node that gets the focus comes into
view, culled or not. Enter goes into a node's fields and buttons, which
are the page's own, and Escape back to the node. See
[Navigation](navigation.md).

## Connecting without a pointer

C, on a focused node, starts an edge from it. The arrows go through the
nodes it may end on (by the same rules as a pointer's, nearest first),
each said as it comes ("Connect to users · id"), and Enter makes the
edge. Every edge a pointer can draw, the keyboard can.

## What is said

A live region says, politely:

* a selection ("users selected.", "3 selected.");
* a move ("Moved users.", "Moved 3 nodes.");
* a delete, a connection, a cancelled connection;
* a change the server refused, in its words;
* no connection to the server.

The words are the canvas's own (`Hakushi.Messages`), in the canvas's
locale.

## Handles

A handle has the `label` you give it, for the keyboard's connection
choices: give the handles of a row the row's name.

## The focus ring

The canvas and its nodes show a focus ring when the focus came from the
keyboard, and not after a click.

## Colour and motion

Selection is a ring, not a colour alone. With forced colours, the canvas
uses the system's; with reduced motion, nothing moves on its own. See
[Theming](theming.md).

## What is not done yet

The edges themselves do not take the focus: they are read through their
nodes, and deleted with the nodes or by a pointer. See
[Known limits](limits.md).
