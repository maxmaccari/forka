defmodule Forka.Games.Word do
  @moduledoc """
  This module represents a word in the Forka game, providing functionality to manage words,
  check letters, and track game progress.

  Each word has:
  - A word value (required)
  - A category (required)
  - An optional hint

  The module handles special characters and accents in words automatically.
  """

  defstruct text: nil, hint: nil, category: nil, language: "en"

  @doc """
  Creates a new Word struct.

  ## Parameters
    - word: The word to be guessed
    - category: The category the word belongs to
    - hint: Optional hint for the word

  ## Examples
      iex> Word.new("elixir", "programming")
      #Word<elixir (programming)>

      iex> Word.new("café", "food", "Hot beverage")
      #Word<café (food)>
  """
  def new(text, category, hint \\ nil, language \\ "en") do
    sanitized_text =
      text
      |> String.trim()
      |> sanitize_text()
      |> String.downcase()

    %__MODULE__{
      text: sanitized_text,
      category: category,
      hint: hint,
      language: language
    }
  end

  @doc """
  Creates a Word struct from a map containing word data.

  ## Parameters
    - map: A map containing at least :text and :category keys, with optional :hint and :language keys

  ## Examples
      iex> Word.from_map(%{text: "elixir", category: "programming"})
      #Word<elixir (programming)>

      iex> Word.from_map(%{text: "café", category: "food", hint: "Hot beverage", language: "pt"})
      #Word<café (food)>
  """
  def from_map(%{text: text, category: category} = map) do
    hint = Map.get(map, :hint)
    language = Map.get(map, :language, "en")

    new(text, category, hint, language)
  end

  defp sanitize_text(text) do
    text
    # Replace multiple spaces with a single space
    |> String.replace(~r/\s{2,}/u, " ")
    # Replace multiple hyphens with a single hyphen
    |> String.replace(~r/-{2,}/u, "-")
    # Remove special characters
    |> String.replace(~r/[^\p{L}\s\-]+/u, "")
  end

  @doc """
  Checks which letters from the given list are present in the word.
  Returns a list of tuples indicating if each letter was found in the word or hidden.

  The function considers letters in a case-insensitive manner and treats spaces and hyphens as found characters.

  ## Parameters
    - word: Word struct
    - letters: List of letters to check

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.check_word_letters(word, ["h", "x", "l"])
      [{:found, "h"}, :hidden, {:found, "l"}, {:found, "l"}, :hidden]

      iex> word = Word.new("café", "food")
      iex> Word.check_word_letters(word, ["c", "a", "f", "e", "x"])
      [{:found, "c"}, {:found, "a"}, {:found, "f"}, {:found, "é"}]
  """
  def check_word_letters(%__MODULE__{text: text}, letters) when is_list(letters) do
    normalized_text = text |> normalized_text() |> String.graphemes()
    displayable_text = String.graphemes(text)

    for {letter, display_letter} <- Enum.zip(normalized_text, displayable_text) do
      if letter in letters or letter in [" ", "-"] do
        {:found, display_letter}
      else
        :hidden
      end
    end
  end

  @doc """
  Checks if a letter is present in the word.

  ## Parameters
    - word: Word struct
    - letter: Single letter to check

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.contain_letter?(word, "h")
      true
      iex> Word.contain_letter?(word, "x")
      false
  """
  def contain_letter?(%__MODULE__{text: text}, letter) when is_binary(letter),
    do: String.downcase(letter) in unique_letters(text)

  @doc """
  Checks if all letters in the word have been guessed.

  ## Parameters
    - word: Word struct
    - guessed_letters: List of letters that have been guessed

  ## Examples
      iex> word = Word.new("hi", "greeting")
      iex> Word.finished?(word, ["h", "i"])
      true
      iex> Word.finished?(word, ["h"])
      false
  """
  def finished?(%__MODULE__{text: text}, guessed_letters) when is_list(guessed_letters) do
    text
    |> remove_spaces_and_hyphens()
    |> unique_letters()
    |> Enum.all?(&(&1 in guessed_letters))
  end

  defp remove_spaces_and_hyphens(text), do: String.replace(text, ~r/[\s\-]+/u, "")

  @doc """
  Counts how many times a letter appears in a word.

  ## Parameters
    - word: Word struct
    - letter: Single letter to count occurrences of

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.letters_count_in_word(word, "l")
      2
      iex> Word.letters_count_in_word(word, "x")
      0
  """
  def letters_count_in_word(%__MODULE__{text: text}, letter) when is_binary(letter) do
    downcase_letter = String.downcase(letter)

    text
    |> normalized_text()
    |> String.graphemes()
    |> Enum.filter(&(&1 == downcase_letter))
    |> length()
  end

  @doc """
  Returns the length of the word's text.

  ## Parameters
    - word: Word struct

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.letters_count(word)
      5
  """
  def letters_count(%__MODULE__{text: text}),
    do: text |> remove_spaces_and_hyphens() |> String.length()

  @doc """
  Returns the category of the word.

  ## Parameters
    - word: Word struct

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.category(word)
      "greeting"
  """
  def category(%__MODULE__{category: category}), do: category

  @doc """
  Returns the hint for the word.

  ## Parameters
    - word: Word struct

  ## Examples
      iex> word = Word.new("hello", "greeting", "A common salutation")
      iex> Word.hint(word)
      "A common salutation"
  """
  def hint(%__MODULE__{hint: hint}), do: hint

  @doc """
  Returns the language of the word.

  ## Parameters
    - word: Word struct

  ## Examples
      iex> word = %Word{text: "hello", category: "greeting", language: "en"}
      iex> Word.language(word)
      "en"
  """
  def language(%__MODULE__{language: language}), do: language

  # Helpers

  defp normalized_text(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\s\-]/u, "")
    |> String.normalize(:nfc)
  end

  defp unique_letters(text) do
    text
    |> normalized_text()
    |> String.graphemes()
    |> Enum.uniq()
    |> Enum.sort()
  end
end

defimpl String.Chars, for: Forka.Games.Word do
  def to_string(%Forka.Games.Word{text: text}), do: text
end

defimpl Inspect, for: Forka.Games.Word do
  import Inspect.Algebra

  def inspect(%Forka.Games.Word{text: text, category: category}, _opts) do
    concat(["#Word<", text, " (", category, ")>"])
  end
end
