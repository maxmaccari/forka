defmodule Forka.Games.WordAvailabilityTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Forka.Games.WordAvailability

  describe "evaluate/1" do
    test "REQ-02 & REQ-03: marks ready for 2..6 players when available_words >= player_count * 2" do
      two_players =
        WordAvailability.evaluate(%{
          available_words: 4,
          player_count: 2,
          max_players: 2,
          language: "pt",
          has_category_filter?: false
        })

      assert two_players.required_words == 4
      assert two_players.missing_words == 0
      assert two_players.enough_players? == true
      assert two_players.enough_words? == true
      assert two_players.ready? == true
      assert two_players.status == :ready
      assert two_players.broaden_actions == []

      six_players =
        WordAvailability.evaluate(%{
          available_words: 12,
          player_count: 6,
          max_players: 6,
          language: "pt",
          has_category_filter?: true
        })

      assert six_players.required_words == 12
      assert six_players.missing_words == 0
      assert six_players.ready? == true
      assert six_players.status == :ready
    end

    test "REQ-03: marks waiting_for_players when < 2 players but pool covers minimum 4 words" do
      result =
        WordAvailability.evaluate(%{
          available_words: 4,
          player_count: 1,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      assert result.required_words == 4
      assert result.missing_words == 0
      assert result.enough_players? == false
      assert result.enough_words? == true
      assert result.ready? == false
      assert result.status == :waiting_for_players
    end

    test "REQ-03: marks too_many_players when roster exceeds 6 or max_players" do
      result =
        WordAvailability.evaluate(%{
          available_words: 20,
          player_count: 7,
          max_players: 6,
          language: "pt",
          has_category_filter?: false
        })

      assert result.enough_players? == false
      assert result.ready? == false
      assert result.status == :too_many_players
    end

    test "REQ-06: computes missing_words and broaden_actions when filtered categories are too small" do
      result =
        WordAvailability.evaluate(%{
          available_words: 4,
          player_count: 3,
          max_players: 6,
          language: "pt",
          has_category_filter?: true
        })

      assert result.required_words == 6
      assert result.missing_words == 2
      assert result.max_supported_players == 2
      assert result.enough_words? == false
      assert result.ready? == false
      assert result.status == :insufficient_words
      assert result.broaden_actions == [:add_categories, :all_categories, :change_language]
    end

    test "REQ-06: omits category actions when all categories are already selected" do
      with_fewer_option =
        WordAvailability.evaluate(%{
          available_words: 6,
          player_count: 4,
          max_players: 6,
          language: "pt",
          has_category_filter?: false
        })

      assert with_fewer_option.status == :insufficient_words
      assert with_fewer_option.required_words == 8
      assert with_fewer_option.missing_words == 2
      assert with_fewer_option.max_supported_players == 3
      assert with_fewer_option.broaden_actions == [:change_language, :fewer_players]

      below_minimum_match =
        WordAvailability.evaluate(%{
          available_words: 3,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      assert below_minimum_match.status == :insufficient_words
      assert below_minimum_match.required_words == 4
      assert below_minimum_match.missing_words == 1
      assert below_minimum_match.max_supported_players == 0
      assert below_minimum_match.broaden_actions == [:change_language]
    end

    property "EDGE-04: ready? holds iff player_count is in 2..min(max_players, 6) and available_words >= player_count * 2" do
      check all(
              available_words <- StreamData.integer(0..20),
              player_count <- StreamData.integer(0..8),
              max_players <- StreamData.integer(2..6),
              has_filter <- StreamData.boolean()
            ) do
        result =
          WordAvailability.evaluate(%{
            available_words: available_words,
            player_count: player_count,
            max_players: max_players,
            language: "pt",
            has_category_filter?: has_filter
          })

        expected_required = max(player_count, 2) * 2
        expected_ready? = player_count in 2..max_players and available_words >= expected_required

        assert result.required_words == expected_required
        assert result.missing_words == max(expected_required - available_words, 0)
        assert result.ready? == expected_ready?
      end
    end
  end
end
