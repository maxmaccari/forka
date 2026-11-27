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
  def start_link(game_id) when is_binary(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: global_name(game_id))
  end

  @doc false
  def await_ready(pid, game_id) when is_pid(pid) and is_binary(game_id) do
    if ready?(pid, game_id) do
      {:ok, pid}
    else
      :ok = GenServer.call(pid, :ensure_ready, :infinity)
      {:ok, pid}
    end
  catch
    :exit, {{:shutdown, {:load_error, reason}}, _call} ->
      {:error, reason}

    :exit, {:shutdown, {:load_error, reason}} ->
      {:error, reason}

    :exit, {reason, _call} when reason in [:normal, :noproc] ->
      classify_stopped_game(game_id)

    :exit, reason when reason in [:normal, :noproc] ->
      classify_stopped_game(game_id)
  end

  defp classify_stopped_game(game_id) do
    case Repository.get_game_status(game_id) do
      {:ok, :archived} -> {:error, :game_archived}
      {:ok, _status} -> {:error, :game_server_unavailable}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp global_name(game_id) when is_binary(game_id) do
    {:global, {__MODULE__, game_id}}
  end

  defp ready_key(game_id) when is_binary(game_id) do
    {__MODULE__, :ready, game_id}
  end

  defp ready?(pid, game_id) when is_pid(pid) and is_binary(game_id) do
    GenServer.whereis({:global, ready_key(game_id)}) == pid
  end

  defp server_ref(pid) when is_pid(pid), do: pid
  defp server_ref(game_id) when is_binary(game_id), do: global_name(game_id)

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
  def get_game(server, opts \\ []) when is_pid(server) or is_binary(server) do
    GenServer.call(server_ref(server), {:get_game, opts})
  end

  @doc false
  def join_room(server, player_id)
      when (is_pid(server) or is_binary(server)) and is_binary(player_id) do
    GenServer.call(server_ref(server), {:join_room, player_id})
  end

  @doc false
  def leave_game(server, player_id, opts \\ [])
      when (is_pid(server) or is_binary(server)) and is_binary(player_id) and is_list(opts) do
    GenServer.call(server_ref(server), {:leave_game, player_id, opts})
  end

  @doc false
  def remove_player(server, player_id)
      when (is_pid(server) or is_binary(server)) and is_binary(player_id) do
    GenServer.call(server_ref(server), {:remove_player, player_id})
  end

  @doc false
  def update_settings(server, actor_id, settings)
      when (is_pid(server) or is_binary(server)) and is_binary(actor_id) and is_map(settings) do
    GenServer.call(server_ref(server), {:update_settings, actor_id, settings})
  end

  @doc false
  def start_game(server, actor_id)
      when (is_pid(server) or is_binary(server)) and is_binary(actor_id) do
    GenServer.call(server_ref(server), {:start_game, actor_id})
  end

  @doc false
  def give_up_game(server, player_id)
      when (is_pid(server) or is_binary(server)) and is_binary(player_id) do
    GenServer.call(server_ref(server), {:give_up, player_id})
  end

  @doc false
  def guess(server, player_id, letter)
      when (is_pid(server) or is_binary(server)) and is_binary(letter) and is_binary(player_id) do
    GenServer.call(server_ref(server), {:guess, letter, player_id})
  end

  @doc false
  def transfer_ownership(server, actor_id, target_player_id, opts \\ [])
      when (is_pid(server) or is_binary(server)) and is_binary(actor_id) and
             is_binary(target_player_id) and is_list(opts) do
    GenServer.call(
      server_ref(server),
      {:transfer_ownership, actor_id, target_player_id, opts}
    )
  end

  @doc false
  def restart_game(server, actor_id)
      when (is_pid(server) or is_binary(server)) and is_binary(actor_id) do
    GenServer.call(server_ref(server), {:restart_game, actor_id})
  end

  @doc false
  def archive_game(server, actor_id)
      when (is_pid(server) or is_binary(server)) and is_binary(actor_id) do
    GenServer.call(server_ref(server), {:archive_game, actor_id})
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
  def init(game_id) when is_binary(game_id) do
    {:ok, {:loading, game_id}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, {:loading, game_id}) do
    case load_and_reconcile_game(game_id) do
      {:ok, %GameState{status: :archived} = archived} ->
        {:stop, :normal, archived}

      {:ok, %GameState{} = game_state} ->
        :global.re_register_name(ready_key(game_id), self())
        {:noreply, game_state, @timeout_ms}

      {:error, :not_found} ->
        {:stop, :normal, {:loading, game_id}}

      {:error, reason} ->
        {:stop, {:shutdown, {:load_error, reason}}, {:loading, game_id}}
    end
  end

  @impl true
  def handle_call(:ensure_ready, _from, %GameState{} = game) do
    {:reply, :ok, game, @timeout_ms}
  end

  def handle_call(request, from, game) do
    case reconcile_running_state(game) do
      {:archived, saved} -> {:stop, :normal, archived_reply(request, saved), saved}
      {:ok, reconciled} -> handle_reconciled_call(request, from, reconciled)
    end
  end

  defp archived_reply({:get_game, opts}, saved), do: Core.to_game_summary(saved, opts)
  defp archived_reply(_request, _saved), do: {:error, :game_archived}

  defp handle_reconciled_call({:get_game, opts}, _from, game) do
    {:reply, Core.to_game_summary(game, opts), game, @timeout_ms}
  end

  defp handle_reconciled_call({:join_room, player_id}, _from, game) do
    with %Player{} = player <- Repository.get_player(player_id),
         {:ok, status, new_game} <- Core.join_room(game, player) do
      saved_game =
        case status do
          :joined -> save_and_publish!(game, new_game)
          _existing -> game
        end

      {:reply, {:ok, status}, saved_game, @timeout_ms}
    else
      nil ->
        {:reply, {:error, :player_not_found}, game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:leave_game, player_id, opts}, _from, game) do
    case Core.leave_game(game, player_id, opts) do
      {:ok, %GameState{status: :archived} = new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:stop, :normal, :ok, saved_game}

      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:reply, :ok, saved_game, @timeout_ms}

      {:error, :confirmation_required} ->
        {:reply, {:error, {:confirmation_required, build_lobby_payload(game)}}, game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:remove_player, player_id}, _from, game) do
    case Core.remove_player(game, player_id) do
      :unchanged ->
        {:reply, :ok, game, @timeout_ms}

      {:changed, %GameState{status: :archived} = archived} ->
        case save_and_publish(game, archived) do
          {:ok, saved_game} -> {:stop, :normal, :ok, saved_game}
          {:error, reason} -> {:reply, {:error, reason}, game, @timeout_ms}
        end

      {:changed, updated} ->
        case save_and_publish(game, updated) do
          {:ok, saved_game} -> {:reply, :ok, saved_game, @timeout_ms}
          {:error, reason} -> {:reply, {:error, reason}, game, @timeout_ms}
        end
    end
  end

  defp handle_reconciled_call({:update_settings, actor_id, settings}, _from, game) do
    with :ok <- Core.authorize_settings_update(game, actor_id),
         {:ok, validated} <- validate_room_settings(game, settings),
         {:ok, new_game} <- Core.update_settings(game, actor_id, validated) do
      saved_game = save_and_publish!(game, new_game)
      {:reply, :ok, saved_game, @timeout_ms}
    else
      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:start_game, actor_id}, _from, game) do
    case do_start_game(game, actor_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:give_up, player_id}, _from, game) do
    case Core.give_up_game(game, player_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:guess, letter, player_id}, _from, game) do
    case Core.guess(game, player_id, letter) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)

        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call(
         {:transfer_ownership, actor_id, target_player_id, opts},
         _from,
         game
       ) do
    case Core.transfer_ownership_to_player(game, actor_id, target_player_id, opts) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:restart_game, actor_id}, _from, game) do
    case Core.restart_game(game, actor_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:reply, :ok, saved_game, @timeout_ms}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  defp handle_reconciled_call({:archive_game, actor_id}, _from, game) do
    case Core.archive_game(game, actor_id) do
      {:ok, new_game} ->
        saved_game = save_and_publish!(game, new_game)
        {:stop, :normal, :ok, saved_game}

      {:error, error} ->
        {:reply, {:error, error}, game, @timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, game) do
    case reconcile_running_state(game) do
      {:archived, saved} -> {:stop, :normal, saved}
      {:ok, reconciled} -> archive_idle_game(reconciled)
    end
  end

  # Server has been inactive for the timeout period, archive the game and terminate.
  # Even if archiving fails (a game in progress), the server still terminates.
  defp archive_idle_game(game) do
    case Core.archive_game(game) do
      {:ok, new_game} -> {:stop, :normal, save_and_publish!(game, new_game)}
      {:error, _error} -> {:stop, :normal, game}
    end
  end

  # Private Helpers

  defp load_and_reconcile_game(game_id, retries \\ 1) do
    case Repository.reconcile_game_state(game_id, &Core.reconcile_missing_players/2) do
      {:ok, :unchanged, state} ->
        {:ok, state}

      {:ok, :reconciled, previous, saved} ->
        publish_state!(previous, saved)
        {:ok, saved}

      {:error, %Ecto.Changeset{}} when retries > 0 ->
        load_and_reconcile_game(game_id, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  defp reconcile_running_state(%GameState{status: :archived} = game_state),
    do: {:archived, game_state}

  defp reconcile_running_state(%GameState{} = game_state) do
    existing_ids =
      game_state
      |> referenced_player_ids()
      |> Repository.existing_player_ids()

    case Core.reconcile_missing_players(game_state, existing_ids) do
      :unchanged ->
        {:ok, game_state}

      {:changed, %GameState{status: :archived} = archived} ->
        {:archived, save_and_publish!(game_state, archived)}

      {:changed, updated} ->
        {:ok, save_and_publish!(game_state, updated)}
    end
  end

  defp referenced_player_ids(%GameState{owner: owner, game_players: game_players}) do
    seated_ids = Enum.map(game_players, fn {_idx, gp} -> gp.player.id end)

    case owner do
      %{id: owner_id} when is_binary(owner_id) -> [owner_id | seated_ids]
      _ -> seated_ids
    end
  end

  defp topic(game_id), do: "#{@pubsub_topic_prefix}:#{game_id}"
  defp lobby_topic(game_id), do: "room_lobby:#{game_id}"

  defp broadcast!(%GameState{id: game_id} = game_state) do
    game_summary = Core.to_game_summary(game_state)
    PubSub.broadcast!(Forka.PubSub, topic(game_id), {@message_tagger, game_summary})
  end

  defp broadcast_lobby!(%GameState{id: game_id} = game_state) do
    payload = build_lobby_payload(game_state)
    PubSub.broadcast!(Forka.PubSub, lobby_topic(game_id), {:room_lobby_updated, payload})
  end

  defp build_lobby_payload(%GameState{} = game_state) do
    word_options = WordOptions.normalize(game_state.word_options)

    category_names =
      word_options.category_ids
      |> Words.list_categories_by_ids()
      |> Enum.map(& &1.name)

    available_words =
      if game_state.status == :lobby do
        Repository.count_available_words(word_options)
      else
        nil
      end

    RoomLobby.payload(game_state, category_names, available_words)
  end

  defp validate_room_settings(game, settings) do
    current = RoomSettings.from_game_state(game)
    occupancy = max(Core.min_players_allowed(), map_size(game.game_players))
    {norm_lang, valid_uuids} = RoomSettings.extract_lookup_inputs(current, settings)

    allowed_ids =
      if norm_lang in WordOptions.supported_languages() do
        Words.list_category_ids_for_language(norm_lang, valid_uuids)
      else
        []
      end

    case RoomSettings.changeset(current, settings,
           min_players: occupancy,
           allowed_category_ids: allowed_ids
         ) do
      %Ecto.Changeset{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      %Ecto.Changeset{valid?: false} = changeset ->
        {:error, changeset}
    end
  end

  defp save_and_publish(previous, updated) do
    with {:ok, saved} <- Repository.save_game_state(updated) do
      publish_state!(previous, saved)
      {:ok, saved}
    end
  end

  defp save_and_publish!(previous, updated) do
    saved = Repository.save_game_state!(updated)
    publish_state!(previous, saved)
    saved
  end

  defp publish_state!(previous, saved) do
    broadcast!(saved)
    broadcast_lobby!(saved)
    :ok = GameListNotifier.broadcast_update_if_changed(previous, saved)
  end

  defp do_start_game(game, actor_id) do
    with :ok <- Core.authorize_start(game, actor_id),
         :ok <- Core.validate_start_roster(game) do
      required = Core.required_words_for_players(map_size(game.game_players))
      words = Repository.get_random_words(required, game.word_options)

      game
      |> Core.set_words(words)
      |> Core.shuffle_players()
      |> Core.start_game(actor_id)
    end
  end
end
