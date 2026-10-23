# Theming

Every colour, size, radius and font of a canvas comes from a
`--hakushi-*` custom property. Set them on `.hakushi` (or higher):

```css
.hakushi {
  --hakushi-accent: #0f766e;
  --hakushi-background: #fafaf9;
}
```

The defaults have no specificity, so a value set on `:root`, on an
ancestor or on `.hakushi` itself wins. They are Masu's, Kotoba's and
Koyomi's own, so that a page with them all looks like one thing.

Your nodes are your HEEx, styled as the rest of your app: these
properties are the canvas's own parts (the paper, the edges, the
handles, the controls), and the default node.

## The properties

| Property | Is |
| --- | --- |
| `--hakushi-font`, `--hakushi-font-size` | the type of the canvas's own words |
| `--hakushi-text`, `--hakushi-muted` | text, and quieter text |
| `--hakushi-background` | the paper |
| `--hakushi-pattern`, `--hakushi-pattern-strong` | the pattern of the paper: the dots and crosses, and the lines (the strong one every five squares) |
| `--hakushi-surface`, `--hakushi-border` | the controls, the minimap and the default node |
| `--hakushi-accent`, `--hakushi-accent-text` | the focus, the selection, the edge being drawn |
| `--hakushi-node-background`, `--hakushi-node-border`, `--hakushi-node-radius`, `--hakushi-node-shadow` | the default node; the radius is also the selection ring's |
| `--hakushi-selection` | the ring of a selected node, and the resize handles |
| `--hakushi-handle-size`, `--hakushi-handle`, `--hakushi-handle-border` | the handles |
| `--hakushi-edge`, `--hakushi-edge-width`, `--hakushi-edge-selected`, `--hakushi-edge-label` | the edges, a selected one, and the background of the labels |
| `--hakushi-guide`, `--hakushi-box` | the helper lines, and the box that selects |
| `--hakushi-control`, `--hakushi-control-shadow` | the controls and the minimap |
| `--hakushi-minimap-node`, `--hakushi-minimap-mask` | the nodes in the minimap, and the veil outside the view |
| `--hakushi-radius`, `--hakushi-transition` | the controls' radius, and the speed of the small transitions |
| `--hakushi-embed-height` | the height of an embed frame (`canvas_embed/1`) whose parent has none, `24rem` |

The kits have their own: Ink's `--hakushi-ink-<colour>` and
`--hakushi-highlighter-opacity`; Shapes' `--hakushi-shape-<colour>` (ink,
gray, blue, green, yellow, red, violet, and your own), whose fills are a
tint of them on the surface (`--hakushi-shape-tint`, 16%).

`--hakushi-person` is a person's colour, on their avatar, their cursor
and the ring of the nodes they selected or drag.

## The paper

`background` is `:dots` (the default), `:lines` (graph paper, a stronger
line every five squares), `:cross` or `:none`, or a paper of your own,
and `grid` the size of a square at 100% (20 pixels unless set). The
pattern scales and moves with the view.

### People choose the paper

`papers` puts a picker in the controls: the papers people choose from,
and the size of their squares (small, medium, large: 10, 20 and 40
pixels). It is off unless you give it.

```heex
<.canvas id="board" graph={@graph} papers={true} on_change={&save/2} />
<.canvas id="board" graph={@graph} papers={[:dots, :lines, %{name: "iso", label: "Isometric"}]} />
```

The paper people choose is the graph's (`Hakushi.Graph`'s `paper`), and
choosing it is a change as any other (`Hakushi.Change.paper/1`): it goes
through `on_change`, which saves it with the graph, ⌘Z takes it back,
and on a shared canvas everyone sees it. It wins over the canvas's
`background` and `grid` until it is taken back. Your app changes it the
same way, with `Hakushi.Live.change/2` or `Hakushi.Issho.change/4`:

```elixir
Hakushi.Live.change("board", Hakushi.Change.paper(background: :lines, grid: 20))
```

### A paper of your own

A paper is a pattern of CSS, on the canvas's paper and on its swatch in
the picker. Draw it with the canvas's properties: `--hakushi-grid-size`
(a square, at the zoom), `--hakushi-pattern` and
`--hakushi-pattern-strong`; the canvas moves it with the view.

```css
.hakushi[data-background="iso"] .hakushi-background,
.hakushi-paper-swatch[data-background="iso"] {
  background: var(--hakushi-pattern-strong);
  mask-image: url("data:image/svg+xml,...");
  mask-size: calc(var(--hakushi-grid-size) * 1.732) var(--hakushi-grid-size);
}
```

Name it in `background` (`background="iso"`) or in `papers`. The
development app's moodboard has one, isometric (see `dev.exs`); see
`Hakushi.Paper`.

An exported image has no paper unless asked: `Hakushi.Live.export/2`
with `paper: true`, or the canvas's `download({paper: true})`.

## Parts of the canvas

The canvas marks its states with attributes, for your own CSS:

* `.hakushi-node[data-ui-selected]`, a selected node;
* `.hakushi-node[data-ui-peer]`, a node another person selected or drags;
* `.hakushi[data-ui-connecting]`, an edge being drawn, and
  `.hakushi-handle[data-ui-valid]`, a handle it may end on;
* `.hakushi[data-ui-dragging]`, nodes being dragged;
* `.hakushi[data-ui-zoom="far"]`, a zoom under 50%, where the handles
  hide;
* `.hakushi[data-ui-readonly]`.

The handles of a node can show only on hover:

```css
.my-node .hakushi-handle { opacity: 0; }
.my-node:hover .hakushi-handle,
.hakushi[data-ui-connecting] .hakushi-handle { opacity: 1; }
```

## Dark mode

The canvas follows the app's own switch: a `dark` class or
`data-theme="dark"` on an ancestor, as the `<html>` of Phoenix's and
Tailwind's apps has. A page that follows the system's setting maps its
media query to one of them. Set the properties for dark yourself under
the same selectors.

## The Sumi theme

`hakushi-sumi.css` sets the properties from the Sumi tokens of the page
(Sumi is the design system of Hattori AI), and from a Sumi palette of its
own on a page without them; it follows the Sumi themes' light and dark,
or `data-theme`, or the system's setting. Load it after `hakushi.css`:

```css
@import "../../deps/hakushi/priv/static/hakushi.css";
@import "../../deps/hakushi/priv/static/hakushi-sumi.css";
```

## Forced colours and motion

With forced colours (Windows' high contrast), the edges, handles and
selection use the system's colours. With reduced motion, nothing
transitions and the animated edges stand still.
