defmodule Forka.Games.Repository do
  @moduledoc false

  alias Forka.Games.Schemas.WordOptions
  alias Forka.Games.Game.GameState
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.Player
  alias Forka.Repo

  import Ecto.Query

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
  def get_random_words(count \\ 5, word_options \\ %WordOptions{}) do
    %WordOptions{language: language, category_ids: category_ids} = word_options

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
    |> Game.insert_changeset(params)
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
  @game_preloads [{:game_players, :player}, :game_words, :owner]
  def get_game_state(id) when is_binary(id) do
    Repo.get(Game, id)
    |> Repo.preload(@game_preloads)
    |> case do
      nil -> {:error, :not_found}
      game -> {:ok, Game.to_game_state(game)}
    end
  end

  def save_game_state(%GameState{id: id} = game_state) do
    Repo.get(Game, id)
    |> Repo.preload(@game_preloads)
    |> Game.update_changeset(game_state_to_map(game_state))
    |> Repo.update()
    |> case do
      {:ok, game} ->
        new_game_state =
          game
          |> Repo.preload(@game_preloads)
          |> Game.to_game_state()

        {:ok, new_game_state}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Similar to `save_game_state/1`, but raises an exception if the game state cannot be saved.

  ## Parameters

    * `game_state` - The GameState struct to save

  ## Examples

      iex> save_game_state!(%GameState{})
      %GameState{}

      iex> save_game_state!(%GameState{id: "invalid"})
      ** (Ecto.InvalidChangesetError)

  ## Returns

  The updated GameState if successful, otherwise raises an exception.
  """
  def save_game_state!(%GameState{} = game_state) do
    case save_game_state(game_state) do
      {:ok, new_game_state} -> new_game_state
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp game_state_to_map(%GameState{} = game_state) do
    game_state
    |> Game.from_game_state()
    |> Game.to_map()
  end
end
