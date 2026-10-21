{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: HakushiTest.PubSub)
{:ok, _pid} = HakushiTest.Endpoint.start_link()

# The Issho instance of the shared canvases: everyone may do everything.
defmodule HakushiTest.Policy do
  @moduledoc false
  @behaviour Issho.Policy
  @impl true
  def authorize(_identity, _room, _action), do: :ok

  # A board an agent opens before anyone has it in a browser: its graph
  # from the app, and its changes to the app (here, to the test that waits
  # for them, named in the room).
  @impl true
  def document(_identity, "board:" <> test) do
    graph = Hakushi.Graph.new(nodes: [%{id: "first", x: 0, y: 0, data: %{label: "First"}}])

    Hakushi.Issho.document(graph,
      on_change: fn _change, %{result: result} ->
        send(:erlang.binary_to_term(Base.decode64!(test)), {:saved, result})
        :ok
      end
    )
  end

  def document(_identity, _id), do: {:error, :not_found}
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
