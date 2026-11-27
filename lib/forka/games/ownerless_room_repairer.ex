defmodule Forka.Games.OwnerlessRoomRepairer do
  @moduledoc """
  Asynchronously drains remaining ownerless rooms in bounded batches after a public
  directory load reaches its synchronous repair cap.
  """

  use GenServer

  alias Forka.Games.GameServer
  alias Forka.Games.Repository
  alias Forka.Games.RoomListItem

  @default_batch_size 10

  @type state :: %{
          batch_size: pos_integer(),
          draining?: boolean(),
          reschedule?: boolean(),
          phase: Repository.ownerless_phase(),
          cursor: Repository.ownerless_cursor() | nil,
          waiters: [GenServer.from()]
        }

  @doc "Starts the ownerless room repairer GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    GenServer.start_link(__MODULE__, batch_size, name: name)
  end

  @doc "Schedules an asynchronous drain of remaining ownerless rooms if not already draining."
  @spec schedule_drain(GenServer.server()) :: :ok
  def schedule_drain(server \\ __MODULE__) do
    GenServer.cast(server, :schedule_drain)
  end

  @doc "Blocks until any currently scheduled or in-progress drain finishes."
  @spec await_idle(GenServer.server(), timeout()) :: :ok
  def await_idle(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :await_idle, timeout)
  end

  @impl true
  def init(batch_size) when is_integer(batch_size) and batch_size > 0 do
    {:ok,
     %{
       batch_size: batch_size,
       draining?: false,
       reschedule?: false,
       phase: :populated,
       cursor: nil,
       waiters: []
     }}
  end

  @impl true
  def handle_cast(:schedule_drain, %{draining?: false} = state) do
    send(self(), :drain_batch)
    {:noreply, %{state | draining?: true, reschedule?: false, phase: :populated, cursor: nil}}
  end

  def handle_cast(:schedule_drain, %{draining?: true} = state) do
    {:noreply, %{state | reschedule?: true}}
  end

  @impl true
  def handle_call(:await_idle, _from, %{draining?: false} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:await_idle, from, %{draining?: true, waiters: waiters} = state) do
    {:noreply, %{state | waiters: [from | waiters]}}
  end

  @impl true
  def handle_info(:drain_batch, state) do
    {phase, cursor} =
      if state.reschedule?, do: {:populated, nil}, else: {state.phase, state.cursor}

    case drain_one_batch(state.batch_size, phase, cursor) do
      {:more, next_phase, next_cursor} ->
        send(self(), :drain_batch)

        {:noreply,
         %{
           state
           | draining?: true,
             reschedule?: false,
             phase: next_phase,
             cursor: next_cursor
         }}

      status when status in [:done, :stalled] ->
        reply_waiters(state.waiters)

        {:noreply,
         %{
           state
           | draining?: false,
             reschedule?: false,
             phase: :populated,
             cursor: nil,
             waiters: []
         }}
    end
  end

  defp drain_one_batch(batch_size, phase, cursor) do
    visible_statuses = RoomListItem.visible_statuses()

    case Repository.list_ownerless_visible_games_batch(
           visible_statuses,
           batch_size + 1,
           phase: phase,
           after: cursor
         ) do
      [] ->
        empty_batch_transition(phase)

      entries ->
        reconcile_entries(entries, batch_size, phase)
    end
  end

  defp empty_batch_transition(:populated), do: {:more, :empty, nil}
  defp empty_batch_transition(:empty), do: :done

  defp reconcile_entries(entries, batch_size, phase) do
    {batch, remaining} = Enum.split(entries, batch_size)
    made_progress? = batch |> Enum.map(&reconcile_made_progress?(&1.id)) |> Enum.any?()

    cond do
      not made_progress? ->
        :stalled

      remaining != [] ->
        {:more, phase, next_cursor(phase, batch)}

      phase == :populated ->
        {:more, :empty, nil}

      true ->
        :done
    end
  end

  defp next_cursor(:populated, batch) do
    last = List.last(batch)
    {last.inserted_at, last.id}
  end

  defp next_cursor(:empty, _batch), do: nil

  defp reconcile_made_progress?(game_id) do
    case GameServer.reconcile_ownerless_room(game_id) do
      {:ok, _summary} -> true
      {:error, reason} when reason in [:game_archived, :not_found] -> true
      {:error, _other} -> false
    end
  end

  defp reply_waiters(waiters) do
    Enum.each(waiters, &GenServer.reply(&1, :ok))
  end
end
