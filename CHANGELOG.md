# Changelog

All notable changes to Hakushi are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Hakushi follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-10-21

On Issho 0.3: the canvas is a block of an Issho page, agents move with
Issho's motion, and following is the room's.

### Changed (breaking)

- Requires `{:issho, "~> 0.3"}`.
- An agent moves with `Issho.Motion`: only when someone of the room sees
  the canvas, within a tool call's time budget (Hakushi's `travel` still
  turns it off for the canvas's agents, Issho's for every component).
- On a page with Issho's pointers (`Issho.Components.pointers/1`), they
  draw everyone's pointer on the canvas too: the canvas says where its
  points and nodes are on the screen (Issho's `locate`) and which point is
  under a pointer (`point`), so a pointer goes from the page onto the
  canvas and back as one, and each person sees it on the same point of
  the canvas, however theirs is panned. Alone on a page, the canvas draws
  its people's cursors itself, as before.
- The avatars are buttons that follow someone (`data-issho-follow-control`).

### Added

- Following someone, from the canvas's avatars or the page's people list:
  the canvas shows what they show (their viewport, sent with their cursor
  as `view`), or keeps an agent's pointer on the screen. A wheel, a press
  or a key on the canvas stops following.

- An agent's pointer travels as a hand does, in a straight line, and the
  node it drags goes with it: only where it goes is sent (once for a
  move, once for a drag, rather than a stream of frames), each browser
  draws the way there, and the agent waits as long as that takes before
  its change lands. `config :hakushi, Hakushi.Issho, travel: false` for
  changes that land at once.
- Others' pointers and the nodes they drag glide to each new place,
  longer the farther they go (up to 400ms; none with reduced motion), in
  the canvas's coordinates, so a pan or a zoom on the way keeps them
  right; a person's pointer is smoother for it.

### Fixed

- A canvas of many nodes mounts in linear time: the nodes are all measured
  before any is placed, rather than the page being laid out again for each
  node (seconds for two thousand nodes in Safari).
- A pan paints nothing again: the paper moves as a layer, by less than a
  period of its pattern, and the world is a layer while a pan goes on.
- A pan of a large canvas keeps its frames: a node that comes back into
  view is not news (it culled every node again on the next frame, redrew
  the minimap and the edges), an edge's path is written only when it
  changes, a node another person has selected is redrawn without laying
  out the canvas again, and in WebKit the edges are painted with the
  world rather than as a layer of their own, which cost more on each
  frame.

## [0.2.0] - 2026-10-21

Agents on shared canvases, on Issho 0.2.

### Changed

- Shared canvases need `{:issho, "~> 0.2"}`.

### Added

- Agents on shared canvases: `Hakushi.Issho.tools/0`, tools an agent
  uses as a person uses the canvas, however it reaches the app (its own
  model through an API with Issho's `Issho.Tools`, or MCP with
  `Issho.MCP`): read it, point (the people see its pointer, with its
  name), add nodes, drag them (they see the node go), connect them,
  change and delete them, through the canvas's rules and its
  `on_change`.
- `Hakushi.Issho.document/2`: a shared canvas's document for your Issho
  policy's `document/2`, so that an agent works on a board no one has
  open in a browser, through the canvas's rules and `on_change`.
- A shared canvas names its document for Issho's page layer
  (`data-issho-doc`) and draws its people's cursors itself
  (`data-issho-cursor="own"`); its awareness merges into the LiveView's
  session, whose other components keep their keys.

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
  with a double click; in a group, when dropped on one.
- Groups (`group` on a `:node` slot, a node's `parent`): nodes that hold
  others, which move, copy and go with them; a drop on a group puts a node
  in it, a drag off takes it out, in one `:move` change.
- Edges whose ends people drag to other handles: the `:reconnect` change,
  checked by the rules.
- A tidy up (⇧L, the controls, `Hakushi.Live.layout/2`): a layered layout
  of the selection or of every node, left to right or top to bottom, as one
  change.
- The canvas as an image: a PNG or an SVG of every node and edge (the
  controls, `Hakushi.Live.export/2`, `exportImage()` in JavaScript).
- `mix hakushi.install`: the hook in `app.js` and the style sheet in
  `app.css`.
- Shared canvases (`live={{MyApp.Issho, topic}}`) on
  [Issho](https://github.com/hattoriai/issho): each canvas of a topic is
  a session of one Issho room, whose document is the graph
  (`Hakushi.Issho`), with one process in the cluster that orders, checks
  and sends the changes; `on_change` once for each change; an Issho
  policy for who may open, read and change each canvas; people with
  their avatars, cursors, selections and drags.
- `Hakushi.Live`: the `on_mount` hook of a shared canvas (Issho's), and
  the app's own changes (`Hakushi.Live.change/2`,
  `Hakushi.Issho.change/3`, `Hakushi.Issho.graph/2`).
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
