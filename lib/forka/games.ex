defmodule Forka.Games do
  @moduledoc """
  The Games context.

  Depends on: Forka.Words.

  This module serves as the public interface for all game-related operations in the Forka application.
  It provides a complete API for managing games, including:

  - Game lifecycle (create, start, restart, archive)
  - Player management (join, leave, transfer ownership)
  - Gameplay operations (make guesses, give up)
  - Game state monitoring (subscribe to updates)
  - Game settings management

  All operations are handled through game servers, ensuring each game maintains its own
  isolated state and can handle concurrent player interactions safely.

  This is the only module that should be used by other contexts to interact with games.
  Internal implementation details are handled by other modules in the Games context.
  """

  import Ecto.Query

  alias Forka.Games.GameListNotifier
  alias Forka.Games.GameServer
  alias Forka.Games.GameSummary
  alias Forka.Games.Repository
  alias Forka.Games.RoomInvite
  alias Forka.Games.RoomListItem
  alias Forka.Games.RoomLobby
  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Players.Player, as: AuthPlayer
  alias Forka.Repo
  alias Forka.Scope
  alias Forka.Words

  @directory_limit 60

  @doc """
  Returns the maximum number of rooms returned by the public directory query.
  """
  @spec directory_limit() :: pos_integer()
  def directory_limit, do: @directory_limit

  @doc """
  Lists games with pagination and optional filtering.

  ## Parameters

    * `opts` - A keyword list of options:
      * `:page` - The page number (default: 1)
      * `:per_page` - Number of games per page (default: 10)
      * `:game_status` - Filter games by status (e.g., :lobby, :playing, :archived)

  ## Examples

      iex> list_games()
      %{games: [%Game{}, ...], games_count: 10}

      iex> list_games(page: 2, per_page: 5, game_status: :playing)
      %{games: [%Game{}, ...], games_count: 15}

  ## Returns

  A map containing:
  - `games` - A list of games for the requested page
  - `games_count` - The total count of games matching the filter criteria
  """
  @spec list_games(keyword()) :: %{games: [Game.t()], games_count: non_neg_integer()}
  def list_games(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    game_status = Keyword.get(opts, :game_status)

    offset = (page - 1) * per_page

    query =
      from g in Game,
        order_by: [desc: g.inserted_at]

    query =
      if game_status do
        from g in query, where: g.status == ^game_status
      else
        query
      end

    games =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    games_count =
      query
      |> exclude(:order_by)
      |> exclude(:limit)
      |> exclude(:offset)
      |> select(count())
      |> Repo.one()

    %{
      games: games,
      games_count: games_count
    }
  end

  @doc """
  Lists rooms visible in the public live room directory.

  Excludes `:archived` games, caps the result set at `directory_limit/0` (newest first),
  aggregates current player counts, and resolves word category names in a single batched
  call to `Forka.Words`.
  """
  @spec list_directory_rooms(keyword()) :: [RoomListItem.t()]
  def list_directory_rooms(opts \\ []) do
    list_directory_rooms_page(opts).rooms
  end

  @doc """
  Lists a bounded page of rooms visible in the public live room directory along with
  whether additional older rooms exist beyond the page cap.

  Queries `limit + 1` rows (with `limit` capped server-side at `directory_limit/0`)
  so callers can tell an exact page-sized result apart from a truncated one.
  """
  @spec list_directory_rooms_page(keyword()) :: %{
          rooms: [RoomListItem.t()],
          has_more?: boolean()
        }
  def list_directory_rooms_page(opts \\ []) do
    limit = opts |> Keyword.get(:limit, @directory_limit) |> cap_directory_limit()
    visible_statuses = RoomListItem.visible_statuses()

    rows =
      from(g in Game,
        left_join: gp in assoc(g, :game_players),
        left_join: o in assoc(g, :owner),
        where: g.status in ^visible_statuses,
        group_by: [g.id, o.id],
        order_by: [desc: g.inserted_at, desc: g.id],
        limit: ^(limit + 1),
        select: %{
          game: g,
          owner_username: o.username,
          player_count: count(gp.id)
        }
      )
      |> Repo.all()

    {page_rows, extra_rows} = Enum.split(rows, limit)

    category_ids =
      page_rows
      |> Enum.flat_map(fn %{game: game} -> extract_category_ids(game.word_options) end)
      |> Enum.uniq()

    categories_by_id =
      category_ids
      |> Words.list_categories_by_ids()
      |> Map.new(&{&1.id, &1.name})

    rooms =
      Enum.map(page_rows, fn %{
                               game: game,
                               owner_username: owner_username,
                               player_count: player_count
                             } ->
        RoomListItem.from_game(game, player_count, owner_username, categories_by_id)
      end)

    %{rooms: rooms, has_more?: extra_rows != []}
  end

  defp cap_directory_limit(limit) when is_integer(limit) and limit > 0,
    do: min(limit, @directory_limit)

  defp cap_directory_limit(_), do: @directory_limit

  defp extract_category_ids(%WordOptions{category_ids: ids}) when is_list(ids), do: ids
  defp extract_category_ids(_), do: []

  @doc """
  Converts a `:game_list_updated` PubSub payload into a `RoomListItem` read model.
  """
  @spec room_list_item_from_event(map()) :: RoomListItem.t()
  def room_list_item_from_event(payload) when is_map(payload) do
    RoomListItem.from_event(payload)
  end

  @doc "Returns the list of supported word languages."
  @spec supported_languages() :: [String.t()]
  def supported_languages, do: WordOptions.supported_languages()

  @doc "Builds a changeset for room settings validation."
  @spec change_room_settings(RoomSettings.t(), map(), keyword()) ::
          Ecto.Changeset.t(RoomSettings.t())
  def change_room_settings(%RoomSettings{} = settings, attrs \\ %{}, opts \\ []) do
    RoomSettings.changeset(settings, attrs, opts)
  end

  @doc "Creates a room for the scoped authenticated player."
  @spec create_room(Scope.t() | nil, map()) ::
          {:ok, Game.t()}
          | {:error, Ecto.Changeset.t() | :unauthorized | term()}
          | :ignore
          | {:ok, pid(), term()}
  def create_room(scope, params \\ %{})

  def create_room(%Scope{player: %AuthPlayer{id: owner_id}}, params) when is_map(params) do
    create_game(owner_id, params)
  end

  def create_room(_invalid_scope, _params), do: {:error, :unauthorized}

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
  @spec create_game(Ecto.UUID.t(), map()) ::
          {:ok, Game.t()} | {:error, term()} | :ignore | {:ok, pid(), term()}
  def create_game(owner_id, params \\ %{}) do
    {norm_lang, valid_uuids} =
      RoomSettings.extract_lookup_inputs(
        %RoomSettings{word_options: %WordOptions{language: "en", category_ids: []}},
        params
      )

    allowed_ids =
      if norm_lang in WordOptions.supported_languages() do
        Words.list_category_ids_for_language(norm_lang, valid_uuids)
      else
        []
      end

    with {:ok, game} <-
           Repository.insert_game(owner_id, params, allowed_category_ids: allowed_ids),
         {:ok, _pid} <- start_supervised_game(game.id) do
      game
      |> Repo.preload([:owner, {:game_players, :player}, :game_words])
      |> Game.to_game_state()
      |> GameListNotifier.broadcast_created()

      {:ok, game}
    end
  end

  defp start_supervised_game(game_id) do
    case DynamicSupervisor.start_child(Forka.GamesSupervisor, {GameServer, game_id}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      result -> result
    end
  end

  @doc """
  Updates the settings of a game if the actor is the owner and the game is in the lobby.
  """
  @spec update_settings(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          :ok
          | {:error,
             Ecto.Changeset.t() | :unauthorized | :game_not_in_lobby | :game_archived | :not_found}
  def update_settings(game_id, actor_id, settings)
      when is_binary(game_id) and is_binary(actor_id) and is_map(settings) do
    ensure_game_server_available(game_id, fn ->
      GameServer.update_settings(game_id, actor_id, settings)
    end)
  end

  @doc "Updates room settings for the scoped authenticated owner while the room is in lobby."
  @spec update_room_settings(Scope.t() | nil, Ecto.UUID.t(), map()) ::
          :ok
          | {:error,
             Ecto.Changeset.t() | :unauthorized | :game_not_in_lobby | :game_archived | :not_found}
  def update_room_settings(%Scope{player: %AuthPlayer{id: actor_id}}, game_id, settings)
      when is_map(settings) do
    case Ecto.UUID.cast(game_id) do
      {:ok, valid_id} -> update_settings(valid_id, actor_id, settings)
      :error -> {:error, :not_found}
    end
  end

  def update_room_settings(_invalid_scope, _game_id, _settings), do: {:error, :unauthorized}

  @doc "Returns the lobby projection for an existing room scoped to an authenticated viewer."
  @spec get_room_lobby(Scope.t() | nil, Ecto.UUID.t()) ::
          {:ok, RoomLobby.t()} | {:error, :not_found | :unauthorized | :game_archived}
  def get_room_lobby(%Scope{player: %AuthPlayer{}} = scope, game_id) do
    with {:ok, valid_id, summary, category_names, available_words} <-
           fetch_room_summary_with_categories(game_id) do
      {:ok,
       RoomLobby.from_game_summary(scope, valid_id, summary, category_names, available_words)}
    end
  end

  def get_room_lobby(_invalid_scope, _game_id), do: {:error, :unauthorized}

  @doc "Returns the public invitation preview for an existing non-archived room without starting its GameServer."
  @spec get_room_invite(Ecto.UUID.t()) ::
          {:ok, RoomInvite.t()} | {:error, :not_found | :game_archived}
  def get_room_invite(game_id) do
    with {:ok, valid_id} <- Ecto.UUID.cast(game_id),
         %{game: game, owner_username: owner_username, player_count: player_count} <-
           fetch_persisted_room_invite_row(valid_id) do
      if game.status == :archived do
        {:error, :game_archived}
      else
        category_names =
          game.word_options
          |> extract_category_ids()
          |> Words.list_categories_by_ids()
          |> Enum.map(& &1.name)

        {:ok, RoomInvite.from_game(game, player_count, owner_username, category_names)}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_persisted_room_invite_row(game_id) do
    from(g in Game,
      left_join: gp in assoc(g, :game_players),
      left_join: o in assoc(g, :owner),
      where: g.id == ^game_id,
      group_by: [g.id, o.id],
      select: %{
        game: g,
        owner_username: o.username,
        player_count: count(gp.id)
      }
    )
    |> Repo.one()
  end

  @doc "Returns true when the scoped player is already a persisted participant in the room."
  @spec room_participant?(Scope.t() | nil, Ecto.UUID.t()) :: boolean()
  def room_participant?(%Scope{player: %AuthPlayer{id: player_id}}, game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, valid_id} ->
        from(gp in GamePlayer,
          where: gp.game_id == ^valid_id and gp.player_id == ^player_id
        )
        |> Repo.exists?()

      :error ->
        false
    end
  end

  def room_participant?(_invalid_scope, _game_id), do: false

  defp fetch_room_summary_with_categories(game_id) do
    with {:ok, valid_id} <- Ecto.UUID.cast(game_id),
         {:ok, %GameSummary{} = summary} <- fetch_game_summary(valid_id) do
      word_options = WordOptions.normalize(summary.word_options)

      category_names =
        word_options.category_ids
        |> Words.list_categories_by_ids()
        |> Enum.map(& &1.name)

      available_words =
        if summary.game_status == :lobby do
          Repository.count_available_words(word_options)
        else
          nil
        end

      {:ok, valid_id, summary, category_names, available_words}
    else
      :error -> {:error, :not_found}
      {:error, :game_archived} -> {:error, :game_archived}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  @doc "Subscribes an authenticated viewer to lobby-safe updates for a room."
  @spec subscribe_to_room_lobby(Scope.t() | nil, Ecto.UUID.t()) ::
          :ok | {:error, :not_found | :unauthorized | :game_archived}
  def subscribe_to_room_lobby(%Scope{player: %AuthPlayer{}}, game_id) do
    with {:ok, valid_id} <- Ecto.UUID.cast(game_id),
         {:ok, %GameSummary{}} <- fetch_game_summary(valid_id) do
      GameServer.subscribe_lobby(valid_id)
    else
      :error -> {:error, :not_found}
      {:error, :game_archived} -> {:error, :game_archived}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  def subscribe_to_room_lobby(_invalid_scope, _game_id), do: {:error, :unauthorized}

  @doc "Projects a `:room_lobby_updated` PubSub payload for the given authenticated viewer."
  @spec room_lobby_from_payload(Scope.t() | nil, map()) ::
          {:ok, RoomLobby.t()} | {:error, :unauthorized}
  def room_lobby_from_payload(%Scope{player: %AuthPlayer{}} = scope, payload)
      when is_map(payload) do
    {:ok, RoomLobby.from_payload(scope, payload)}
  end

  def room_lobby_from_payload(_invalid_scope, _payload), do: {:error, :unauthorized}

  @doc "Loads room settings for editing, enforcing authenticated owner and `:lobby` state."
  @spec get_room_settings_for_edit(Scope.t() | nil, Ecto.UUID.t()) ::
          {:ok, %{settings: RoomSettings.t(), min_players: pos_integer()}}
          | {:error, :not_found | :unauthorized | :game_not_in_lobby | :game_archived}
  def get_room_settings_for_edit(%Scope{player: %AuthPlayer{id: actor_id}}, game_id) do
    with {:ok, valid_id} <- Ecto.UUID.cast(game_id),
         {:ok, %GameSummary{} = summary} <- fetch_game_summary(valid_id) do
      cond do
        summary.owner == nil or summary.owner.id != actor_id ->
          {:error, :unauthorized}

        summary.game_status != :lobby ->
          {:error, :game_not_in_lobby}

        true ->
          {:ok,
           %{
             settings: RoomSettings.from_game_summary(summary),
             min_players: max(2, map_size(summary.players))
           }}
      end
    else
      :error -> {:error, :not_found}
      {:error, :game_archived} -> {:error, :game_archived}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  def get_room_settings_for_edit(_invalid_scope, _game_id), do: {:error, :unauthorized}

  @doc """
  Adds a player to the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to join.

  ## Returns
    - `:ok` if the player successfully joined the game
    - `{:error, reason}` if the player could not join
  """
  @spec join_game(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def join_game(game_id, player_id) do
    ensure_game_server_available(game_id, fn -> GameServer.join_game(game_id, player_id) end)
  end

  @doc """
  Joins a room for the scoped authenticated player, distinguishing new joins from returning participants.
  """
  @spec join_room(Scope.t() | nil, Ecto.UUID.t()) ::
          {:ok, :joined | :already_joined | :returning_participant}
          | {:error,
             :unauthorized
             | :not_found
             | :game_archived
             | :maximum_players
             | :game_already_started
             | :game_ended
             | :player_not_found}
  def join_room(%Scope{player: %AuthPlayer{id: player_id}}, game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, valid_id} ->
        ensure_game_server_available(valid_id, fn ->
          GameServer.join_room(valid_id, player_id)
        end)

      :error ->
        {:error, :not_found}
    end
  end

  def join_room(_invalid_scope, _game_id), do: {:error, :unauthorized}

  @doc """
  Removes a player from the game.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to leave.

  ## Returns
    - `:ok` if the player successfully left the game
    - `{:error, reason}` if the player could not leave
  """
  @spec leave_game(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
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
  @spec start_game(Ecto.UUID.t()) :: :ok | {:error, term()}
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
  @spec give_up_game(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
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
  @spec guess(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: :ok | {:error, term()}
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
  @spec transfer_ownership(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
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
  @spec restart_game(Ecto.UUID.t()) :: :ok | {:error, term()}
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
  @spec archive_game(Ecto.UUID.t()) :: :ok | {:error, term()}
  def archive_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.archive_game(game_id) end)
  end

  @doc """
  Gets the current game summary.

  ## Parameters
    - game_id: The ID of the game.
    - opts: (optional) Options for retrieving the game summary:
      - load_all_events: When true, includes all game events in the summary (default: false)

  ## Returns
    - A GameSummary struct containing the current game state if found
    - `nil` if the game does not exist
  """
  @spec get_game_summary(Ecto.UUID.t(), keyword()) :: GameSummary.t() | nil
  def get_game_summary(game_id, opts \\ []) do
    ensure_game_server_available_with_nil(game_id, fn -> GameServer.get_game(game_id, opts) end)
  end

  @doc """
  Subscribes the caller to receive updates for the game list.

  ## Returns
    - `:ok` if the subscription is successful
  """
  @spec subscribe_to_game_list() :: :ok | {:error, term()}
  def subscribe_to_game_list do
    GameListNotifier.subscribe()
  end

  @doc """
  Unsubscribes the caller from receiving updates for the game list.

  ## Returns
    - `:ok` if the unsubscription is successful
  """
  @spec unsubscribe_from_game_list() :: :ok
  def unsubscribe_from_game_list do
    GameListNotifier.unsubscribe()
  end

  @doc """
  Subscribes the caller to receive updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to subscribe to.

  ## Returns
    - `:ok` if the subscription is successful
    - `{:error, reason}` if the subscription fails
  """
  @spec subscribe_to_game(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_to_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.subscribe(game_id) end)
  end

  @doc """
  Unsubscribes the caller from receiving updates for a specific game.

  ## Parameters
    - game_id: The ID of the game to unsubscribe from.

  ## Returns
    - `:ok` if the unsubscription is successful
    - `{:error, reason}` if the unsubscription fails
  """
  @spec unsubscribe_from_game(Ecto.UUID.t()) :: :ok | {:error, term()}
  def unsubscribe_from_game(game_id) do
    ensure_game_server_available(game_id, fn -> GameServer.unsubscribe(game_id) end)
  end

  defp fetch_game_summary(game_id) do
    case ensure_game_server_available(game_id, fn -> {:ok, GameServer.get_game(game_id)} end) do
      {:ok, %GameSummary{game_status: :archived}} -> {:error, :game_archived}
      other -> other
    end
  end

  defp ensure_game_server_available(game_id, action) do
    if GameServer.exists?(game_id) do
      action.()
    else
      start_and_run_game_server(game_id, action)
    end
  end

  defp start_and_run_game_server(game_id, action) do
    case Repository.get_game_state(game_id) do
      {:ok, %{status: :archived}} ->
        {:error, :game_archived}

      {:ok, _game_state} ->
        with {:ok, _pid} <- start_supervised_game(game_id) do
          action.()
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp ensure_game_server_available_with_nil(game_id, action) do
    case ensure_game_server_available(game_id, action) do
      {:error, :not_found} -> nil
      {:error, error} -> raise "Game server error: #{inspect(error)}"
      result -> result
    end
  end
end
