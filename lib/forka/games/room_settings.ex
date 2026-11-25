defmodule Forka.Games.RoomSettings do
  @moduledoc """
  Embedded schema and validation rules for room creation and pre-match owner settings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Games.Core.GameState
  alias Forka.Games.GameSummary
  alias Forka.Games.Schemas.WordOptions

  @max_name_length 60

  @primary_key false
  embedded_schema do
    field :name, :string, default: ""
    field :max_players, :integer, default: 4
    embeds_one :word_options, WordOptions, on_replace: :update
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          max_players: integer() | nil,
          word_options: WordOptions.t() | nil
        }

  @doc "Builds a new `%RoomSettings{}` with creation defaults."
  @spec new(map()) :: t()
  def new(attrs \\ %{}) do
    %__MODULE__{word_options: %WordOptions{language: "pt", category_ids: []}}
    |> struct(attrs)
  end

  @doc "Returns the maximum allowed length for a room name."
  @spec max_name_length() :: pos_integer()
  def max_name_length, do: @max_name_length

  @doc "Builds `%RoomSettings{}` from a `%GameState{}`."
  @spec from_game_state(GameState.t()) :: t()
  def from_game_state(%GameState{} = state) do
    %__MODULE__{
      name: state.name || "",
      max_players: state.max_players || 4,
      word_options: WordOptions.normalize(state.word_options)
    }
  end

  @doc "Builds `%RoomSettings{}` from a `%GameSummary{}`."
  @spec from_game_summary(GameSummary.t()) :: t()
  def from_game_summary(%GameSummary{} = summary) do
    %__MODULE__{
      name: summary.name || "",
      max_players: summary.max_players || 4,
      word_options: WordOptions.normalize(summary.word_options)
    }
  end

  @doc """
  Validates room settings changes, always running `WordOptions.settings_changeset/3`
  even when `attrs` omits `:word_options`.
  """
  @spec changeset(t(), map(), keyword()) :: Ecto.Changeset.t(t())
  def changeset(%__MODULE__{} = settings, attrs, opts \\ []) when is_map(attrs) do
    wo_opts = Keyword.take(opts, [:allowed_category_ids])
    normalized_settings = %{settings | word_options: WordOptions.normalize(settings.word_options)}
    attrs = ensure_word_options_in_attrs(attrs, normalized_settings.word_options)

    normalized_settings
    |> cast(attrs, [:name, :max_players])
    |> update_change(:name, fn
      nil -> nil
      name when is_binary(name) -> String.trim(name)
    end)
    |> validate_required([:name, :max_players])
    |> validate_length(:name, max: @max_name_length)
    |> validate_number(:max_players,
      greater_than_or_equal_to: 2,
      less_than_or_equal_to: 6,
      message: "deve ser entre 2 e 6 jogadores"
    )
    |> validate_occupancy(Keyword.get(opts, :min_players))
    |> cast_embed(:word_options,
      required: true,
      with: fn wo, wo_attrs ->
        WordOptions.settings_changeset(wo, wo_attrs, wo_opts)
      end
    )
  end

  @doc """
  Computes the normalized effective `{language, valid_uuids}` from merging `attrs`
  onto `settings` so `Games` and `GameServer` can query `Words` with exact inputs.
  """
  @spec extract_lookup_inputs(t(), map()) :: {String.t() | nil, [Ecto.UUID.t()]}
  def extract_lookup_inputs(%__MODULE__{} = settings, attrs) when is_map(attrs) do
    current_wo = WordOptions.normalize(settings.word_options)
    wo_attrs = Map.get(attrs, "word_options") || Map.get(attrs, :word_options) || %{}

    raw_lang = fetch_attr(wo_attrs, "language", :language, current_wo.language)
    raw_ids = fetch_attr(wo_attrs, "category_ids", :category_ids, current_wo.category_ids)

    {WordOptions.normalize_language(raw_lang), cast_valid_uuids(raw_ids)}
  end

  defp fetch_attr(map, str_key, atom_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, str_key) -> Map.get(map, str_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> default
    end
  end

  defp fetch_attr(_other, _str_key, _atom_key, default), do: default

  defp cast_valid_uuids(ids) when is_list(ids) do
    if Enum.drop(ids, WordOptions.max_categories()) != [] do
      []
    else
      ids
      |> Enum.flat_map(&cast_single_uuid/1)
      |> Enum.uniq()
    end
  end

  defp cast_valid_uuids(_other), do: []

  defp cast_single_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, canonical} -> [canonical]
      :error -> []
    end
  end

  defp ensure_word_options_in_attrs(attrs, %WordOptions{} = current_wo) do
    if Map.has_key?(attrs, "word_options") or Map.has_key?(attrs, :word_options) do
      attrs
    else
      has_string_keys = Enum.any?(attrs, fn {k, _v} -> is_binary(k) end)

      if has_string_keys do
        Map.put(attrs, "word_options", %{
          "language" => current_wo.language,
          "category_ids" => current_wo.category_ids
        })
      else
        Map.put(attrs, :word_options, %{
          language: current_wo.language,
          category_ids: current_wo.category_ids
        })
      end
    end
  end

  defp validate_occupancy(changeset, min_players) when is_integer(min_players) do
    if Keyword.has_key?(changeset.errors, :max_players) do
      changeset
    else
      case get_field(changeset, :max_players) do
        val when is_integer(val) and val < min_players ->
          add_error(
            changeset,
            :max_players,
            "não pode ser menor que o número atual de jogadores (%{count})",
            count: min_players
          )

        _ ->
          changeset
      end
    end
  end

  defp validate_occupancy(changeset, _min_players), do: changeset
end
