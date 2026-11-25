defmodule Forka.Games.Core.Helpers do
  @moduledoc "Looks up players and records events in the game state."

  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.{Event, GamePlayer}

  # This module provides helper functions to manage and manipulate the game state.

  @doc false
  @spec find_game_player_by_id(GameState.t(), Ecto.UUID.t()) ::
          {non_neg_integer(), GamePlayer.t()} | nil
  def find_game_player_by_id(%GameState{game_players: game_players}, player_id) do
    Enum.find(game_players, fn {_idx, game_player} -> game_player.player.id == player_id end)
  end

  @doc false
  @spec participant?(GameState.t(), Ecto.UUID.t()) :: boolean()
  def participant?(%GameState{} = game_state, player_id) when is_binary(player_id) do
    find_game_player_by_id(game_state, player_id) != nil
  end

  @doc false
  @spec authorize_owner(GameState.t(), Ecto.UUID.t()) :: :ok | {:error, :unauthorized}
  def authorize_owner(%GameState{owner: %{id: owner_id}}, actor_id)
      when is_binary(actor_id) and actor_id == owner_id,
      do: :ok

  def authorize_owner(%GameState{}, _actor_id), do: {:error, :unauthorized}

  @doc false
  @spec increment_tick(GameState.t()) :: GameState.t()
  def increment_tick(%GameState{tick: 0, events: events} = game) do
    # Legacy games reused ticks. Advance above their history on the first new event.
    largest_tick = Enum.reduce(events, 0, fn event, largest -> max(event.tick, largest) end)
    %{game | tick: largest_tick + 1}
  end

  def increment_tick(%GameState{tick: tick} = game), do: %{game | tick: tick + 1}

  @doc false
  @spec push_event(GameState.t(), atom(), map() | nil) :: GameState.t()
  def push_event(%GameState{tick: tick, events: events} = game, event_type, data \\ nil) do
    event = Event.new(event_type, tick, data)

    %{game | events: [event | events]}
  end
end
