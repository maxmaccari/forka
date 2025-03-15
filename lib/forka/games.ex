defmodule Forka.Games do
  alias Forka.Games.Game

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

  @doc """
  Creates a new game with the given parameters.

  ## Parameters
    - params: A map containing game configuration:
      - owner: (required) The player who is creating the game
      - name: (optional) The name of the game (default: "My Game")
      - max_players: (optional) Maximum number of players allowed (default: 2)

  ## Returns
    - `{:ok, game}` if the game was created successfully
    - `{:error, reason}` if creation failed
  """
  def create_game(params \\ %{}) do
    owner = Map.fetch!(params, :owner)
    name = Map.get(params, :name, "My Game")
    max_players = Map.get(params, :max_players, 2)

    game = Game.new(owner, name, max_players)

    case start_supervised_game(game) do
      {:ok, _pid} -> {:ok, game}
      {:error, error} -> {:error, error}
    end
  end

  defp start_supervised_game(game),
    do: DynamicSupervisor.start_child(Forka.GamesSupervisor, {Forka.Games.GameServer, game})

  @doc """
  Adds a player to the game.

  ## Parameters
    - game_id: The ID of the game.
    - player: The player to add.

  ## Returns
    See `Forka.Games.GameServer.add_player/2` for return values.
  """
  defdelegate add_player(game_id, player), to: Forka.Games.GameServer

  @doc """
  Removes a player from the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to remove.

  ## Returns
    See `Forka.Games.GameServer.remove_player/2` for return values.
  """
  defdelegate remove_player(game_id, player_id), to: Forka.Games.GameServer

  @doc """
  Initializes the game.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.init_game/1` for return values.
  """
  defdelegate init_game(game_id), to: Forka.Games.GameServer

  @doc """
  Makes a player give up in the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who is giving up.

  ## Returns
    See `Forka.Games.GameServer.give_up_player/2` for return values.
  """
  defdelegate give_up_player(game_id, player_id), to: Forka.Games.GameServer

  @doc """
  Makes a guess for the current word in the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player making the guess.
    - letter: The letter being guessed.

  ## Returns
    See `Forka.Games.GameServer.guess/3` for return values.
  """
  defdelegate guess(game_id, player_id, letter), to: Forka.Games.GameServer

  @doc """
  Transfers ownership of the game to another player.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who will become the new owner.

  ## Returns
    See `Forka.Games.GameServer.transfer_ownership/2` for return values.
  """
  defdelegate transfer_ownership(game_id, player_id), to: Forka.Games.GameServer

  @doc """
  Restarts the game, returning it to the lobby state.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.restart_game/1` for return values.
  """
  defdelegate restart_game(game_id), to: Forka.Games.GameServer

  @doc """
  Archives the game, marking it as completed and no longer active.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    See `Forka.Games.GameServer.archive_game/1` for return values.
  """
  defdelegate archive_game(game_id), to: Forka.Games.GameServer

  @doc """
  Gets the current game summary.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    The current game summary.
  """
  defdelegate get_game(game_id), to: Forka.Games.GameServer

  @doc """
  Subscribes the caller to receive updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to subscribe to.

  ## Returns
    - `:ok` if the subscription is successful.
    - `{:error, term}` if the subscription fails.
  """
  defdelegate subscribe(game_id), to: Forka.Games.GameServer

  @doc """
  Unsubscribes the caller from receiving updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to unsubscribe from.

  ## Returns
    - `:ok` if the unsubscription is successful.
    - `{:error, term}` if the unsubscription fails.
  """
  defdelegate unsubscribe(game_id), to: Forka.Games.GameServer
end
