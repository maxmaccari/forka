defmodule Forka.Games.GameListNotifier do
  @moduledoc """
  Handles notifications for the game list.

  This module provides a centralized way to manage game list updates
  without cluttering either the Games context or GameServer modules.
  """

  alias Phoenix.PubSub

  @pubsub Forka.PubSub
  @topic "game_list"

  @doc """
  Subscribe to game list updates.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Unsubscribe from game list updates.
  """
  def unsubscribe do
    PubSub.unsubscribe(@pubsub, @topic)
  end

  @doc """
  Broadcast an update to the game list with a specific action.
  """
  def broadcast_update(game_state, action \\ :updated) do
    # Extract only the minimal data needed for the list view
    game_list_data = %{
      id: game_state.id,
      name: game_state.name,
      status: game_state.status,
      player_count: map_size(game_state.game_players || %{}),
      max_players: game_state.max_players,
      owner: game_state.owner,
      updated_at: DateTime.utc_now(),
      action: action
    }

    PubSub.broadcast!(@pubsub, @topic, {:game_list_updated, game_list_data})
  end

  @doc """
  Broadcast a game creation event.
  """
  def broadcast_created(game_state) do
    broadcast_update(game_state, :created)
  end
end
