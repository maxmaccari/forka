defmodule Forka.Games.Game.GamePlayer do
  @moduledoc """
  This module represents a player within a specific game session.

  Each game player has:
  - A player struct containing the base player information (required)
  - A status indicating if the player is alive or dead (defaults to :alive)
  - Lives remaining in the game (defaults to 6)
  - A connection status indicating if connected/disconnected (defaults to :disconnected)
  - A score that tracks points earned in the current game (defaults to 0)

  The GamePlayer wraps the base Player struct with game-specific attributes like lives, status, and score,
  allowing the same player to participate in multiple games with different states.
  """

  alias Forka.Games.Schemas.Player

  # Player in hangman starts with 6 lives
  @initial_lives 6

  defstruct player: nil,
            status: :alive,
            lives: @initial_lives,
            score: 0

  @doc false
  def new(%Player{} = player) do
    %__MODULE__{player: player}
  end

  @doc false
  def decrement_lives(%__MODULE__{status: :alive, lives: lives} = game_player) when lives > 0,
    do: %{game_player | lives: lives - 1}

  @doc false
  def decrement_lives(%__MODULE__{status: :alive, lives: lives} = game_player) when lives == 0,
    do: %{game_player | status: :dead}

  @doc false
  def decrement_lives(%__MODULE__{} = game_player), do: game_player

  @doc false
  def reset_lives(%__MODULE__{} = game_player),
    do: %{game_player | lives: @initial_lives, status: :alive}

  @doc false
  def give_up(%__MODULE__{} = game_player),
    do: %{game_player | status: :dead, lives: 0}

  @doc false
  def add_score(%__MODULE__{status: :alive, score: score} = game_player, points)
      when is_integer(points) do
    %{game_player | score: score + points}
  end

  def add_score(%__MODULE__{} = game_player, points) when is_integer(points), do: game_player

  @doc false
  def died?(%__MODULE__{status: :dead}), do: true
  def died?(%__MODULE__{}), do: false

  @doc false
  def alive?(%__MODULE__{status: :alive}), do: true
  def alive?(%__MODULE__{}), do: false
end
