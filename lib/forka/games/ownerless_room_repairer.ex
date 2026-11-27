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
    {:ok, %{batch_size: batch_size, draining?: false, reschedule?: false, waiters: []}}
  end

  @impl true
  def handle_cast(:schedule_drain, %{draining?: false} = state) do
    send(self(), :drain_batch)
    {:noreply, %{state | draining?: true, reschedule?: false}}
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
  def handle_info(:drain_batch, %{batch_size: batch_size} = state) do
    case drain_one_batch(batch_size) do
      :more ->
        send(self(), :drain_batch)
        {:noreply, %{state | draining?: true, reschedule?: false}}

      :done when state.reschedule? ->
        send(self(), :drain_batch)
        {:noreply, %{state | draining?: true, reschedule?: false}}

      status when status in [:done, :stalled] ->
        reply_waiters(state.waiters)
        {:noreply, %{state | draining?: false, reschedule?: false, waiters: []}}
    end
  end

  defp drain_one_batch(batch_size) do
    visible_statuses = RoomListItem.visible_statuses()

    case Repository.list_ownerless_visible_game_ids(visible_statuses, batch_size + 1) do
      [] ->
        :done

      ownerless_ids ->
        {batch_ids, remaining_ids} = Enum.split(ownerless_ids, batch_size)
        made_progress? = batch_ids |> Enum.map(&reconcile_made_progress?/1) |> Enum.any?()

        cond do
          not made_progress? -> :stalled
          remaining_ids != [] -> :more
          true -> :done
        end
    end
  end

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
