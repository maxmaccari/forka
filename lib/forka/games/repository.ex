defmodule Forka.Games.Repository do
  alias Forka.Games.Word
  alias Forka.Games.Player
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
end
