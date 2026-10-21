defmodule Hakushi do
  @moduledoc """
  Hakushi (白紙, "a blank sheet of paper") is a canvas for Phoenix: an
  endless sheet that people pan and zoom, with nodes of your own HEEx on
  it, joined by edges.

      <.canvas id="flow" graph={@graph} on_change={&Flows.change(&1, &2, @flow)}>
        <:node type="step" :let={node}>
          <div class="step">
            <.handle kind={:target} side={:left} />
            {node.data.title}
            <.handle kind={:source} side={:right} />
          </div>
        </:node>
      </.canvas>

  * `Hakushi.Components` - the canvas, its handles, and the items people
    drag onto it.
  * `Hakushi.Graph`, `Hakushi.Node`, `Hakushi.Edge` - the data of a
    canvas.
  * `Hakushi.Change` - what people (and the app) do to it, each checked by
    `Hakushi.Rules` and the app's `on_change` before anyone sees it.
  * `Hakushi.Room` and `Hakushi.Live` - a canvas shared by everyone on a
    topic.
  * `Hakushi.Graph.Type` - a canvas in one column of the database.
  * `Hakushi.Test` - the canvas in `Phoenix.LiveViewTest`.

  Start with the [Quickstart](quickstart.md).
  """
end
