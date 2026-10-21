# Changelog

All notable changes to Hakushi are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Hakushi follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-21

The first release.

### Added

- `Hakushi.Components.canvas/1`: a canvas for LiveView, with nodes drawn
  by `:node` slots of your HEEx, sent as LiveView streams; edges drawn
  in SVG (bezier, smooth, step, straight; arrows, dots, labels,
  animated); paper of dots, lines or crosses; pan and zoom by wheel,
  trackpad, touch and keys; a minimap and controls.
- `handle/1`: where edges start and end, on any element of a node, with
  `type`, `accepts` and `max`; several handles with one id, of which an
  edge takes the nearest.
- Selection by click and box, dragging with helper lines and snapping,
  resizing, copy and paste, duplicate, delete, labels, and undo and redo
  of each person's own changes, checked on the server.
- `Hakushi.Graph`, `Hakushi.Node`, `Hakushi.Edge` and `Hakushi.Change`:
  the data of a canvas, and changes with their inverses.
- `Hakushi.Rules`: loops, duplicates and cycles, the same in the browser
  and on the server.
- `on_change`, the app's check of every change, where it saves it; a
  refused change taken back in the browser, with its reason.
- `canvas_item/1` and `new_node`: nodes dragged onto the canvas, or made
  with a double click.
- Shared canvases (`live`): `Hakushi.Room`, one process for each canvas
  that orders, checks and broadcasts the changes, registered with
  `:global`; people with their avatars, cursors, selections and drags.
- `Hakushi.Live`: the `on_mount` hook of a shared canvas, and the app's
  own changes (`Hakushi.Live.change/2`, `Hakushi.Room.change/2`).
- The keyboard: Tab between nodes, Alt and an arrow to the nearest node,
  the arrows to move, C to connect, Enter into a node; a live region for
  screen readers.
- Culling of the nodes and edges far from the screen.
- `Hakushi.Graph.Type`, a canvas in one column of the database.
- `Hakushi.Test`, for `Phoenix.LiveViewTest`.
- `Hakushi.Messages`, in English, Portuguese, Spanish, French, German and
  Japanese.
- `hakushi.css` and the Sumi theme, `hakushi-sumi.css`.

[0.1.0]: https://github.com/hattoriai/hakushi/releases/tag/v0.1.0
