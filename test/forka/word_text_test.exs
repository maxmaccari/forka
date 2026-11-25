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

    test "EDGE-01: treats empty, whitespace, digits, punctuation, and hyphen-only text as unplayable" do
      for unplayable <- [nil, "", "   ", "12345", "!!!", "---", " - - ", "123-456"] do
        refute WordText.playable_text?(unplayable),
               "expected #{inspect(unplayable)} to be unplayable"
      end

      for playable <- ["a", "é", "café", "beija-flor", "São Paulo", "a1"] do
        assert WordText.playable_text?(playable), "expected #{inspect(playable)} to be playable"
      end
    end

    property "EDGE-04: normalize_text/1 is idempotent and matches downcase/accent folding" do
      check all(text <- StreamData.string(:printable, max_length: 30)) do
        normalized = WordText.normalize_text(text)
        assert WordText.normalize_text(normalized) == normalized
        assert normalized == String.downcase(normalized)

        assert WordText.playable_text?(text) ==
                 (String.replace(normalized, ~r/[\s\-]+/u, "") != "")
      end
    end
  end
end
