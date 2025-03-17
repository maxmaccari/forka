defmodule Forka.Games.Repository do
  @moduledoc false

  alias Forka.Games.Game.GameState
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.Player
  alias Forka.Repo

  @doc """
  Returns a list of random words from the database.

  ## Parameters

    * `count` - The number of words to return (default: 5)
    * `opts` - Additional options:
      * `:language` - Filter words by category language (e.g., "en", "pt")
      * `:category_ids` - Filter words by specific category IDs (list)

  ## Examples

      iex> get_random_words(3)
      [%{text: "dog", hint: "Barks", category: "Animals", language: "en"}, ...]

      iex> get_random_words(5, language: "en")
      [%{text: "blue", hint: "Color of the sky", category: "Colors", language: "en"}, ...]

      iex> get_random_words(2, category_ids: ["uuid1", "uuid2"])
      [%{text: "cat", hint: "Meows", category: "Animals", language: "en"}, ...]

  ## Returns

  A list of Word structs with text, hint, category, and language fields.
  Returns fewer words than requested if not enough words match the filters.
  """
  def get_random_words(count \\ 5, opts \\ []) do
    import Ecto.Query

    language = Keyword.get(opts, :language)
    category_ids = Keyword.get(opts, :category_ids)

    query =
      from w in Forka.Words.Word,
        join: c in assoc(w, :category),
        select: %{
          text: w.text,
          category: c.name,
          hint: w.hint,
          language: c.language
        }

    query =
      if language do
        from [w, c] in query, where: c.language == ^String.downcase(language)
      else
        query
      end

    query =
      if category_ids && !Enum.empty?(category_ids) do
        from w in query, where: w.category_id in ^category_ids
      else
        query
      end

    # Order by random and limit to requested count
    query =
      from q in query,
        order_by: fragment("RANDOM()"),
        limit: ^count

    query
    |> Repo.all()
    |> Enum.map(&Word.from_map/1)
  end

  @doc """
  Gets a player by ID.

  ## Parameters

    * `id` - The UUID of the player to retrieve

  ## Examples

      iex> get_player("123e4567-e89b-12d3-a456-426614174000")
      %Player{}

      iex> get_player("nonexistent-uuid")
      nil

  ## Returns

  The Player struct if found, nil otherwise.
  """
  def get_player(id) do
    Repo.get(Player, id)
  end

  @doc """
  Inserts a new game into the database with the given owner ID and parameters.

  ## Parameters

    * `owner_id` - The UUID of the player who will own the game
    * `params` - A map of parameters for the game (name, max_players, etc.)

  ## Examples

      iex> insert_game("123e4567-e89b-12d3-a456-426614174000", %{name: "My Game", max_players: 4})
      {:ok, %Game{}}

      iex> insert_game("123e4567-e89b-12d3-a456-426614174000", %{name: ""})
      {:error, changeset}

  ## Returns

  A tuple containing either:
  - `{:ok, game}` with the inserted game if successful
  - `{:error, changeset}` with the changeset containing errors if unsuccessful
  """
  def insert_game(owner_id, params) when is_binary(owner_id) and is_map(params) do
    %Game{owner_id: owner_id}
    |> Game.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, game} -> {:ok, game}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets a game state from the database by its ID.

  This function retrieves a game by ID, preloads its associations,
  and converts it to a GameState struct.

  ## Parameters

    * `id` - The UUID of the game to retrieve

  ## Examples

      iex> get_game_state("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %GameState{}}

      iex> get_game_state("nonexistent-uuid")
      {:error, :not_found}

  ## Returns

  A tuple containing either:
  - `{:ok, game_state}` with the game state if found
  - `{:error, :not_found}` if the game does not exist
  """
  def get_game_state(id) when is_binary(id) do
    Repo.get(Game, id)
    |> Repo.preload([:game_words, :game_players, :owner])
    |> case do
      nil -> {:error, :not_found}
      game -> {:ok, Game.to_game_state(game)}
    end
  end

  def save_game_state(%GameState{id: id} = game_state) do
    Repo.get(Game, id)
    |> Repo.preload([:game_words, :game_players])
    |> Game.changeset(game_state_to_params(game_state))
    |> Repo.update()
    |> case do
      {:ok, game} -> {:ok, Game.to_game_state(game)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp game_state_to_params(%GameState{} = game_state) do
    # First convert GameState to Game schema
    game = Game.from_game_state(game_state)

    # Then convert the Game schema to a map, removing the __struct__ and other Ecto metadata
    game_params = Map.from_struct(game)

    # Clean up any virtual fields or associations that might cause issues
    game_params
    |> Map.drop([:__meta__, :owner, :inserted_at, :updated_at])
    |> Map.update(:game_words, [], fn game_words ->
      Enum.map(game_words, fn game_word ->
        game_word
        |> Map.from_struct()
        |> Map.update(:word, nil, &(&1 |> Map.from_struct() |> Map.drop([:__meta__])))
        |> Map.drop([:__meta__, :game, :game_id, :inserted_at, :updated_at])
        |> Map.update(:guesses, [], fn guesses ->
          Enum.map(guesses, &Map.from_struct/1)
        end)
      end)
    end)
    |> Map.update(:game_players, [], fn game_players ->
      Enum.map(game_players, fn game_player ->
        game_player
        |> Map.from_struct()
        |> Map.drop([:__meta__, :player, :game, :game_id, :inserted_at, :updated_at])
      end)
    end)
    |> Map.update(:word_options, nil, fn word_options ->
      if word_options do
        word_options
        |> Map.from_struct()
        |> Map.drop([:__meta__])
      else
        %{}
      end
    end)
  end
end
