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

  defstruct word: nil, hint: nil, category: nil

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
  def new(word, category, hint \\ nil) do
    %__MODULE__{
      word: String.downcase(word),
      category: category,
      hint: hint
    }
  end

  @doc """
  Checks which letters from the given list are present in the word.
  Returns a list of tuples indicating if each letter was found or hidden.

  ## Parameters
    - word: Word struct
    - letters: List of letters to check

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> Word.check_word_letters(word, ["h", "x", "l"])
      [{:found, "h"}, :hidden, {:found, "l"}, {:found, "l"}, :hidden]
  """
  def check_word_letters(%__MODULE__{word: word}, letters) when is_list(letters) do
    normalized_word = word |> normalized_word() |> String.graphemes()
    displayble_word = String.graphemes(word)

    for {letter, display_letter} <- Enum.zip(normalized_word, displayble_word) do
      if letter in letters do
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
  def contain_letter?(%__MODULE__{word: word}, letter) when is_binary(letter),
    do: String.downcase(letter) in unique_letters(word)

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
  def finished?(%__MODULE__{word: word}, guessed_letters) when is_list(guessed_letters) do
    word
    |> unique_letters()
    |> Enum.all?(&(&1 in guessed_letters))
  end

  defp normalized_word(word) do
    word
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\s]/u, "")
    |> String.normalize(:nfc)
  end

  defp unique_letters(word) do
    word
    |> normalized_word()
    |> String.graphemes()
    |> Enum.uniq()
    |> Enum.sort()
  end
end

defimpl String.Chars, for: Forka.Games.Word do
  def to_string(%Forka.Games.Word{word: word}), do: word
end

defimpl Inspect, for: Forka.Games.Word do
  import Inspect.Algebra

  def inspect(%Forka.Games.Word{word: word, category: category}, _opts) do
    concat(["#Word<", word, " (", category, ")>"])
  end
end
