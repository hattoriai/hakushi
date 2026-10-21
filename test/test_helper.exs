{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: HakushiTest.PubSub)
{:ok, _pid} = HakushiTest.Endpoint.start_link()
Application.put_env(:hakushi, :room_timeout, 50)
ExUnit.start()
