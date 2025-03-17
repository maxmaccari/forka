defmodule Forka.Games.Schemas.GameWord do
  @moduledoc """
  This module represents a word being played in a game session, tracking guesses and game state.

  Each GameWord has:
  - A Word struct containing the actual word and metadata
  - A list of guesses made by players
  - The ID of the player who finished guessing the word (if completed)

  This module handles all game logic related to guessing letters, checking word completion,
  and managing the game state for a single word.
  """

  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.Guess

  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.Guess

  schema "game_words" do
    embeds_one :word, Word
    embeds_many :guesses, Guess
    field :finished_by_id, :string

    field :base_word_id, :binary_id

    timestamps()
  end

  def changeset(game_word, attrs) do
    game_word
    |> cast(attrs, [:finished_by_id, :base_word_id])
    |> cast_embed(:word)
    |> cast_embed(:guesses)
  end

  @doc """
  Creates a new GameWord struct for the given Word.

  ## Parameters
    - word: A Word struct containing the word to be guessed

  ## Examples
      iex> word = Word.new("hello", "greeting")
      iex> GameWord.new(word)
      #GameWord<word: #Word<hello (greeting)>, guesses: [], display: "_____", finished?: false>
  """
  def new(%Word{} = word) do
    %__MODULE__{
      word: word,
      base_word_id: word.id
    }
  end

  @doc """
  Processes a letter guess from a player.

  ## Parameters
    - game_word: The current GameWord struct
    - letter: The letter being guessed
    - guessed_by_player_id: ID of the player making the guess

  ## Returns
    - `{:ok, updated_game_word, guess}` if the guess was valid, where guess is the new Guess struct
    - `{:error, :letter_already_guessed}` if the letter was already guessed

  ## Examples
      iex> game_word = GameWord.new(Word.new("hello", "greeting"))
      iex> {:ok, _game_word, guess} = GameWord.guess(game_word, "h", "player1")
      iex> Map.put(guess, :guessed_at, nil)
      %Forka.Games.Schemas.Guess{letter: \"h\", guessed_by_player_id: \"player1\", correct?: true}
  """
  def guess(%__MODULE__{guesses: guesses, word: word} = game_word, letter, guessed_by_player_id) do
    if can_guess_letter?(guesses, letter) do
      correct? = Word.contain_letter?(word, letter)
      guess = Guess.new(letter, guessed_by_player_id, correct?)
      new_guesses = [guess | guesses]

      {:ok, check_finished(%{game_word | guesses: new_guesses}, guessed_by_player_id), guess}
    else
      {:error, :letter_already_guessed}
    end
  end

  @doc """
  Returns a list showing which letters of the word have been found.

  ## Parameters
    - game_word: The GameWord struct to check

  ## Returns
  List of tuples in the format `{:found, letter}` or `:hidden`

  ## Examples
      iex> game_word = GameWord.new(Word.new("hello", "greeting"))
      iex> {:ok, game_word, _guess} = GameWord.guess(game_word, "h", "player1")
      iex> GameWord.display_word_letters(game_word)
      [{:found, "h"}, :hidden, :hidden, :hidden, :hidden]
  """
  def display_word_letters(%__MODULE__{word: word, guesses: guesses}),
    do: Word.check_word_letters(word, guessed_letters(guesses))

  @doc """
  Checks if the word has been completely guessed.

  ## Parameters
    - game_word: The GameWord struct to check

  ## Returns
  Boolean indicating if all letters have been guessed
  """
  def finished?(%__MODULE__{word: word, guesses: guesses}),
    do: Word.finished?(word, guessed_letters(guesses))

  @doc """
  Returns all guesses made by a specific player.

  ## Parameters
    - game_word: The GameWord struct to check
    - player_id: The ID of the player

  ## Returns
  List of Guess structs made by the player
  """
  def guesses_from_player(%__MODULE__{guesses: guesses}, player_id),
    do: Enum.filter(guesses, &(&1.guessed_by_player_id == player_id))

  defp can_guess_letter?([], _), do: true

  defp can_guess_letter?(guesses, letter),
    do: !Enum.any?(guesses, &(&1.letter == String.downcase(letter)))

  defp check_finished(%__MODULE__{guesses: guesses, word: word} = game_word, finished_by_id) do
    if Word.finished?(word, guessed_letters(guesses)) do
      %{game_word | finished_by_id: finished_by_id}
    else
      game_word
    end
  end

  defp guessed_letters(guesses), do: Enum.map(guesses, & &1.letter)
end

defimpl Inspect, for: Forka.Games.Schemas.GameWord do
  import Inspect.Algebra

  alias Forka.Games.Schemas.GameWord

  def inspect(%GameWord{word: word, guesses: guesses} = game_word, opts) do
    # Computed fields
    word_letters = GameWord.display_word_letters(game_word)
    finished? = GameWord.finished?(game_word)

    word_display =
      word_letters
      |> Enum.map(fn
        {:found, letter} -> letter
        :hidden -> "_"
      end)
      |> Enum.join("")

    concat([
      "#GameWord<",
      # Stored fields
      "word: ",
      to_doc(word, opts),
      ", guesses: ",
      to_doc(guesses, opts),
      # Computed fields
      ", display: \"",
      word_display,
      "\"",
      ", finished?: ",
      to_doc(finished?, opts),
      ">"
    ])
  end
end
