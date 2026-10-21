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

`--hakushi-person` is a person's colour, on their avatar, their cursor
and the ring of the nodes they selected or drag.

## The paper

`background` is `:dots` (the default), `:lines` (graph paper, a stronger
line every five squares), `:cross` or `:none`, and `grid` the size of a
square at 100% (20 pixels unless set). The pattern scales and moves with
the view.

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
