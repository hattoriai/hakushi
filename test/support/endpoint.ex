defmodule HakushiTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule HakushiTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the canvas tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :hakushi

  plug(Plug.Session, store: :cookie, key: "_hakushi_test", signing_salt: "hakushi-test")
  plug(HakushiTest.Router)
end
