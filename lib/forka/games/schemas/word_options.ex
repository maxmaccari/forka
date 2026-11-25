defmodule Forka.Games.Schemas.WordOptions do
  @moduledoc """
  Embedded schema for word options used in game filtering.

  This schema represents options for filtering words in a game, including:
  - language: The language of the words to be used in the game
  - category_ids: Optional list of category IDs to filter words by
  """

  use Ecto.Schema
  import Ecto.Changeset

  @supported_languages ["pt", "en"]
  @max_categories 50

  @primary_key false
  embedded_schema do
    field :language, :string, default: "en"
    field :category_ids, {:array, :binary_id}, default: []
  end

  @type t :: %__MODULE__{
          language: String.t() | nil,
          category_ids: [Ecto.UUID.t()] | nil
        }

  @doc "Returns the list of supported word languages."
  @spec supported_languages() :: [String.t()]
  def supported_languages, do: @supported_languages

  @doc "Returns the maximum number of category IDs allowed in room settings."
  @spec max_categories() :: pos_integer()
  def max_categories, do: @max_categories

  @doc "Normalizes a `%WordOptions{}`, keyword list, map, or `nil` into `%WordOptions{}`."
  @spec normalize(t() | keyword() | map() | nil) :: t()
  def normalize(nil), do: %__MODULE__{language: "en", category_ids: []}

  def normalize(%__MODULE__{language: language, category_ids: category_ids}) do
    %__MODULE__{
      language: language || "en",
      category_ids: category_ids || []
    }
  end

  def normalize(opts) when is_list(opts) do
    %__MODULE__{
      language: Keyword.get(opts, :language) || "en",
      category_ids: Keyword.get(opts, :category_ids) || []
    }
  end

  def normalize(opts) when is_map(opts) do
    %__MODULE__{
      language: Map.get(opts, :language) || Map.get(opts, "language") || "en",
      category_ids: Map.get(opts, :category_ids) || Map.get(opts, "category_ids") || []
    }
  end

  @doc "Trims and downcases a language binary, returning `nil` for `nil` or non-binaries."
  @spec normalize_language(any()) :: String.t() | nil
  def normalize_language(nil), do: nil

  def normalize_language(lang) when is_binary(lang),
    do: lang |> String.trim() |> String.downcase()

  def normalize_language(_other), do: nil

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(word_options, attrs) do
    word_options
    |> cast(attrs, [:language, :category_ids])
    |> validate_required([:language])
  end

  @doc """
  Strict changeset used for room creation and owner settings updates.
  """
  @spec settings_changeset(t(), map(), keyword()) :: Ecto.Changeset.t(t())
  def settings_changeset(word_options, attrs, opts \\ []) do
    allowed_category_ids = Keyword.get(opts, :allowed_category_ids)
    {cast_attrs, oversized_categories?} = guard_category_list_size(attrs)

    word_options
    |> normalize()
    |> cast(cast_attrs, [:language, :category_ids])
    |> maybe_add_max_categories_error(oversized_categories?)
    |> update_change(:language, &normalize_language/1)
    |> update_change(:category_ids, &normalize_category_ids/1)
    |> validate_required([:language])
    |> validate_effective_language()
    |> validate_category_ids(allowed_category_ids)
  end

  defp guard_category_list_size(attrs) when is_map(attrs) do
    raw_ids =
      cond do
        Map.has_key?(attrs, "category_ids") -> Map.get(attrs, "category_ids")
        Map.has_key?(attrs, :category_ids) -> Map.get(attrs, :category_ids)
        true -> nil
      end

    if is_list(raw_ids) and list_exceeds?(raw_ids, @max_categories) do
      {Map.drop(attrs, ["category_ids", :category_ids]), true}
    else
      {attrs, false}
    end
  end

  defp guard_category_list_size(attrs), do: {attrs, false}

  defp list_exceeds?(list, limit) when is_list(list) do
    Enum.drop(list, limit) != []
  end

  defp maybe_add_max_categories_error(changeset, true) do
    add_error(
      changeset,
      :category_ids,
      "deve ter no máximo %{count} categorias",
      count: @max_categories,
      validation: :length,
      kind: :max
    )
  end

  defp maybe_add_max_categories_error(changeset, false), do: changeset

  defp validate_effective_language(changeset) do
    if Keyword.has_key?(changeset.errors, :language) do
      changeset
    else
      check_effective_language(changeset, get_field(changeset, :language))
    end
  end

  defp check_effective_language(changeset, language)
       when is_binary(language) and language != "" do
    normalized = normalize_language(language)

    cond do
      normalized in @supported_languages and normalized != language ->
        put_change(changeset, :language, normalized)

      normalized in @supported_languages ->
        changeset

      true ->
        add_error(
          changeset,
          :language,
          "is invalid",
          validation: :inclusion,
          enum: @supported_languages
        )
    end
  end

  defp check_effective_language(changeset, _language), do: changeset

  defp normalize_category_ids(nil), do: []

  defp normalize_category_ids(ids) when is_list(ids) do
    ids
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&canonicalize_uuid_or_keep/1)
    |> Enum.uniq()
  end

  defp canonicalize_uuid_or_keep(id) do
    case Ecto.UUID.cast(id) do
      {:ok, canonical} -> canonical
      :error -> id
    end
  end

  defp validate_category_ids(changeset, allowed_ids) do
    if Keyword.has_key?(changeset.errors, :category_ids) do
      changeset
    else
      do_validate_category_ids(changeset, allowed_ids)
    end
  end

  defp do_validate_category_ids(changeset, allowed_ids) do
    ids = get_field(changeset, :category_ids) || []

    cond do
      list_exceeds?(ids, @max_categories) ->
        maybe_add_max_categories_error(changeset, true)

      not Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) ->
        add_error(
          changeset,
          :category_ids,
          "contém categorias indisponíveis para o idioma selecionado"
        )

      ids != [] and is_list(allowed_ids) ->
        check_allowed_category_ids(changeset, ids, allowed_ids)

      true ->
        changeset
    end
  end

  defp check_allowed_category_ids(changeset, ids, allowed_ids) do
    allowed_canonical = canonicalize_allowed_ids(allowed_ids)

    if Enum.all?(ids, &MapSet.member?(allowed_canonical, &1)) do
      changeset
    else
      add_error(
        changeset,
        :category_ids,
        "contém categorias indisponíveis para o idioma selecionado"
      )
    end
  end

  defp canonicalize_allowed_ids(allowed_ids) do
    allowed_ids
    |> Enum.flat_map(fn id ->
      case Ecto.UUID.cast(id) do
        {:ok, canonical} -> [canonical]
        :error -> []
      end
    end)
    |> MapSet.new()
  end

  @doc false
  @spec new(map()) :: t()
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end
end
