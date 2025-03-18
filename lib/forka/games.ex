defmodule Forka.Games do
  @moduledoc """
  The Games context.

  This module provides functions for managing game operations, including:
  - Creating and initializing games
  - Managing players (adding, removing)
  - Game state operations
  - Subscribing to game updates

  It serves as the main interface for game-related operations, delegating
  most functionality to the GameServer implementation.
  """

  alias Forka.Games.GameServer
  alias Forka.Games.Repository

  @doc """
  Creates a new game with the given parameters.

  ## Parameters
    - owner_id: (required) The ID of the player who is creating the game
    - params: A map containing game configuration:
      - name: (optional) The name of the game (default: "My Game")
      - max_players: (optional) Maximum number of players allowed (default: 2)

  ## Returns
    - `{:ok, game}` if the game was created successfully
    - `{:error, reason}` if creation failed
  """
  def create_game(owner_id, params \\ %{}) do
    with {:ok, game} <- Repository.insert_game(owner_id, params),
         {:ok, _pid} <- start_supervised_game(game.id) do
      {:ok, game}
    end
  end

  defp start_supervised_game(game_id),
    do: DynamicSupervisor.start_child(Forka.GamesSupervisor, {GameServer, game_id})

  @doc """
  Updates the settings of a game.

  ## Parameters
    - game_id: The ID of the game.
    - settings: A map containing the settings to update:
      - name: (optional) The name of the game
      - max_players: (optional) Maximum number of players allowed
      - word_settings: (optional) Settings for word selection

  ## Returns
    - `:ok` if the settings were updated successfully
    - `{:error, reason}` if the update failed

  Note: Settings can only be updated when the game is in the lobby state.
  """
  def update_settings(game_id, settings) when is_map(settings) do
    ensure_game_server_available(game_id, fn -> GameServer.update_settings(game_id, settings) end)
  end

  @doc """
  Adds a player to the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to join.

  ## Returns
    See `Forka.Games.GameServer.join_game/2` for return values.
  """
  def join_game(game_id, player_id) do
    ensure_game_server_available(game_id, fn -> GameServer.join_game(game_id, player_id) end)
  end

  @doc """
  Removes a player from the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to leave.

  ## Returns
    See `Forka.Games.GameServer.leave_game/2` for return values.
  """
  def leave_game(game_id, player_id) do
    ensure_game_server_available(game_id, fn -> GameServer.leave_game(game_id, player_id) end)
  end

  @doc """
  Initializes the game.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.start_game/1` for return values.
  """
  def start_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.start_game(game_id) end)
  end

  @doc """
  Makes a player give up in the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who is giving up.

  ## Returns
    See `Forka.Games.GameServer.give_up_game/2` for return values.
  """
  def give_up_game(game_id, player_id) do
    ensure_game_server_available(game_id, fn -> GameServer.give_up_game(game_id, player_id) end)
  end

  @doc """
  Makes a guess for the current word in the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player making the guess.
    - letter: The letter being guessed.

  ## Returns
    See `Forka.Games.GameServer.guess/3` for return values.
  """
  def guess(game_id, player_id, letter) do
    ensure_game_server_available(game_id, fn -> GameServer.guess(game_id, player_id, letter) end)
  end

  @doc """
  Transfers ownership of the game to another player.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who will become the new owner.

  ## Returns
    See `Forka.Games.GameServer.transfer_ownership/2` for return values.
  """
  def transfer_ownership(game_id, player_id) do
    ensure_game_server_available(game_id, fn ->
      GameServer.transfer_ownership(game_id, player_id)
    end)
  end

  @doc """
  Restarts the game, returning it to the lobby state.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.restart_game/1` for return values.
  """
  def restart_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.restart_game(game_id) end)
  end

  @doc """
  Archives the game, marking it as completed and no longer active.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.archive_game/1` for return values.
  """
  def archive_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.archive_game(game_id) end)
  end

  @doc """
  Gets the current game summary.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    The current game summary.
  """
  def get_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.get_game(game_id) end)
  end

  @doc """
  Subscribes the caller to receive updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to subscribe to.

  ## Returns
    - `:ok` if the subscription is successful.
    - `{:error, term}` if the subscription fails.
  """
  def subscribe(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.subscribe(game_id) end)
  end

  @doc """
  Unsubscribes the caller from receiving updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to unsubscribe from.

  ## Returns
    - `:ok` if the unsubscription is successful.
    - `{:error, term}` if the unsubscription fails.
  """
  def unsubscribe(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.unsubscribe(game_id) end)
  end

  defp ensure_game_server_available(game_id, action) do
    cond do
      GameServer.exists?(game_id) ->
        action.()

      true ->
        case Repository.get_game_state(game_id) do
          {:ok, _game_state} ->
            case start_supervised_game(game_id) do
              {:ok, _pid} -> action.()
              {:error, reason} -> {:error, reason}
            end

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
