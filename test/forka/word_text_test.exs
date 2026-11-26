defmodule Forka.WordTextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Forka.WordText

  describe "normalize_text/1 and playable_text?/1" do
    test "REQ-01: folds case, accents, cedilla, extra whitespace, hyphens, and punctuation" do
      assert WordText.normalize_text("Café") == "cafe"
      assert WordText.normalize_text("cafe") == "cafe"
      assert WordText.normalize_text("CAFÉ") == "cafe"
      assert WordText.normalize_text("Coração") == "coracao"
      assert WordText.normalize_text("coracao") == "coracao"
      assert WordText.normalize_text("  São   Paulo  ") == "sao paulo"
      assert WordText.normalize_text("beija--flor") == "beija-flor"
      assert WordText.normalize_text("he0123@#$llo") == "hello"
      assert WordText.normalize_text(nil) == ""
    end

    test "supported_letters/0 returns uppercase A-Z input letters" do
      assert WordText.supported_letters() == Enum.map(?A..?Z, &<<&1>>)
    end

    test "EDGE-01: treats empty, whitespace, digits, punctuation, hyphen-only, and unsupported-letter text as unplayable" do
      for unplayable <- [
            nil,
            "",
            "   ",
            "12345",
            "!!!",
            "---",
            " - - ",
            "123-456",
            "straße",
            "ß",
            "aß",
            "øl",
            "łódź",
            "œuf",
            "αβγ",
            "привет"
          ] do
        refute WordText.playable_text?(unplayable),
               "expected #{inspect(unplayable)} to be unplayable"
      end

      for playable <- ["a", "é", "café", "beija-flor", "São Paulo", "a1"] do
        assert WordText.playable_text?(playable), "expected #{inspect(playable)} to be playable"
      end
    end

    property "EDGE-04: normalize_text/1 is idempotent and playable_text?/1 requires every normalized letter to be supported" do
      supported = MapSet.new(WordText.supported_letters(), &String.downcase/1)

      check all(text <- StreamData.string(:utf8, max_length: 30)) do
        normalized = WordText.normalize_text(text)
        assert WordText.normalize_text(normalized) == normalized
        assert normalized == String.downcase(normalized)

        letters =
          normalized
          |> String.replace(~r/[\s\-]+/u, "")
          |> String.graphemes()

        expected_playable? = letters != [] and Enum.all?(letters, &MapSet.member?(supported, &1))
        assert WordText.playable_text?(text) == expected_playable?
      end
    end
  end
end
