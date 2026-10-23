defmodule HakushiTest.ImagesLive do
  @moduledoc "A LiveView with a canvas of images (Hakushi.Kits.Images), for the image tests."
  use Phoenix.LiveView

  on_mount(Hakushi.Live)

  import Hakushi.Components

  alias Hakushi.Graph

  def graph do
    Graph.new(
      nodes: [
        %{
          id: "photo",
          type: "image",
          x: 0,
          y: 0,
          width: 400,
          height: 300,
          data: %{
            "url" => "/uploads/hakushi/2026/10/a-photo.png",
            "key" => "2026/10/a-photo.png",
            "thumb" => nil,
            "name" => "photo.png",
            "pixels" => [800, 600],
            "crop" => [0, 0, 1, 1],
            "alt" => "",
            "caption" => ""
          }
        },
        %{id: "frame", type: "frame", x: 600, y: 0, width: 400, height: 400, data: %{}}
      ]
    )
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       graph: graph(),
       readonly: params["readonly"] == "true",
       user: params["user"] && %{id: params["user"], name: String.capitalize(params["user"])},
       issho:
         params["live"] &&
           [instance: HakushiTest.Issho, document: "canvas:" <> params["live"]]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.canvas
      id="board"
      graph={@graph}
      kits={[Hakushi.Kits.Images]}
      readonly={@readonly}
      issho={@issho}
      user={@user}
    >
      <:node type="frame" group resizable><div class="frame"></div></:node>
    </.canvas>
    """
  end
end
