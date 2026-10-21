defmodule Hakushi.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Shared canvases run in Issho's processes; Hakushi starts none of its own.
    children = []

    Supervisor.start_link(children, strategy: :one_for_one, name: Hakushi.Supervisor)
  end
end
