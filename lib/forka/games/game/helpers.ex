defmodule Forka.Games.Game.Helpers do
  @moduledoc false

  alias Forka.Games.Game.GameState

  # This module provides helper functions to manage and manipulate the game state.

  @doc false
  def find_game_player_by_id(%GameState{game_players: game_players}, player_id) do
    Enum.find(game_players, fn {_idx, game_player} -> game_player.player.id == player_id end)
  end
end
