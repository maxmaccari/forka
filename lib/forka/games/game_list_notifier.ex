defmodule Forka.Games.GameListNotifier do
  @moduledoc "Publishes game list changes to subscribed clients."

  # Handles notifications for the game list.
  # This module provides a centralized way to manage game list updates
  # without cluttering either the Games context or GameServer modules.

  alias Forka.Games.Core.GameState
  alias Phoenix.PubSub

  @pubsub Forka.PubSub
  @topic "game_list"

  @doc """
  Subscribe to game list updates.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Unsubscribe from game list updates.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    PubSub.unsubscribe(@pubsub, @topic)
  end

  @doc """
  Broadcast an update to the game list with a specific action.
  """
  @spec broadcast_update(GameState.t(), atom()) :: :ok
  def broadcast_update(game_state, action \\ :updated) do
    data = Map.merge(list_fields(game_state), %{updated_at: DateTime.utc_now(), action: action})
    PubSub.broadcast!(@pubsub, @topic, {:game_list_updated, data})
  end

  @doc false
  @spec broadcast_update_if_changed(GameState.t(), GameState.t()) :: :ok
  def broadcast_update_if_changed(
        %GameState{} = previous,
        %GameState{} = saved
      ) do
    if list_fields(previous) != list_fields(saved), do: broadcast_update(saved)
    :ok
  end

  defp list_fields(game_state) do
    %{
      id: game_state.id,
      name: game_state.name,
      status: game_state.status,
      player_count: map_size(game_state.game_players || %{}),
      max_players: game_state.max_players,
      owner: game_state.owner
    }
  end

  @doc """
  Broadcast a game creation event.
  """
  @spec broadcast_created(GameState.t()) :: :ok
  def broadcast_created(game_state) do
    broadcast_update(game_state, :created)
  end
end
