defmodule Forka.Games.Game do
  alias Forka.Games.GameSummary
  alias Forka.Games.Game.GameLogic
  alias Forka.Games.Player
  alias Forka.Games.Game.{GameState, GamePlayer, GameWord}

  @doc """
  Creates a new game state with the given name and maximum number of players.

  ## Parameters
    - name: The name of the game (string)
    - max_players: Maximum number of players allowed (integer)

  ## Returns
  A new GameState struct with:
  - A unique UUID as id
  - The provided name and max_players
  - Default empty values for words and players
  - Initial :lobby status
  - No current word or player selected

  ## Examples
      iex> GameState.new("Fun Game", 4)
      %Forka.Games.GameState{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "Fun Game",
        max_players: 4,
        status: :lobby,
        words: %{},
        players: %{},
        current_game_word_index: nil,
        current_game_player_index: nil
      }
  """
  def new(%Player{} = owner, name, max_players)
      when is_binary(name) and is_integer(max_players) do
    %GameState{
      id: UUID.uuid4(),
      name: name,
      owner: owner,
      max_players: max_players
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

  The player is converted to a GamePlayer and added to the game state's players map.
  """
  def add_player(%GameState{players: players, status: :lobby} = game_state, %Player{} = player) do
    new_players = add_game_player_to_map(players, player)

    if map_size(new_players) <= game_state.max_players do
      {:ok, %{game_state | players: new_players}}
    else
      {:error, :maximum_players}
    end
  end

  def add_player(_game_state, _player), do: {:error, :game_already_started}

  defp add_game_player_to_map(%{} = players, %Player{} = player) do
    (Map.values(players) ++ [GamePlayer.new(player)])
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

  Players are reindexed after removal to maintain sequential ordering.
  If the player is not found in the game, returns the unchanged game state.
  """
  def remove_player(%GameState{status: :lobby, players: players} = game_state, player_id)
      when is_binary(player_id) do
    new_players =
      players
      |> Map.values()
      |> Enum.reject(&(&1.player.id == player_id))
      |> indexed_map()

    {:ok, %{game_state | players: new_players}}
  end

  def remove_player(%GameState{}, player_id) when is_binary(player_id),
    do: {:error, :game_already_started}

  @doc """
  Sets the words for the game state.

  ## Parameters
    - game_state: The GameState struct to update
    - words: List of words to add to the game state

  ## Returns
    - - A GameState struct with words set
  """
  def set_words(%GameState{} = game_state, words) when is_list(words) do
    new_words =
      words
      |> Enum.uniq()
      |> indexed_map(&GameWord.new/1)

    %{game_state | words: new_words}
  end

  @doc """
  Shuffles the players in the game state.

  ## Parameters
    - game_state: The GameState struct containing players to shuffle

  ## Returns
    - A GameState struct with players in a randomized order

  ## Examples
      iex> game_state = %GameState{players: %{0 => player1, 1 => player2, 2 => player3}}
      iex> shuffled = Game.shuffle_players(game_state)
      iex> Map.keys(shuffled.players) == Map.keys(game_state.players)
      true
      iex> Map.values(shuffled.players) |> Enum.sort() == Map.values(game_state.players) |> Enum.sort()
      true
  """
  def shuffle_players(%GameState{players: players} = game_state) do
    shuffled_players =
      players
      |> Map.values()
      |> Enum.shuffle()
      |> indexed_map()

    %{game_state | players: shuffled_players}
  end

  @doc """
  Initializes a game by transitioning it from lobby state to playing state.

  ## Parameters
    - game_state: The GameState struct to initialize

  ## Returns
    - `{:ok, game_state}` with updated status if the game can be started
    - `{:error, :game_not_ready}` if there are not enough players or words
    - `{:error, :game_already_initialized}` if the game is not in lobby status

  ## Examples
      iex> game_state = %GameState{status: :lobby, players: %{0 => player1, 1 => player2}, words: %{0 => word1}}
      iex> {:ok, updated_game} = Game.init_game(game_state)
      iex> updated_game.status
      :playing
  """
  def init_game(%GameState{status: :lobby} = game_state) do
    if can_start?(game_state) do
      new_game_state = %{
        game_state
        | current_game_word_index: 0,
          current_game_player_index: 0,
          status: :playing
      }

      {:ok, new_game_state}
    else
      {:error, :game_not_ready}
    end
  end

  def init_game(%GameState{}), do: {:error, :game_already_initialized}

  defp can_start?(%GameState{} = game_state),
    do: map_size(game_state.players) >= 2 && map_size(game_state.words) >= 1

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
    - letter: A single character string representing the letter being guessed
    - player_id: The ID of the player making the guess (not the Player struct)

  ## Returns
    - `{:ok, updated_game}`: If the guess is processed successfully
    - `{:error, reason}`: If the guess cannot be processed. Possible reasons:
      - `:not_player_turn`: The player attempting to guess is not the current player
      - `:game_not_playing`: The game is not in playing state
      - `:letter_already_guessed`: The letter has already been guessed for this word
  """
  defdelegate guess(game_state, letter, player_id), to: GameLogic

  @doc """
  Makes a player give up in the game state, updating their status to :dead and setting lives to 0.

  ## Parameters
    - game_state: The GameState struct to update
    - player_id: The ID of the player that is giving up

  ## Returns
    - `{:ok, updated_game_state}` if player successfully gave up
    - `{:error, :player_not_found}` if player is not in the game state
    - `{:error, :game_not_playing}` if the game is not in playing state
  """
  defdelegate give_up_player(game_state, player_id), to: GameLogic

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
end
