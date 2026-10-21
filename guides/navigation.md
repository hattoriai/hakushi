# Navigation

How people move about a canvas, and change it, with a mouse, a trackpad,
a touch screen and the keyboard. (⌘ is Ctrl outside Apple's systems.)

## The view

| | |
| --- | --- |
| Pan | the wheel or two fingers on a trackpad; Space and a drag; the middle button and a drag; one finger on a touch screen; the arrow keys with nothing selected |
| Zoom | ⌘ (or Ctrl) and the wheel, at the pointer; a pinch on a trackpad or a touch screen; + and -; the controls |
| Fit | ⇧1, or the fit button: every node on the screen, at 100% at most |
| 100% | ⇧0, ⌘0, or a click on the zoom in the controls |
| Overview | a click or a drag on the minimap moves the view there |

`wheel={:zoom}` makes the wheel zoom, as a map does. `wheel={:scroll}`
leaves the wheel to the page, for a canvas in a page that scrolls: ⌘ or
Ctrl and the wheel, or a pinch, zoom, and a drag pans (see
[In a page](embedding.md)).

## Selecting

A click on a node or an edge selects it. Shift, ⌘ or Ctrl and a click
adds it or takes it away. A drag on the paper draws a box that selects
what it touches (Shift keeps the selection). ⌘A selects every node, and
Escape nothing.

## Changing

| | |
| --- | --- |
| Move | drag a node (and every selected node with it); the helper lines line it up with the nodes near it, and Alt drags without them; the arrow keys move the selection by one (ten with Shift, a square of the grid on a canvas that snaps) |
| Connect | drag from a handle to a handle; or C, then the arrows, then Enter |
| Move an end | select an edge, and drag one of its ends to another handle |
| Group | drop a node on a group to put it in; drag it off to take it out |
| Tidy up | ⇧L, or the button of the controls: the selection when two or more nodes are selected, else every node |
| Download | the button of the controls: the canvas as a PNG |
| Resize | the corners of a selected node of a `resizable` slot |
| Delete | Delete or Backspace |
| Copy, cut, paste | ⌘C, ⌘X, ⌘V (at the pointer, or next to what it copies) |
| Duplicate | ⌘D |
| Undo, redo | ⌘Z, ⇧⌘Z or ⌘Y |
| Label an edge | a double click on it, then Enter (or Escape) |
| A new node | drag an item onto the canvas, or Enter on it; a double click on the paper |

## The keyboard alone

The canvas is one stop of Tab. From there:

* Tab and Shift+Tab go from node to node, in their order, and on past
  the last one out of the canvas; the focused node is selected and comes
  into view;
* Alt and an arrow go to the nearest node that way;
* Enter goes into the node, to its first field or button, and Escape
  back out to the node;
* C starts an edge from the focused node: the arrows (or Tab) go through
  the nodes it may end on, nearest first, Enter makes it, Escape does
  not.
