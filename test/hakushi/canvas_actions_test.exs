defmodule Hakushi.CanvasActionsTest do
  # A shared canvas's commands are Issho's actions: a person's canvas and an
  # agent's tool run the same one, heard as "action.done" by whoever made it.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hakushi.Test

  alias Issho.Tool.Context

  @endpoint HakushiTest.Endpoint

  defp open(topic, user) do
    {:ok, view, _html} = live(build_conn(), "/?live=#{topic}&user=#{user}")
    view
  end

  defp topic, do: "t#{System.unique_integer([:positive])}"

  defp settle(view) do
    :sys.get_state(view.pid)
    :sys.get_state(view.pid)
  end

  defp agent(id), do: Context.new(HakushiTest.Issho, %{id: id, name: "Assistant", kind: :agent})

  defp tools, do: Hakushi.Issho.tools() ++ Issho.Tools.room()

  test "a person's connect and delete, and an agent's, are the same actions" do
    topic = topic()
    room = "canvas:" <> topic
    :ok = Issho.Events.subscribe(HakushiTest.Issho, room)
    ada = open(topic, "ada")

    assert :ok = connect(ada, "schema", "note", "orders")

    assert_receive {Issho, :event,
                    %Issho.Event{
                      name: "action.done",
                      by: %{key: "ada"},
                      data: %{action: "connect_nodes", source: "note", target: "orders"}
                    }}

    # Undone, it is deleted: the delete_items action, as Ada.
    assert :ok = undo(ada, "schema")

    assert_receive {Issho, :event,
                    %Issho.Event{
                      name: "action.done",
                      by: %{key: "ada"},
                      data: %{action: "delete_items"}
                    }}

    settle(ada)
    refute Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))

    assistant = agent("assistant-#{topic}")

    assert {:ok, %{"id" => edge}} =
             Issho.Tools.call(
               tools(),
               "connect_nodes",
               %{"canvas" => room, "source" => "note", "target" => "orders"},
               assistant
             )

    assert_receive {Issho, :event,
                    %Issho.Event{name: "action.done", by: %{kind: :agent}, data: %{edge: ^edge}}}

    settle(ada)
    assert Enum.any?(edges(ada, "schema"), &(&1.id == edge))

    # The canvas's rules (no cycles) refuse a person's connect and an agent's alike.
    assert {:error, _reason} = connect(ada, "schema", "users", "orders")

    assert {:error, _reason} =
             Issho.Tools.call(
               tools(),
               "connect_nodes",
               %{"canvas" => room, "source" => "users", "target" => "orders"},
               assistant
             )
  end

  test "an agent paused before it goes there connects nothing, and is told why" do
    topic = topic()
    room = "canvas:" <> topic
    ada = open(topic, "ada")
    assistant = agent("paused-#{topic}")

    assert {:ok, _} = Issho.Tools.call(tools(), "read_canvas", %{"canvas" => room}, assistant)

    :ok =
      Issho.Work.interrupt(HakushiTest.Issho, room, Context.key(assistant), :pause,
        by: %{id: "ada", name: "Ada"}
      )

    participant = Issho.Agents.participant(HakushiTest.Issho, Context.key(assistant), room)
    wait_until(fn -> Issho.Participant.interrupted(participant) end)

    assert {:error, message} =
             Issho.Tools.call(
               tools(),
               "connect_nodes",
               %{"canvas" => room, "source" => "note", "target" => "orders"},
               assistant
             )

    assert message =~ "Ada paused you"
    settle(ada)
    refute Enum.any?(edges(ada, "schema"), &(&1.source == "note" and &1.target == "orders"))
  end

  test "an agent finds the canvas's actions it may do in its room" do
    topic = topic()
    room = "canvas:" <> topic
    _ada = open(topic, "ada")

    assert {:ok, %{"actions" => actions}} =
             Issho.Tools.call(tools(), "list_actions", %{"room" => room}, agent("a-#{topic}"))

    assert ~w(add_node connect_nodes update_node delete_items) ==
             actions |> Enum.filter(& &1.allowed) |> Enum.map(& &1.name)
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("it never came")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end
end
