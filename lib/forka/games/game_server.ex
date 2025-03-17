defmodule Forka.Games.GameServer do
  @moduledoc """
  A GenServer implementation for managing game state and operations.

  The GameServer is responsible for:
  - Creating and managing game insstances
  - Handling player actions (joining, leaving, guessing)
  - Managing game lifecycle (starting, restarting, archiving)
  - Maintaining game state throughout play

  Each game has its own dedicated server process identified by a unique ID.
  The server handles all game operations and maintains the state between player interactions.
  """

  use GenServer

  alias Forka.Games.Repository
  alias Phoenix.PubSub
  alias Forka.Games.Player
  alias Forka.Games.Game
  alias Forka.Games.Game.GameState

  @pubsub_topic_prefix "game"
  @message_tagger :game_updated
  # 30 minutes in milliseconds
  @timeout_ms 30 * 60 * 1000

  # Public API

  @doc """
  Starts the GameServer.

  ## Parameters
    - owner: The player who created the game.
    - opts: Options for the game, including:
      - name: The name of the game (default: "Jogo").
      - max_players: The maximum number of players allowed in the game (default: 2).

  ## Returns
    - `{:ok, pid}` if the server is started successfully.
  """
  def start_link(%GameState{} = game_state) do
    GenServer.start_link(__MODULE__, game_state, name: global_name(game_state.id))
  end

  defp global_name(game_id) when is_binary(game_id) do
    {:global, {__MODULE__, game_id}}
  end

  @doc """
  Checks if a game server exists for the given game ID.

  ## Parameters
    - game_id: The ID of the game to check.

  ## Returns
    - `true` if the game server exists.
    - `false` if the game server does not exist.
  """
  def exists?(game_id) when is_binary(game_id) do
    game_id |> whereis() |> is_pid()
  end

  @doc """
  Finds the process ID for a game server with the given game ID.

  ## Parameters
    - game_id: The ID of the game to locate.

  ## Returns
    - The PID of the game server if it exists.
    - `nil` if the game server does not exist.
  """
  def whereis(game_id) do
    game_id
    |> global_name()
    |> GenServer.whereis()
  end

  @doc """
  Gets the current game summary.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - The current game summary.
  """
  def get_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :get_game)
  end

  @doc """
  Adds a player to the game.

  Delegates to `Forka.Games.Game.join_game/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player: The player to add.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.join_game/2` for possible error reasons.
  """
  def join_game(game_id, %Player{} = player) when is_binary(game_id) do
    GenServer.call(global_name(game_id), {:join_game, player})
  end

  @doc """
  Removes a player from the game.

  Delegates to `Forka.Games.Game.leave_game/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to remove.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.leave_game/2` for possible error reasons.
  """
  def leave_game(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:leave_game, player_id})
  end

  @doc """
  Sets the word options for the game.

  Delegates to `Forka.Games.Game.set_word_options/2`.

  ## Parameters
    - game_id: The ID of the game.
    - options: Keyword list of options (e.g., [language: "en", category_ids: ["uuid1"]])

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.set_word_options/2` for possible error reasons.
  """
  def set_word_options(game_id, options) when is_binary(game_id) and is_list(options) do
    GenServer.call(global_name(game_id), {:set_word_options, options})
  end

  @doc """
  Initializes the game.

  Delegates to `Forka.Games.Game.start_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.start_game/1` for possible error reasons.
  """
  def start_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :start_game)
  end

  @doc """
  Makes a player give up in the game.

  Delegates to `Forka.Games.Game.give_up_game/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who is giving up.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.give_up_game/2` for possible error reasons.
  """
  def give_up_game(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:give_up, player_id})
  end

  @doc """
  Makes a guess for the current word in the game.

  Delegates to `Forka.Games.Game.guess/3`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player making the guess.
    - letter: The letter being guessed.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.guess/3` for possible error reasons.
  """
  def guess(game_id, player_id, letter)
      when is_binary(game_id) and is_binary(letter) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:guess, letter, player_id})
  end

  @doc """
  Transfers ownership of the game to another player.

  Delegates to `Forka.Games.Game.transfer_ownership_to_player/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who will become the new owner.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.transfer_ownership_to_player/2` for possible error reasons.
  """
  def transfer_ownership(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:transfer_ownership, player_id})
  end

  @doc """
  Restarts the game, returning it to the lobby state.

  Delegates to `Forka.Games.Game.restart_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.restart_game/1` for possible error reasons.
  """
  def restart_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :restart_game)
  end

  @doc """
  Archives the game, marking it as completed and no longer active.
  This will stop the server process.

  Delegates to `Forka.Games.Game.archive_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.archive_game/1` for possible error reasons.
  """
  def archive_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :archive_game)
  end

  @doc """
  Subscribes the caller to receive updates for a specific game.

  When events occur in the game (like player actions or state changes),
  subscribers will receive messages in the format `{:game_updated, game_summary}`.

  ## Parameters
    - game_id: The ID of the game to subscribe to.

  ## Returns
    - `:ok` if the subscription is successful.
    - `{:error, term}` if the subscription fails.
  """
  def subscribe(game_id) when is_binary(game_id) do
    PubSub.subscribe(Forka.PubSub, topic(game_id))
  end

  @doc """
  Unsubscribes the caller from receiving updates for a specific game.

  This stops the process from receiving messages about game events.

  ## Parameters
    - game_id: The ID of the game to unsubscribe from.

  ## Returns
    - `:ok` if the unsubscription is successful.
    - `{:error, term}` if the unsubscription fails.
  """
  def unsubscribe(game_id) when is_binary(game_id) do
    PubSub.unsubscribe(Forka.PubSub, topic(game_id))
  end

  # Callbacks
  @impl true
  def init(%GameState{} = game_state) do
    {:ok, game_state, @timeout_ms}
  end

  @impl true
  def handle_call(:get_game, _from, game) do
    {:reply, Game.to_game_summary(game), game, @timeout_ms}
  end

  @impl true
  def handle_call({:join_game, player}, _from, game) do
    case Game.join_game(game, player) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:leave_game, player_id}, _from, game) do
    case Game.leave_game(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:set_word_options, options}, _from, game) do
    case Game.set_word_options(game, options) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    words_count = map_size(game.players) * 2
    words = Repository.get_random_words(words_count, game.word_options)
    game_with_words = Game.set_words(game, words)

    case game_with_words |> Game.shuffle_players() |> Game.start_game() do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:give_up, player_id}, _from, game) do
    case Game.give_up_game(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:guess, letter, player_id}, _from, game) do
    case Game.guess(game, player_id, letter) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:transfer_ownership, player_id}, _from, game) do
    case Game.transfer_ownership_to_player(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:restart_game, _from, game) do
    case Game.restart_game(game) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:archive_game, _from, game) do
    case Game.archive_game(game) do
      {:ok, new_game} ->
        broadcast!(new_game)
        # Return the response and stop the GenServer with normal reason
        {:stop, :normal, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, game) do
    # Server has been inactive for the timeout period, archive the game and terminate
    case Game.archive_game(game) do
      {:ok, new_game} ->
        broadcast!(new_game)
        {:stop, :normal, new_game}

      {:error, _error} ->
        # Even if archiving fails, we should terminate the server
        {:stop, :normal, game}
    end
  end

  # Private Helpers

  defp topic(game_id), do: "#{@pubsub_topic_prefix}:#{game_id}"

  defp broadcast!(%GameState{id: game_id} = game_state) do
    game_summary = Game.to_game_summary(game_state)
    PubSub.broadcast!(Forka.PubSub, topic(game_id), {@message_tagger, game_summary})
  end
end
