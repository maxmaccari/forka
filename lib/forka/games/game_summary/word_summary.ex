defmodule Forka.Games.GameSummary.WordSummary do
  @moduledoc """
  This module provides a summary representation of a Word, containing only non-sensitive information.

  Each WordSummary has:
  - The number of letters in the word (but not the word itself)
  - The category the word belongs to
  - An optional hint to help players guess the word

  This module is used to safely share word information with players without revealing
  the actual word being guessed.
  """

  alias Forka.Games.Word

  defstruct letters: 0, category: nil, hint: nil

  @doc false
  def from_word(%Word{} = word) do
    %__MODULE__{
      letters: Word.letters_count(word),
      category: Word.category(word),
      hint: Word.hint(word)
    }
  end
end
