defmodule Forka.Games.GameServer do
  @moduledoc false

  # A GenServer implementation for managing game state and operations.

  # The GameServer is responsible for:
  # - Creating and managing game instances
  # - Handling player actions (joining, leaving, guessing)
  # - Managing game lifecycle (starting, restarting, archiving)
  # - Maintaining game state throughout play

  # Each game has its own dedicated server process identified by a unique ID.
  # The server handles all game operations and maintains the state between player interactions.

  use GenServer

  alias Forka.Games.Repository
  alias Phoenix.PubSub
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Game
  alias Forka.Games.Game.GameState

  @pubsub_topic_prefix "game"
  @message_tagger :game_updated
  # 30 minutes in milliseconds
  @timeout_ms 30 * 60 * 1000

  # Public API

  @doc false
  def start_link(game_id) do
    with {:ok, game_state} <- Repository.get_game_state(game_id),
         :ok <- validate_status(game_state) do
      GenServer.start_link(__MODULE__, game_state, name: global_name(game_id))
    end
  end

  defp validate_status(%{status: :archived}), do: {:error, :game_archived}
  defp validate_status(_), do: :ok

  defp global_name(game_id) when is_binary(game_id) do
    {:global, {__MODULE__, game_id}}
  end

  @doc false
  def exists?(game_id) when is_binary(game_id) do
    game_id |> whereis() |> is_pid()
  end

  @doc false
  def whereis(game_id) do
    game_id
    |> global_name()
    |> GenServer.whereis()
  end

  @doc false
  def get_game(game_id, opts \\ []) when is_binary(game_id) do
    GenServer.call(global_name(game_id), {:get_game, opts})
  end

  @doc false
  def join_game(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:join_game, player_id})
  end

  @doc false
  def leave_game(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:leave_game, player_id})
  end

  @doc false
  def update_settings(game_id, settings) when is_binary(game_id) and is_map(settings) do
    GenServer.call(global_name(game_id), {:update_settings, settings})
  end

  @doc false
  def start_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :start_game)
  end

  @doc false
  def give_up_game(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:give_up, player_id})
  end

  @doc false
  def guess(game_id, player_id, letter)
      when is_binary(game_id) and is_binary(letter) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:guess, letter, player_id})
  end

  @doc false
  def transfer_ownership(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:transfer_ownership, player_id})
  end

  @doc false
  def restart_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :restart_game)
  end

  @doc false
  def archive_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :archive_game)
  end

  @doc false
  def subscribe(game_id) when is_binary(game_id) do
    PubSub.subscribe(Forka.PubSub, topic(game_id))
  end

  @doc false
  def unsubscribe(game_id) when is_binary(game_id) do
    PubSub.unsubscribe(Forka.PubSub, topic(game_id))
  end

  # Callbacks
  @impl true
  def init(%GameState{} = game_state) do
    {:ok, game_state, @timeout_ms}
  end

  @impl true
  def handle_call({:get_game, opts}, _from, game) do
    {:reply, Game.to_game_summary(game, opts), game, @timeout_ms}
  end

  @impl true
  def handle_call({:join_game, player_id}, _from, game) do
    with %Player{} = player <- Repository.get_player(player_id),
         {:ok, new_game} <- Game.join_game(game, player) do
      saved_game = Repository.save_game_state!(new_game)
      broadcast!(saved_game)

      {:reply, :ok, saved_game, @timeout_ms}
    else
      nil ->
        {:reply, {:error, :player_not_found}, game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:leave_game, player_id}, _from, game) do
    case Game.leave_game(game, player_id) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:update_settings, settings}, _from, game) do
    case Game.update_settings(game, settings) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    words_count = map_size(game.game_players) * 2
    words = Repository.get_random_words(words_count, game.word_options)
    game_with_words = Game.set_words(game, words)

    case game_with_words |> Game.shuffle_players() |> Game.start_game() do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:give_up, player_id}, _from, game) do
    case Game.give_up_game(game, player_id) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:guess, letter, player_id}, _from, game) do
    case Game.guess(game, player_id, letter) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:transfer_ownership, player_id}, _from, game) do
    case Game.transfer_ownership_to_player(game, player_id) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:restart_game, _from, game) do
    case Game.restart_game(game) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:archive_game, _from, game) do
    case Game.archive_game(game) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)
        # Return the response and stop the GenServer with normal reason
        {:stop, :normal, :ok, saved_game}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, game) do
    # Server has been inactive for the timeout period, archive the game and terminate
    case Game.archive_game(game) do
      {:ok, new_game} ->
        saved_game = Repository.save_game_state!(new_game)
        broadcast!(saved_game)

        {:stop, :normal, saved_game}

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
