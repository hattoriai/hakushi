{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: HakushiTest.PubSub)
{:ok, _pid} = HakushiTest.Endpoint.start_link()

# The Issho instance of the shared canvases: everyone may do everything.
defmodule HakushiTest.Policy do
  @moduledoc false
  @behaviour Issho.Policy
  @impl true
  def authorize(_identity, _room, _action), do: :ok
end

{:ok, _pid} =
  Issho.start_link(
    name: HakushiTest.Issho,
    pubsub: HakushiTest.PubSub,
    policy: HakushiTest.Policy,
    secret_key_base: String.duplicate("hakushi-test-secret-key-base-", 3),
    ttl: 50,
    awareness_interval: 5
  )

ExUnit.start()
