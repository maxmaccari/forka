defmodule Forka.Words do
  @moduledoc """
  The Words context.
  """

  import Ecto.Query, warn: false
  alias Forka.Repo

  alias Forka.Words.Category
  alias Forka.Words.Word

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
        dbg(word)

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

  def list_categories(opts \\ []) do
    language = Keyword.get(opts, :language)

    case language do
      nil -> Repo.all(Category)
      lang -> Repo.all(from c in Category, where: c.language == ^lang)
    end
  end
end
