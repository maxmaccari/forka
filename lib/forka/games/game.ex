defmodule Forka.Games.Game do
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
  def new(name, max_players) when is_binary(name) and is_integer(max_players) do
    %GameState{
      id: UUID.uuid4(),
      name: name,
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
  Players will be shuffled when the game starts.
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
    [GamePlayer.new(player) | Map.values(players)]
    |> Enum.uniq_by(& &1.player.id)
    |> indexed_map()
  end

  @doc """
  Removes a player from the game state while in lobby state.

  Returns:
  - `{:ok, game_state}` if player was successfully removed
  - `{:error, :game_already_started}` if game state is not in lobby state
  - `{:error, :player_not_found}` if player is not in the game state
  """
  def remove_player(%GameState{status: :lobby, players: players} = game_state, %Player{
        id: player_id
      }) do
    case Enum.find(players, fn {_idx, game_player} -> game_player.player.id == player_id end) do
      {idx, _game_player} ->
        {:ok, %{game_state | players: Map.delete(players, idx)}}

      nil ->
        {:error, :player_not_found}
    end
  end

  def remove_player(_game_state, _player), do: {:error, :game_already_started}

  @doc """
  Connects a player to the game state, updating their status to :connected.

  ## Parameters
    - game_state: The GameState struct to update
    - player: The Player struct to connect

  ## Returns
    - `{:ok, game_state}` if player was successfully connected
    - `{:error, :player_not_found}` if player is not in the game state
  """
  def connect_player(%GameState{} = game_state, %Player{id: player_id}),
    do: update_player_status(game_state, player_id, &GamePlayer.connect/1)

  @doc """
  Disconnects a player from the game state, updating their status to :disconnected.

  ## Parameters
    - game_state: The GameState struct to update
    - player: The Player struct to disconnect

  ## Returns
    - `{:ok, game_state}` if player was successfully disconnected
    - `{:error, :player_not_found}` if player is not in the game state
  """
  def disconnect_player(%GameState{} = game_state, %Player{id: player_id}),
    do: update_player_status(game_state, player_id, &GamePlayer.disconnect/1)

  defp update_player_status(game_state, player_id, status_fn) do
    case find_player_by_id(game_state.players, player_id) do
      {idx, game_player} ->
        updated_player = status_fn.(game_player)
        {:ok, %{game_state | players: Map.put(game_state.players, idx, updated_player)}}

      nil ->
        {:error, :player_not_found}
    end
  end

  defp find_player_by_id(players, player_id) do
    Enum.find(players, fn {_idx, game_player} -> game_player.player.id == player_id end)
  end

  @doc """
  Makes a player give up in the game state, updating their status to :died and setting lives to 0.

  ## Parameters
    - game_state: The GameState struct to update
    - player: The Player struct that is giving up

  ## Returns
    - `{:ok, game_state}` if player successfully gave up
    - `{:error, :player_not_found}` if player is not in the game state
  """
  def give_up_player(%GameState{} = game_state, %Player{id: player_id}) do
    case find_player_by_id(game_state.players, player_id) do
      {idx, game_player} ->
        updated_player = GamePlayer.give_up(game_player)
        {:ok, %{game_state | players: Map.put(game_state.players, idx, updated_player)}}

      nil ->
        {:error, :player_not_found}
    end
  end

  @doc """
  Sets the words for the game state.

  ## Parameters
    - game_state: The GameState struct to update
    - words: List of words to add to the game state

  ## Returns
    - `{:ok, game_state}` with updated words
  """
  def set_game_words(%GameState{} = game_state, words) when is_list(words) do
    new_words =
      words
      |> Enum.uniq_by(& &1.word)
      |> indexed_map(&GameWord.new/1)

    {:ok, %{game_state | words: new_words}}
  end

  def init_game(%GameState{status: :lobby} = game_state) do
    if can_start?(game_state) do
      shuffled_players =
        game_state.players
        |> Map.values()
        |> Enum.shuffle()
        |> indexed_map()

      shuffled_words =
        game_state.words
        |> Map.values()
        |> Enum.shuffle()
        |> indexed_map()

      new_game_state = %{
        game_state
        | players: shuffled_players,
          words: shuffled_words,
          current_game_word_index: 0,
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
end
