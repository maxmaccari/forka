defmodule Forka.Games.Game do
  alias Forka.Games.Schemas.Player
  alias Forka.Games.GameSummary
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Guess
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Game.{GameState, GameLogic}

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
  def join_game(
        %GameState{game_players: game_players, status: :lobby} = game_state,
        %Player{} = player
      ) do
    new_game_players = add_game_player_to_map(game_players, player)

    if map_size(new_game_players) <= game_state.max_players do
      {:ok, %{game_state | game_players: new_game_players, last_event: {:player_joined, player}}}
    else
      {:error, :maximum_players}
    end
  end

  def join_game(%GameState{status: :archived}, _player), do: {:error, :game_archived}

  def join_game(_game_state, _player), do: {:error, :game_already_started}

  defp add_game_player_to_map(%{} = game_players, %Player{} = player) do
    (Map.values(game_players) ++ [GamePlayer.new(player)])
    |> Enum.uniq_by(& &1.player.id)
    |> indexed_map()
  end

  @doc """
  Removes a player from the game state while in lobby state.

  ## Parameters
    - game_state: The GameState struct
    - player_id: The ID of the player to be removed

  ## Returns
    - `{:ok, game_state}` if player was successfully removed
    - `{:error, :game_already_started}` if game state is not in lobby state
    - `{:error, :game_archived}` if game state is archived

  Players are reindexed after removal to maintain sequential ordering.
  If the player is not found in the game, returns the unchanged game state.
  """
  def leave_game(%GameState{status: :lobby, game_players: game_players} = game_state, player_id)
      when is_binary(player_id) do
    left_player =
      Enum.find_value(game_players, fn {_, game_player} ->
        if game_player.player.id == player_id, do: game_player.player
      end)

    if left_player do
      new_game_players =
        game_players
        |> Map.values()
        |> Enum.reject(&(&1.player.id == player_id))
        |> indexed_map()

      {:ok,
       %{game_state | game_players: new_game_players, last_event: {:player_left, left_player}}}
    else
      {:ok, game_state}
    end
  end

  def leave_game(%GameState{status: :archived}, player_id) when is_binary(player_id),
    do: {:error, :game_archived}

  def leave_game(%GameState{}, player_id) when is_binary(player_id),
    do: {:error, :game_already_started}

  @doc """
  Sets the words for the game state.

  ## Parameters
    - game_state: The GameState struct to update
    - words: List of words to add to the game state

  ## Returns
    - A GameState struct with game_words set if the game is in lobby state
    - The unchanged game_state if the game is not in lobby state
  """
  def set_words(%GameState{status: :lobby} = game_state, words) when is_list(words) do
    new_game_words =
      words
      |> Enum.uniq()
      |> indexed_map(&GameWord.new/1)

    %{game_state | game_words: new_game_words, last_event: {:words_set, length(words)}}
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
  def shuffle_players(%GameState{game_players: game_players, status: :lobby} = game_state) do
    shuffled_game_players =
      game_players
      |> Map.values()
      |> Enum.shuffle()
      |> indexed_map()

    %{game_state | game_players: shuffled_game_players, last_event: :players_shuffled}
  end

  def shuffle_players(%GameState{} = game_state),
    do: game_state

  @doc """
  Initializes a game by transitioning it from lobby state to playing state.

  ## Parameters
    - game_state: The GameState struct to initialize

  ## Returns
    - `{:ok, game_state}` with updated status if the game can be started
    - `{:error, :game_not_ready}` if there are not enough players or words
    - `{:error, :game_already_initialized}` if the game is not in lobby status
    - `{:error, :game_archived}` if the game is archived

  ## Examples
      iex> game_state = %GameState{status: :lobby, game_players: %{0 => player1, 1 => player2}, game_words: %{0 => word1}}
      iex> {:ok, updated_game} = Game.start_game(game_state)
      iex> updated_game.status
      :playing
  """
  def start_game(%GameState{status: :lobby} = game_state) do
    if can_start?(game_state) do
      new_game_state = %{
        game_state
        | current_game_word_index: 0,
          current_game_player_index: 0,
          status: :playing,
          last_event: :game_started
      }

      {:ok, new_game_state}
    else
      {:error, :game_not_ready}
    end
  end

  def start_game(%GameState{status: :archived}), do: {:error, :game_archived}

  def start_game(%GameState{}), do: {:error, :game_already_initialized}

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
      - `:not_player_turn`: The player attempting to guess is not the current player
      - `:game_not_playing`: The game is not in playing state
      - `:letter_already_guessed`: The letter has already been guessed for this word
      - `:game_archived`: The game is archived and cannot be modified
  """
  defdelegate guess(game_state, player_id, letter), to: GameLogic

  @doc """
  Makes a player give up in the game state, updating their status to :dead and setting lives to 0.

  ## Parameters
    - game_state: The GameState struct to update
    - player_id: The ID of the player that is giving up

  ## Returns
    - `{:ok, updated_game_state}` if player successfully gave up
    - `{:error, :player_not_found}` if player is not in the game state
    - `{:error, :game_not_playing}` if the game is not in playing state
    - `{:error, :game_archived}` if the game is archived and cannot be modified
  """
  defdelegate give_up_game(game_state, player_id), to: GameLogic

  @doc """
  Gets the current player in the game.

  ## Parameters
  - game_state: The current state of the game.

  ## Returns
  - current_player: The current player in the game.
  """
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
  def to_game_summary(%GameState{} = game_state), do: GameSummary.from_game_state(game_state)

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
  def archive_game(%GameState{status: :playing} = _game_state) do
    {:error, :game_in_progress}
  end

  def archive_game(%GameState{} = game_state) do
    {:ok, %GameState{game_state | status: :archived, last_event: :game_archived}}
  end

  @doc """
  Restarts a game, returning it to the lobby state.

  This function resets the game to its lobby state, allowing players to start a new round.
  It maintains the same players and game settings, but clears all game progress including
  guesses, word selections, and player statuses.

  ## Parameters
    - game_state: The current GameState struct to restart

  ## Returns
    - {:ok, updated_game_state} if the game was successfully restarted
    - {:error, :game_in_progress} if the game is still in playing status
    - {:error, :game_archived} if the game is archived
  """
  def restart_game(%GameState{status: :playing} = _game_state) do
    {:error, :game_in_progress}
  end

  def restart_game(%GameState{status: :archived} = _game_state) do
    {:error, :game_archived}
  end

  def restart_game(%GameState{} = game_state) do
    # Reset player lives and status
    updated_players =
      game_state.game_players
      |> Enum.map(fn {idx, game_player} ->
        {idx, GamePlayer.reset_lives(game_player)}
      end)
      |> Map.new()

    # Return to lobby state
    {:ok,
     %GameState{
       game_state
       | status: :lobby,
         game_players: updated_players,
         current_game_player_index: nil,
         current_game_word_index: nil,
         game_words: %{},
         last_event: :game_restarted
     }}
  end

  @doc """
  Transfers ownership of the game to another player.

  This function changes the owner of the game to a different player who is already
  participating in the game.

  ## Parameters
    - game_state: The current GameState struct
    - player_id: The ID of the player who will become the new owner

  ## Returns
    - {:ok, updated_game_state} if ownership was successfully transferred
    - {:error, :player_not_found} if the specified player is not in the game
    - {:error, :already_owner} if the specified player is already the owner
    - {:error, :game_archived} if the game is in archived status
  """
  def transfer_ownership_to_player(%GameState{status: :archived} = _game_state, player_id)
      when is_binary(player_id) do
    {:error, :game_archived}
  end

  def transfer_ownership_to_player(%GameState{} = game_state, player_id)
      when is_binary(player_id) do
    # Check if player exists in the game
    player_exists =
      game_state.game_players
      |> Map.values()
      |> Enum.any?(fn game_player -> game_player.player.id == player_id end)

    cond do
      # If player is already the owner
      game_state.owner.id == player_id ->
        {:error, :already_owner}

      # If player doesn't exist in the game
      not player_exists ->
        {:error, :player_not_found}

      # Transfer ownership
      true ->
        # Find the player struct from game_players map
        new_owner =
          game_state.game_players
          |> Map.values()
          |> Enum.find(fn game_player -> game_player.player.id == player_id end)
          |> Map.get(:player)

        {:ok,
         %GameState{
           game_state
           | owner: new_owner,
             last_event: {:ownership_transferred_to, new_owner}
         }}
    end
  end

  @doc """
  Sets the word options for the game.

  ## Parameters
    - game_state: The current GameState struct
    - options: Keyword list of options (e.g., [language: "en", category_ids: ["uuid1"]])

  ## Returns
    - {:ok, updated_game_state} if the options were successfully set
    - {:error, :game_not_in_lobby} if the game is not in lobby status
  """
  def set_word_options(%GameState{status: :lobby} = game_state, options) when is_list(options) do
    {:ok,
     %GameState{game_state | word_options: options, last_event: {:words_options_set, options}}}
  end

  def set_word_options(%GameState{} = _game_state, _options),
    do: {:error, :game_not_in_lobby}

  @doc """
  Converts the last_event tuple into a human-readable description.

  ## Parameters
    - game_state: The current GameState struct

  ## Returns
    - A string with a friendly description of the last event
    - nil if there's no last event
  """
  def last_event_description(%GameState{last_event: nil}), do: nil

  def last_event_description(%GameState{last_event: {:player_joined, player}}) do
    "#{player.username} joined the game"
  end

  def last_event_description(%GameState{last_event: {:player_left, player}}) do
    "#{player.username} left the game"
  end

  def last_event_description(%GameState{last_event: {:game_started, _owner}}) do
    "Game started"
  end

  def last_event_description(%GameState{
        last_event: {:player_guessed, %Guess{letter: letter, correct?: true}}
      }) do
    "Player correctly guessed the letter '#{letter}'"
  end

  def last_event_description(%GameState{
        last_event: {:player_guessed, %Guess{letter: letter, correct?: false}}
      }) do
    "Player incorrectly guessed the letter '#{letter}'"
  end

  def last_event_description(%GameState{last_event: {:player_gave_up, player}}) do
    "#{player.username} gave up"
  end

  def last_event_description(%GameState{last_event: {:ownership_transferred_to, player}}) do
    "Game ownership transferred to #{player.username}"
  end

  def last_event_description(%GameState{last_event: :game_archived}) do
    "Game was archived"
  end

  def last_event_description(%GameState{last_event: :game_restarted}) do
    "Game was restarted"
  end

  def last_event_description(%GameState{last_event: {:word_options_set, options}}) do
    language = Keyword.get(options, :language)
    categories = Keyword.get(options, :category_ids, [])

    language_text =
      case language do
        nil -> ""
        language -> " to language '#{language}'"
      end

    categories_text =
      case categories do
        [] -> ""
        ids -> " with #{length(ids)} categories"
      end

    "Word options set#{language_text}#{categories_text}"
  end

  # Fallback for any unhandled event types
  def last_event_description(%GameState{last_event: event}) do
    "Unknown event: #{inspect(event)}"
  end
end
