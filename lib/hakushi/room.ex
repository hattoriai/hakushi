defmodule Hakushi.Room do
  @moduledoc """
  One process for each canvas that people share: it puts their changes in
  order, checks them, and sends them to everyone on the canvas.

  A canvas with `live={{MyApp.PubSub, "diagram:42"}}` joins the room of
  its topic when its LiveView connects. The first to join starts the room,
  with the canvas's `graph`, `rules` and `on_change`; those who join later
  get the room's graph, as it is with every change since. Each change of
  a person goes to the room, which applies it (`Hakushi.Graph.apply/2`),
  checks the rules and asks `on_change`, one change at a time, and then
  sends it on the topic, where each canvas applies it to its own graph,
  in the same order. So `on_change` runs once for each change, wherever
  the people are, and two people never save over each other: the second
  change applies to the graph the first one made.

  The room knows who is in it: it watches the LiveView of each canvas, and
  tells the others when a person comes or goes, with no
  `Phoenix.Presence`. When the last person leaves, the room waits a while
  (`config :hakushi, room_timeout:`, 5 seconds unless set), so that a
  reload finds it, then stops.

  The room is registered with `:global`: in a cluster, the canvases of a
  topic on every node share one room. The changes go on the topic, so the
  PubSub must reach every node, as Phoenix's does.

  The app makes its own changes through the room with `change/2`, from
  anywhere (a LiveView, a job): they go to everyone, as a person's do.
  """

  use GenServer, restart: :temporary

  alias Hakushi.{Change, Commit, Graph, Rules}

  @palette ~w(#e84a1c #2563eb #059669 #9333ea #d97706 #db2777 #0891b2 #65a30d)

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: name(opts[:topic]))

  defp name(topic), do: {:global, {__MODULE__, topic}}

  @doc """
  The room of a topic, or `nil` when no one has the canvas open.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(topic) do
    case :global.whereis_name({__MODULE__, topic}) do
      :undefined -> nil
      pid -> pid
    end
  end

  @doc """
  Makes a change on the canvas of a topic, for everyone on it: the app's
  own change (`by` is `nil`). Gives `:ok`, `{:error, reason}` when the
  change does not apply or `on_change` refuses it, or
  `{:error, :not_running}` when no one has the canvas open (then change
  your own copy, in your database).
  """
  @spec change(String.t(), Change.t()) :: :ok | {:error, term()}
  def change(topic, %Change{} = change) do
    case whereis(topic) do
      nil ->
        {:error, :not_running}

      pid ->
        case GenServer.call(pid, {:change, change}) do
          {:ok, _inverse} -> :ok
          error -> error
        end
    end
  end

  @doc "The graph of the canvas of a topic, as the room has it, or `nil`."
  @spec graph(String.t()) :: Graph.t() | nil
  def graph(topic) do
    case whereis(topic) do
      nil -> nil
      pid -> GenServer.call(pid, :graph)
    end
  end

  @doc false
  # A canvas joins: the room of its topic, started with its graph when
  # there is none. Gives the graph, its version, and the people.
  @spec join(map()) :: {:ok, pid(), Graph.t(), non_neg_integer(), [map()]}
  def join(%{topic: _topic} = opts) do
    pid =
      case DynamicSupervisor.start_child(Hakushi.RoomSupervisor, {__MODULE__, opts}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    case GenServer.call(pid, {:join, self(), opts.user}) do
      {:ok, graph, version, people} -> {:ok, pid, graph, version, people}
      # The room stopped as we joined (its last person had left); a new one.
      :stopping -> join(opts)
    end
  catch
    :exit, {:noproc, _} -> join(opts)
    :exit, {:normal, _} -> join(opts)
  end

  @doc false
  @spec commit(pid(), Change.t()) :: {:ok, Change.t()} | {:error, term()}
  def commit(pid, %Change{} = change), do: GenServer.call(pid, {:change, change})

  @doc false
  @spec color(term()) :: String.t()
  def color(id), do: Enum.at(@palette, :erlang.phash2(id, length(@palette)))

  @impl true
  def init(opts) do
    {:ok,
     %{
       topic: opts.topic,
       pubsub: opts.pubsub,
       graph: opts.graph,
       rules: Rules.new(opts[:rules]),
       on_change: opts[:on_change],
       canvas: opts[:canvas],
       version: 0,
       people: %{},
       stop_timer: nil,
       stopping: false
     }}
  end

  @impl true
  def handle_call({:join, _pid, _user}, _from, %{stopping: true} = state),
    do: {:reply, :stopping, state}

  def handle_call({:join, pid, user}, _from, state) do
    ref = Process.monitor(pid)
    person = person(user)
    state = cancel_stop(%{state | people: Map.put(state.people, pid, {ref, person})})
    broadcast(state, {:people, people(state)})
    {:reply, {:ok, state.graph, state.version, people(state)}, state}
  end

  def handle_call(:graph, _from, state), do: {:reply, state.graph, state}

  def handle_call({:change, change}, _from, state) do
    case Commit.run(state.graph, change, Map.take(state, [:rules, :on_change, :canvas])) do
      {:ok, graph, change, inverse} ->
        version = state.version + 1
        broadcast(state, {:changed, version, change})
        {:reply, {:ok, inverse}, %{state | graph: graph, version: version}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = %{state | people: Map.delete(state.people, pid)}
    broadcast(state, {:people, people(state)})

    if state.people == %{} do
      timeout = Application.get_env(:hakushi, :room_timeout, 5_000)
      {:noreply, %{state | stop_timer: Process.send_after(self(), :stop, timeout)}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:stop, %{people: people} = state) when people == %{},
    do: {:stop, :normal, %{state | stopping: true}}

  def handle_info(:stop, state), do: {:noreply, state}

  defp cancel_stop(%{stop_timer: nil} = state), do: state

  defp cancel_stop(state) do
    Process.cancel_timer(state.stop_timer)
    %{state | stop_timer: nil}
  end

  defp person(nil), do: nil

  defp person(user) do
    id = Map.get(user, :id) || Map.get(user, "id")
    name = Map.get(user, :name) || Map.get(user, "name")

    %{
      "id" => to_string(id),
      "name" => name && to_string(name),
      "color" => Map.get(user, :color) || Map.get(user, "color") || color(id),
      "avatar" => Map.get(user, :avatar) || Map.get(user, "avatar")
    }
  end

  # Each person once, however many tabs they have open.
  defp people(state) do
    state.people
    |> Map.values()
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["id"])
  end

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:hakushi, state.topic, message})
  end
end
