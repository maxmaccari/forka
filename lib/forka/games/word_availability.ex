defmodule Forka.Games.WordAvailability do
  @moduledoc """
  Evaluates whether a room's word pool and roster satisfy Forka's pre-kickoff rules:
  between 2 and 6 players and at least two distinct, playable words per player.
  """

  @min_players 2
  @max_players 6
  @words_per_player 2

  @type status :: :ready | :waiting_for_players | :insufficient_words | :too_many_players
  @type broaden_action :: :add_categories | :all_categories | :change_language | :fewer_players

  @type t :: %__MODULE__{
          available_words: non_neg_integer(),
          required_words: pos_integer(),
          missing_words: non_neg_integer(),
          player_count: non_neg_integer(),
          max_players: pos_integer(),
          max_supported_players: non_neg_integer(),
          enough_players?: boolean(),
          enough_words?: boolean(),
          ready?: boolean(),
          status: status(),
          language: String.t(),
          has_category_filter?: boolean(),
          broaden_actions: [broaden_action()]
        }

  defstruct available_words: 0,
            required_words: 4,
            missing_words: 4,
            player_count: 0,
            max_players: 4,
            max_supported_players: 0,
            enough_players?: false,
            enough_words?: false,
            ready?: false,
            status: :insufficient_words,
            language: "pt",
            has_category_filter?: false,
            broaden_actions: []

  @doc """
  Evaluates word-pool readiness for a lobby roster or form configuration.

  Expects a map with `:available_words`, `:player_count`, `:max_players`, `:language`,
  and `:has_category_filter?`.
  """
  @spec evaluate(map()) :: t()
  def evaluate(%{
        available_words: available_words,
        player_count: player_count,
        max_players: max_players,
        language: language,
        has_category_filter?: has_category_filter?
      })
      when is_integer(available_words) and available_words >= 0 and
             is_integer(player_count) and player_count >= 0 and
             is_integer(max_players) and max_players >= 1 do
    build_evaluation(available_words, player_count, max_players, language, has_category_filter?)
  end

  defp build_evaluation(
         available_words,
         player_count,
         max_players,
         language,
         has_category_filter?
       ) do
    capped_max = min(max_players, @max_players)
    required_words = max(player_count, @min_players) * @words_per_player
    missing_words = max(required_words - available_words, 0)
    enough_players? = player_count >= @min_players and player_count <= capped_max
    enough_words? = available_words >= required_words
    max_supported_players = compute_max_supported_players(available_words, capped_max)
    status = resolve_status(player_count, capped_max, enough_words?)

    broaden_actions =
      compute_broaden_actions(status, has_category_filter?, max_supported_players, player_count)

    %__MODULE__{
      available_words: available_words,
      required_words: required_words,
      missing_words: missing_words,
      player_count: player_count,
      max_players: capped_max,
      max_supported_players: max_supported_players,
      enough_players?: enough_players?,
      enough_words?: enough_words?,
      ready?: status == :ready,
      status: status,
      language: language || "en",
      has_category_filter?: has_category_filter?,
      broaden_actions: broaden_actions
    }
  end

  defp compute_max_supported_players(available_words, capped_max) do
    supported_raw = min(div(available_words, @words_per_player), capped_max)
    if supported_raw >= @min_players, do: supported_raw, else: 0
  end

  defp resolve_status(player_count, capped_max, _enough_words?) when player_count > capped_max,
    do: :too_many_players

  defp resolve_status(_player_count, _capped_max, false), do: :insufficient_words

  defp resolve_status(player_count, _capped_max, true) when player_count < @min_players,
    do: :waiting_for_players

  defp resolve_status(_player_count, _capped_max, true), do: :ready

  defp compute_broaden_actions(:insufficient_words, true, _supported, _player_count) do
    [:add_categories, :all_categories, :change_language]
  end

  defp compute_broaden_actions(:insufficient_words, false, supported, player_count)
       when supported >= @min_players and player_count > supported do
    [:change_language, :fewer_players]
  end

  defp compute_broaden_actions(:insufficient_words, false, _supported, _player_count) do
    [:change_language]
  end

  defp compute_broaden_actions(_other_status, _has_filter, _supported, _player_count), do: []
end
