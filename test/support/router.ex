defmodule HakushiTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)
    live("/", HakushiTest.CanvasLive)
    live("/kits", HakushiTest.KitsLive)
  end
end
