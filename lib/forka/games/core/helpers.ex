defmodule Forka.Games.Core.Helpers do
  @moduledoc false

  alias Forka.Games.Schemas.Event
  alias Forka.Games.Core.GameState

  # This module provides helper functions to manage and manipulate the game state.

  @doc false
  def find_game_player_by_id(%GameState{game_players: game_players}, player_id) do
    Enum.find(game_players, fn {_idx, game_player} -> game_player.player.id == player_id end)
  end

  @doc false
  def increment_tick(%GameState{tick: tick} = game), do: %{game | tick: tick + 1}

  @doc false
  def push_event(%GameState{tick: tick, events: events} = game, event_type, data \\ nil) do
    event = Event.new(event_type, tick, data)

    %{game | events: [event | events]}
  end
end
