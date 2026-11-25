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

  use GenServer, restart: :transient

  alias Forka.Games.Core
  alias Forka.Games.Core.GameState
  alias Forka.Games.GameListNotifier
  alias Forka.Games.Repository
  alias Forka.Games.RoomLobby
  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Words
  alias Phoenix.PubSub

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
  def update_settings(game_id, actor_id, settings)
      when is_binary(game_id) and is_binary(actor_id) and is_map(settings) do
    GenServer.call(global_name(game_id), {:update_settings, actor_id, settings})
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
  def subscribe_lobby(game_id) when is_binary(game_id) do
    PubSub.subscribe(Forka.PubSub, lobby_topic(game_id))
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
    {:reply, Core.to_game_summary(game, opts), game, @timeout_ms}
  end

  @impl true
  def handle_call({:join_game, player_id}, _from, game) do
    with %Player{} = player <- Repository.get_player(player_id),
         {:ok, new_game} <- Core.join_game(game, player) do
      saved_game = save_and_publish!(game, new_game)

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
    case Core.leave_game(game, player_id) do
      {:ok, ^game} ->
        {:reply, :ok, game, @timeout_ms}

      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:update_settings, actor_id, settings}, _from, game) do
    current = RoomSettings.from_game_state(game)
    {norm_lang, valid_uuids} = RoomSettings.extract_lookup_inputs(current, settings)

    allowed_ids =
      if norm_lang in WordOptions.supported_languages() do
        Words.list_category_ids_for_language(norm_lang, valid_uuids)
      else
        []
      end

    case Core.update_settings(game, actor_id, settings, allowed_category_ids: allowed_ids) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    words_count = map_size(game.game_players) * 2
    words = Repository.get_random_words(words_count, game.word_options)
    game_with_words = Core.set_words(game, words)

    case game_with_words |> Core.shuffle_players() |> Core.start_game() do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:give_up, player_id}, _from, game) do
    case Core.give_up_game(game, player_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:guess, letter, player_id}, _from, game) do
    case Core.guess(game, player_id, letter) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call({:transfer_ownership, player_id}, _from, game) do
    case Core.transfer_ownership_to_player(game, player_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:restart_game, _from, game) do
    case Core.restart_game(game) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_call(:archive_game, _from, game) do
    case Core.archive_game(game) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        # Return the response and stop the GenServer with normal reason
        {:stop, :normal, :ok, saved_game}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, game) do
    # Server has been inactive for the timeout period, archive the game and terminate
    case Core.archive_game(game) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:stop, :normal, saved_game}

      {:error, _error} ->
        # Even if archiving fails, we should terminate the server
        {:stop, :normal, game}
    end
  end

  # Private Helpers

  defp topic(game_id), do: "#{@pubsub_topic_prefix}:#{game_id}"
  defp lobby_topic(game_id), do: "room_lobby:#{game_id}"

  defp broadcast!(%GameState{id: game_id} = game_state) do
    game_summary = Core.to_game_summary(game_state)
    PubSub.broadcast!(Forka.PubSub, topic(game_id), {@message_tagger, game_summary})
  end

  defp broadcast_lobby!(%GameState{id: game_id} = game_state) do
    word_options = WordOptions.normalize(game_state.word_options)

    category_names =
      word_options.category_ids
      |> Words.list_categories_by_ids()
      |> Enum.map(& &1.name)

    payload = RoomLobby.payload(game_state, category_names)
    PubSub.broadcast!(Forka.PubSub, lobby_topic(game_id), {:room_lobby_updated, payload})
  end

  defp save_and_publish!(previous, updated) do
    saved = Repository.save_game_state!(updated)
    broadcast!(saved)
    broadcast_lobby!(saved)
    :ok = GameListNotifier.broadcast_update_if_changed(previous, saved)
    saved
  end
end
