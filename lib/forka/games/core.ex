defmodule Forka.Games.Core do
  @moduledoc "Applies the rules of a game to its in-memory state."

  alias Forka.Games.Core.GameLogic
  alias Forka.Games.Core.GameState
  alias Forka.Games.GameSummary
  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.{Player, Word, WordOptions}

  import Forka.Games.Core.Helpers,
    only: [
      authorize_owner: 2,
      find_game_player_by_id: 2,
      increment_tick: 1,
      participant?: 2,
      push_event: 2,
      push_event: 3
    ]

  @min_players_allowed 2
  @max_players_allowed 6

  @doc """
  Creates a new game state with the given name and maximum number of players.

  ## Parameters
    - owner: The player who created the game
    - name: The name of the game (string)
    - max_players: Maximum number of players allowed (integer)
    - opts: Optional parameters:
      - word_options: Options for word selection:
        - language: Language for the game words (default: "en")
        - category_ids: List of category IDs to filter words (default: [])

  ## Returns
  A new GameState struct with:
  - A unique UUID as id
  - The provided name and max_players
  - Default empty values for game_words and game_players
  - Initial :lobby status
  - No current word or player selected
  - Specified options for words (defaults to language: "en")

  ## Examples
      iex> GameState.new(owner, "Fun Game", 4)
      %Forka.Games.GameState{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "Fun Game",
        max_players: 4,
        status: :lobby,
        game_words: %{},
        game_players: %{},
        current_game_word_index: nil,
        current_game_player_index: nil,
        word_options: [language: "en"]
      }

      iex> GameState.new(owner, "Jogo Divertido", 4, word_options: [language: "pt", category_ids: ["uuid1", "uuid2"]])
      %Forka.Games.GameState{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "Jogo Divertido",
        max_players: 4,
        status: :lobby,
        game_words: %{},
        game_players: %{},
        current_game_word_index: nil,
        current_game_player_index: nil,
        word_options: [language: "pt", category_ids: ["uuid1", "uuid2"]]
      }
  """
  @spec new(Player.t(), String.t(), integer(), keyword()) :: GameState.t()
  def new(%Player{} = owner, name, max_players, opts \\ [])
      when is_binary(name) and is_integer(max_players) do
    word_options = Keyword.get(opts, :word_options, language: "en")

    %GameState{
      id: UUID.uuid4(),
      name: name,
      owner: owner,
      max_players: max_players,
      word_options: word_options
    }
  end

  @doc """
  Adds a player to the game state while in lobby state.

  ## Parameters
    - game_state: The GameState struct
    - player: The Player struct to be added

  ## Returns
  - `{:ok, game_state}` if player was successfully added
  - `{:error, :maximum_players}` if game state already has maximum number of players
  - `{:error, :game_already_started}` if game state is not in lobby state
  - `{:error, :game_archived}` if game state is archived

  The player is converted to a GamePlayer and added to the game state's game_players map.
  """
  @spec join_game(GameState.t(), Player.t()) ::
          {:ok, GameState.t()}
          | {:error, :maximum_players | :game_archived | :game_already_started}
  def join_game(
        %GameState{game_players: game_players, status: :lobby} = game_state,
        %Player{} = player
      ) do
    new_game_players = add_game_player_to_map(game_players, player)

    if map_size(new_game_players) <= game_state.max_players do
      new_game_state =
        %{game_state | game_players: new_game_players}
        |> increment_tick()
        |> push_event(:player_joined, player)

      {:ok, new_game_state}
    else
      {:error, :maximum_players}
    end
  end

  def join_game(%GameState{status: :archived}, %Player{}), do: {:error, :game_archived}

  def join_game(_game_state, %Player{}), do: {:error, :game_already_started}

  @doc """
  Evaluates joining a room for a player, distinguishing a new join from an existing participant.
  """
  @spec join_room(GameState.t(), Player.t()) ::
          {:ok, :joined | :already_joined | :returning_participant, GameState.t()}
          | {:error, :maximum_players | :game_already_started | :game_ended | :game_archived}
  def join_room(%GameState{status: :archived}, %Player{}), do: {:error, :game_archived}

  def join_room(
        %GameState{status: :lobby} = game_state,
        %Player{} = player
      ) do
    if participant?(game_state, player.id) do
      {:ok, :already_joined, game_state}
    else
      case join_game(game_state, player) do
        {:ok, updated} -> {:ok, :joined, updated}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def join_room(
        %GameState{status: status} = game_state,
        %Player{} = player
      )
      when status in [:playing, :finished, :game_over] do
    if participant?(game_state, player.id) do
      {:ok, :returning_participant, game_state}
    else
      case status do
        :playing -> {:error, :game_already_started}
        _ended -> {:error, :game_ended}
      end
    end
  end

  defp add_game_player_to_map(%{} = game_players, %Player{} = player) do
    (Map.values(game_players) ++ [GamePlayer.new(player)])
    |> Enum.uniq_by(& &1.player.id)
    |> indexed_map()
  end

  @doc """
  Removes a participating player from the game state while in lobby state.

  ## Parameters
    - game_state: The GameState struct
    - player_id: The ID of the participating player to remove

  ## Returns
    - `{:ok, game_state}` if the player was successfully removed
    - `{:error, :game_archived}` if the game state is archived
    - `{:error, :not_a_participant}` if the player is not seated in the game
    - `{:error, :game_already_started}` if the game state is not in lobby state
  """
  @spec leave_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()}
          | {:error, :game_archived | :not_a_participant | :game_already_started}
  def leave_game(%GameState{status: :archived}, player_id) when is_binary(player_id),
    do: {:error, :game_archived}

  def leave_game(%GameState{} = game_state, player_id) when is_binary(player_id) do
    case find_game_player_by_id(game_state, player_id) do
      nil ->
        {:error, :not_a_participant}

      {_idx, %{player: left_player}} ->
        if game_state.status == :lobby do
          new_game_players =
            game_state.game_players
            |> Map.values()
            |> Enum.reject(&(&1.player.id == player_id))
            |> indexed_map()

          new_game_state =
            %{game_state | game_players: new_game_players}
            |> increment_tick()
            |> push_event(:player_left, left_player)

          {:ok, new_game_state}
        else
          {:error, :game_already_started}
        end
    end
  end

  @doc """
  Sets the words for the game state.

  ## Parameters
    - game_state: The GameState struct to update
    - words: List of words to add to the game state

  ## Returns
    - A GameState struct with game_words set if the game is in lobby state
    - The unchanged game_state if the game is not in lobby state
  """
  @spec set_words(GameState.t(), [Word.t()]) :: GameState.t()
  def set_words(%GameState{status: :lobby} = game_state, words) when is_list(words) do
    new_game_words =
      words
      |> Enum.uniq()
      |> indexed_map(&GameWord.new/1)

    %{game_state | game_words: new_game_words}
    |> increment_tick()
    |> push_event(:words_set, %{count: map_size(new_game_words)})
  end

  def set_words(%GameState{} = game_state, words) when is_list(words),
    do: game_state

  @doc """
  Shuffles the players in the game state.

  ## Parameters
    - game_state: The GameState struct containing players to shuffle

  ## Returns
    - A GameState struct with players in a randomized order if the game is in lobby state
    - The unchanged game_state if the game is not in lobby state

  ## Examples
      iex> game_state = %GameState{status: :lobby, game_players: %{0 => player1, 1 => player2, 2 => player3}}
      iex> shuffled = Game.shuffle_players(game_state)
      iex> Map.keys(shuffled.game_players) == Map.keys(game_state.game_players)
      true
      iex> Map.values(shuffled.game_players) |> Enum.sort() == Map.values(game_state.game_players) |> Enum.sort()
      true
  """
  @spec shuffle_players(GameState.t()) :: GameState.t()
  def shuffle_players(%GameState{game_players: game_players, status: :lobby} = game_state) do
    shuffled_game_players =
      game_players
      |> Map.values()
      |> Enum.shuffle()
      |> indexed_map()

    %{game_state | game_players: shuffled_game_players}
    |> increment_tick()
    |> push_event(:players_shuffled)
  end

  def shuffle_players(%GameState{} = game_state),
    do: game_state

  @doc "Checks whether `actor_id` is allowed to start `game_state`."
  @spec authorize_start(GameState.t(), Ecto.UUID.t()) ::
          :ok | {:error, :game_archived | :unauthorized | :game_already_initialized}
  def authorize_start(%GameState{status: :archived}, actor_id) when is_binary(actor_id),
    do: {:error, :game_archived}

  def authorize_start(%GameState{} = game_state, actor_id) when is_binary(actor_id) do
    with :ok <- authorize_owner(game_state, actor_id) do
      if game_state.status == :lobby do
        :ok
      else
        {:error, :game_already_initialized}
      end
    end
  end

  @doc "Initializes a lobby game for `actor_id` if they are the owner and the game is ready."
  @spec start_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()}
          | {:error, :game_archived | :unauthorized | :game_already_initialized | :game_not_ready}
  def start_game(%GameState{} = game_state, actor_id) when is_binary(actor_id) do
    with :ok <- authorize_start(game_state, actor_id) do
      if can_start?(game_state) do
        new_game_state =
          %{
            game_state
            | current_game_word_index: 0,
              current_game_player_index: 0,
              status: :playing
          }
          |> increment_tick()
          |> push_event(:game_started)

        {:ok, new_game_state}
      else
        {:error, :game_not_ready}
      end
    end
  end

  defp can_start?(%GameState{game_players: game_players, game_words: game_words}) do
    map_size(game_players) >= 2 and map_size(game_words) >= 1
  end

  defp indexed_map(enum, transform \\ & &1) do
    enum
    |> Enum.with_index()
    |> Map.new(fn {value, key} -> {key, transform.(value)} end)
  end

  @doc """
  Makes a guess for the current word in the game.

  This function processes a player's guess for the current word, updating the game state
  accordingly. It validates that it's the player's turn and the game is in a valid state
  for guessing.

  ## Parameters
    - game_state: The GameState struct representing the current state of the game
    - player_id: The ID of the player making the guess (not the Player struct)
    - letter: A single character string representing the letter being guessed

  ## Returns
    - `{:ok, updated_game}`: If the guess is processed successfully
    - `{:error, reason}`: If the guess cannot be processed. Possible reasons:
      - `:not_a_participant`: The player attempting to guess is not seated in the game
      - `:not_player_turn`: The player attempting to guess is not the current player
      - `:game_not_playing`: The game is not in playing state
      - `:letter_already_guessed`: The letter has already been guessed for this word
      - `:game_archived`: The game is archived and cannot be modified
  """
  @spec guess(GameState.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, GameState.t()}
          | {:error,
             :not_a_participant
             | :not_player_turn
             | :game_archived
             | :game_not_playing
             | :letter_already_guessed}
  defdelegate guess(game_state, player_id, letter), to: GameLogic

  @doc """
  Makes a player give up in the game state, updating their status to :dead and setting lives to 0.

  ## Parameters
    - game_state: The GameState struct to update
    - player_id: The ID of the player that is giving up

  ## Returns
    - `{:ok, updated_game_state}` if player successfully gave up
    - `{:error, :not_a_participant}` if player is not seated in the game state
    - `{:error, :game_not_playing}` if the game is not in playing state
    - `{:error, :game_archived}` if the game is archived and cannot be modified
  """
  @spec give_up_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()} | {:error, :not_a_participant | :game_archived | :game_not_playing}
  defdelegate give_up_game(game_state, player_id), to: GameLogic

  @doc """
  Gets the current player in the game.

  ## Parameters
  - game_state: The current state of the game.

  ## Returns
  - current_player: The current player in the game.
  """
  @spec get_current_player(GameState.t()) :: Player.t() | Ecto.Association.NotLoaded.t() | nil
  defdelegate get_current_player(game_state), to: GameLogic

  @doc """
  Converts a GameState to a GameSummary.

  This function creates a safe representation of the game state that can be shared with players,
  containing only non-sensitive information. The GameSummary includes details like players,
  current player's turn, guesses made, remaining words, and game status, while hiding
  sensitive information like the actual words being guessed.

  ## Parameters
    - game_state: The GameState struct to convert

  ## Returns
    - A GameSummary struct containing shareable game information
  """
  @spec to_game_summary(GameState.t(), keyword()) :: GameSummary.t()
  def to_game_summary(%GameState{} = game_state, opts \\ []),
    do: GameSummary.from_game_state(game_state, opts)

  @doc """
  Archives a game, marking it as completed and no longer active.

  This function changes the game status to :archived, which indicates the game has ended
  and is no longer playable. This is useful when all players have given up or when
  the game has been completed.

  Once a game is archived, it cannot be modified in any way.

  ## Parameters
    - game_state: The GameState struct to archive

  ## Returns
    - {:ok, updated_game_state} if the game was successfully archived
    - {:error, :game_in_progress} if the game is still in playing status
  """
  @spec archive_game(GameState.t()) :: {:ok, GameState.t()} | {:error, :game_in_progress}
  def archive_game(%GameState{status: :playing} = _game_state) do
    {:error, :game_in_progress}
  end

  def archive_game(%GameState{} = game_state) do
    new_game_state =
      %GameState{game_state | status: :archived}
      |> increment_tick()
      |> push_event(:game_archived)

    {:ok, new_game_state}
  end

  @doc "Archives a non-playing, non-archived game when requested by its owner."
  @spec archive_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()} | {:error, :game_archived | :unauthorized | :game_in_progress}
  def archive_game(%GameState{status: :archived}, actor_id) when is_binary(actor_id),
    do: {:error, :game_archived}

  def archive_game(%GameState{} = game_state, actor_id) when is_binary(actor_id) do
    with :ok <- authorize_owner(game_state, actor_id) do
      archive_game(game_state)
    end
  end

  @doc "Restarts a non-playing, non-archived game back to lobby when requested by its owner."
  @spec restart_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()} | {:error, :game_archived | :unauthorized | :game_in_progress}
  def restart_game(%GameState{status: :archived}, actor_id) when is_binary(actor_id),
    do: {:error, :game_archived}

  def restart_game(%GameState{} = game_state, actor_id) when is_binary(actor_id) do
    with :ok <- authorize_owner(game_state, actor_id) do
      do_restart_game(game_state)
    end
  end

  defp do_restart_game(%GameState{status: :playing}), do: {:error, :game_in_progress}

  defp do_restart_game(%GameState{} = game_state) do
    # Reset player lives and status
    updated_players =
      game_state.game_players
      |> Enum.map(fn {idx, game_player} ->
        {idx, %{GamePlayer.reset_lives(game_player) | score: 0}}
      end)
      |> Map.new()

    new_game_state =
      %GameState{
        game_state
        | status: :lobby,
          game_players: updated_players,
          current_game_player_index: nil,
          current_game_word_index: nil,
          game_words: %{}
      }
      |> increment_tick()
      |> push_event(:game_restarted)

    # Return to lobby state
    {:ok, new_game_state}
  end

  @doc "Transfers ownership to a participating player in any non-archived phase when requested by the current owner."
  @spec transfer_ownership_to_player(GameState.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()}
          | {:error, :game_archived | :unauthorized | :already_owner | :player_not_found}
  def transfer_ownership_to_player(%GameState{status: :archived}, actor_id, target_player_id)
      when is_binary(actor_id) and is_binary(target_player_id),
      do: {:error, :game_archived}

  def transfer_ownership_to_player(%GameState{} = game_state, actor_id, target_player_id)
      when is_binary(actor_id) and is_binary(target_player_id) do
    with :ok <- authorize_owner(game_state, actor_id) do
      do_transfer_ownership(game_state, target_player_id)
    end
  end

  defp do_transfer_ownership(%GameState{owner: %{id: owner_id}}, target_player_id)
       when owner_id == target_player_id,
       do: {:error, :already_owner}

  defp do_transfer_ownership(%GameState{} = game_state, target_player_id) do
    case find_game_player_by_id(game_state, target_player_id) do
      nil ->
        {:error, :player_not_found}

      {_idx, %{player: new_owner}} ->
        new_game_state =
          %GameState{game_state | owner: new_owner}
          |> increment_tick()
          |> push_event(:ownership_transferred_to, %{
            from_player_id: game_state.owner.id,
            to_player_id: new_owner.id
          })

        {:ok, new_game_state}
    end
  end

  @doc "Checks whether `actor_id` is allowed to update settings on `game_state`."
  @spec authorize_settings_update(GameState.t(), Ecto.UUID.t()) ::
          :ok | {:error, :unauthorized | :game_not_in_lobby}
  def authorize_settings_update(%GameState{owner: %{id: owner_id}}, actor_id)
      when actor_id != owner_id,
      do: {:error, :unauthorized}

  def authorize_settings_update(%GameState{owner: nil}, _actor_id),
    do: {:error, :unauthorized}

  def authorize_settings_update(%GameState{status: status}, _actor_id)
      when status != :lobby,
      do: {:error, :game_not_in_lobby}

  def authorize_settings_update(%GameState{status: :lobby}, _actor_id), do: :ok

  @doc "Applies validated room settings to a lobby game state owned by `actor_id`."
  @spec update_settings(GameState.t(), Ecto.UUID.t(), RoomSettings.t()) ::
          {:ok, GameState.t()}
          | {:error,
             :unauthorized
             | :game_not_in_lobby
             | :invalid_name
             | :invalid_max_players
             | :invalid_word_options}
  def update_settings(%GameState{} = game_state, actor_id, %RoomSettings{} = settings)
      when is_binary(actor_id) do
    with :ok <- authorize_settings_update(game_state, actor_id),
         :ok <- validate_settings_invariants(game_state, settings) do
      updated_game_state =
        game_state
        |> put_name(settings.name)
        |> put_max_players(settings.max_players)
        |> put_word_options(settings.word_options)
        |> increment_tick()
        |> push_event(:settings_updated, settings_event_payload(settings))

      {:ok, updated_game_state}
    end
  end

  defp validate_settings_invariants(game_state, settings) do
    with :ok <- validate_name(settings.name),
         :ok <- validate_max_players(settings.max_players, game_state.game_players) do
      validate_word_options(settings.word_options)
    end
  end

  defp validate_name(name) when is_binary(name) do
    trimmed_len = name |> String.trim() |> String.length()

    if trimmed_len in 1..RoomSettings.max_name_length() do
      :ok
    else
      {:error, :invalid_name}
    end
  end

  defp validate_name(_name), do: {:error, :invalid_name}

  defp validate_max_players(max_players, game_players)
       when is_integer(max_players) and max_players in @min_players_allowed..@max_players_allowed do
    if max_players >= map_size(game_players), do: :ok, else: {:error, :invalid_max_players}
  end

  defp validate_max_players(_max_players, _game_players), do: {:error, :invalid_max_players}

  defp validate_word_options(%WordOptions{language: lang, category_ids: ids})
       when is_list(ids) do
    if lang in WordOptions.supported_languages(), do: :ok, else: {:error, :invalid_word_options}
  end

  defp validate_word_options(_word_options), do: {:error, :invalid_word_options}

  defp put_name(%GameState{} = game_state, name),
    do: %GameState{game_state | name: String.trim(name)}

  defp put_max_players(%GameState{} = game_state, max_players),
    do: %GameState{game_state | max_players: max_players}

  defp put_word_options(%GameState{} = game_state, %WordOptions{} = word_options),
    do: %GameState{game_state | word_options: word_options}

  defp settings_event_payload(%RoomSettings{} = settings) do
    %{
      name: String.trim(settings.name),
      max_players: settings.max_players,
      word_options: %{
        language: settings.word_options.language,
        category_ids: settings.word_options.category_ids
      }
    }
  end

  @doc false
  @spec min_players_allowed() :: 2
  def min_players_allowed, do: @min_players_allowed

  @doc false
  @spec max_players_allowed() :: 6
  def max_players_allowed, do: @max_players_allowed
end
