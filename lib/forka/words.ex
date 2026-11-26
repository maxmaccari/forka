defmodule Forka.Words do
  @moduledoc """
  The Words context.
  """

  import Ecto.Query, warn: false
  alias Forka.Repo

  alias Forka.Words.Category
  alias Forka.Words.Word
  alias Forka.WordText

  @doc """
  Imports words from a list of maps.

  Each map should contain "category", "name" (word text), and optionally "hint".
  Keys can be provided as strings or atoms.
  If the category exists, it adds words to it. If not, it creates the category.
  Words that already exist in a category are ignored.

  ## Examples

      iex> import_words([
      ...>   %{"category" => "Animal", "name" => "horse", "hint" => "Used as transportation", "language" => "en"}
      ...> ])
      {:ok, [%Word{}]}

      iex> import_words([
      ...>   %{category: "Animal", name: "cavalo", hint: "Usado como meio de transporte", language: "pt"}
      ...> ])
      {:ok, [%Word{}]}

  """
  @spec import_words([map()]) :: {:ok, [Word.t()]}
  def import_words(words_data) when is_list(words_data) do
    # Group words by category
    words_by_category =
      Enum.group_by(words_data, fn word_data ->
        String.downcase(word_data["category"] || word_data[:category])
      end)

    # 1. Insert the categories using insert_all. Just use on_conflict: :nothing
    # Extract unique category names and prepare for insertion
    categories_to_insert =
      words_by_category
      |> Map.keys()
      |> Enum.map(fn category_name ->
        # Get the first word data for this category to extract language
        first_word = words_by_category[category_name] |> List.first()
        language = first_word["language"] || first_word[:language] || "en"

        %{
          name: first_word["category"] || first_word[:category],
          language: language,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          id: Ecto.UUID.generate()
        }
      end)

    # Insert all categories at once, ignoring conflicts and return the inserted records
    {_, inserted_categories} =
      Repo.insert_all(Category, categories_to_insert,
        on_conflict: :nothing,
        returning: true
      )

    # 2. Find existing categories for the ones that weren't inserted
    # Get all category names from the data
    all_category_names = Map.keys(words_by_category)

    # Get names of categories that were successfully inserted
    inserted_category_names = Enum.map(inserted_categories, &String.downcase(&1.name))

    # Find category names that need to be fetched from the database
    categories_to_fetch = all_category_names -- inserted_category_names

    # Fetch existing categories from the database
    existing_categories =
      if Enum.empty?(categories_to_fetch) do
        []
      else
        Repo.all(from c in Category, where: fragment("lower(?)", c.name) in ^categories_to_fetch)
      end

    # Combine newly inserted and existing categories
    categories = inserted_categories ++ existing_categories

    words_to_insert =
      for category <- categories, word <- words_by_category[String.downcase(category.name)] do
        # Extract word data and prepare for insertion
        word_name = word["name"] || word[:name]
        word_hint = word["hint"] || word[:hint]

        %{
          text: String.downcase(word_name),
          hint: word_hint,
          category_id: category.id,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          id: Ecto.UUID.generate()
        }
      end

    {_, words} = Repo.insert_all(Word, words_to_insert, on_conflict: :nothing, returning: true)

    {:ok, Repo.preload(words, :category)}
  end

  @doc """
  Returns the list of categories.

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

      iex> list_categories(language: "en")
      [%Category{language: "en"}, ...]
  """

  @spec list_categories(keyword()) :: [Category.t()]
  def list_categories(opts \\ []) do
    language = Keyword.get(opts, :language)

    case language do
      nil -> Repo.all(from c in Category, order_by: [asc: c.name])
      lang -> Repo.all(from c in Category, where: c.language == ^lang, order_by: [asc: c.name])
    end
  end

  @doc """
  Returns the subset of `ids` that exist as categories for the given `language`.

  Returns an empty list without querying the database when given an empty list.
  """
  @spec list_category_ids_for_language(String.t(), [Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def list_category_ids_for_language(_language, []), do: []

  def list_category_ids_for_language(language, ids)
      when is_binary(language) and is_list(ids) do
    ids = Enum.uniq(ids)

    Repo.all(
      from c in Category,
        where: c.language == ^language and c.id in ^ids,
        select: c.id
    )
  end

  @doc """
  Returns categories matching the given list of IDs, ordered alphabetically by name.

  Returns an empty list without querying the database when given an empty list.
  """
  @spec list_categories_by_ids([Ecto.UUID.t()]) :: [Category.t()]
  def list_categories_by_ids([]), do: []

  def list_categories_by_ids(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    Repo.all(
      from c in Category,
        where: c.id in ^ids,
        order_by: [asc: c.name]
    )
  end

  @doc """
  Counts distinct playable words matching the optional `:language` and `:category_ids` filters.

  Words are filtered to playable text (`WordText.playable_text?/1`) and deduplicated by
  `WordText.normalize_text/1` (case and accents folded).
  """
  @spec count_distinct_playable_words(keyword()) :: non_neg_integer()
  def count_distinct_playable_words(opts \\ []) when is_list(opts) do
    opts
    |> filtered_words_query()
    |> select([w, _c], w.text)
    |> Repo.all()
    |> Stream.filter(&WordText.playable_text?/1)
    |> Stream.map(&WordText.normalize_text/1)
    |> MapSet.new()
    |> MapSet.size()
  end

  @doc """
  Samples up to `count` distinct playable dictionary entries matching the optional
  `:language` and `:category_ids` filters.

  Returns fewer entries than `count` when the filtered pool has fewer distinct playable words.
  """
  @spec sample_distinct_playable_words(non_neg_integer(), keyword()) :: [
          %{
            text: String.t(),
            category: String.t(),
            hint: String.t() | nil,
            language: String.t()
          }
        ]
  def sample_distinct_playable_words(count, opts \\ [])

  def sample_distinct_playable_words(0, opts) when is_list(opts), do: []

  def sample_distinct_playable_words(count, opts)
      when is_integer(count) and count > 0 and is_list(opts) do
    opts
    |> filtered_words_query()
    |> select([w, c], %{
      text: w.text,
      category: c.name,
      hint: w.hint,
      language: c.language
    })
    |> Repo.all()
    |> Enum.filter(&WordText.playable_text?(&1.text))
    |> Enum.group_by(&WordText.normalize_text(&1.text))
    |> Map.values()
    |> Enum.take_random(count)
    |> Enum.map(&Enum.random/1)
  end

  defp filtered_words_query(opts) do
    language = Keyword.get(opts, :language)
    category_ids = Keyword.get(opts, :category_ids, [])

    query =
      from w in Word,
        join: c in assoc(w, :category)

    query =
      if is_binary(language) and String.trim(language) != "" do
        normalized_lang = language |> String.trim() |> String.downcase()
        from [w, c] in query, where: c.language == ^normalized_lang
      else
        query
      end

    if is_list(category_ids) and category_ids != [] do
      from [w, _c] in query, where: w.category_id in ^category_ids
    else
      query
    end
  end
end
