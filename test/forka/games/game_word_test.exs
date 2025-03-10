defmodule Forka.Games.GameWordTest do
  use ExUnit.Case
  alias Forka.Games.{GameWord, Word, Guess}

  doctest Forka.Games.GameWord

  setup do
    word = Word.new("hello", "greeting")
    game_word = GameWord.new(word)
    {:ok, game_word: game_word}
  end

  test "new/1 creates a new GameWord struct", %{game_word: game_word} do
    assert %GameWord{word: %Word{word: "hello"}, guesses: []} = game_word
  end

  test "guess/3 processes a correct guess", %{game_word: game_word} do
    {:ok, updated_game_word, guess} = GameWord.guess(game_word, "h", "player1")
    assert [%Guess{letter: "h", correct?: true}] = updated_game_word.guesses
    assert %Guess{letter: "h", correct?: true} = guess
  end

  test "guess/3 processes an incorrect guess", %{game_word: game_word} do
    {:ok, updated_game_word, guess} = GameWord.guess(game_word, "n", "player1")
    assert [%Guess{letter: "n", correct?: false}] = updated_game_word.guesses
    assert %Guess{letter: "n", correct?: false} = guess
  end

  test "guess/3 returns error for already guessed letter", %{game_word: game_word} do
    {:ok, updated_game_word, _guess} = GameWord.guess(game_word, "h", "player1")
    assert {:error, :letter_already_guessed} = GameWord.guess(updated_game_word, "h", "player1")
  end

  test "display_word_letters/1 shows correct letters", %{game_word: game_word} do
    {:ok, updated_game_word, _guess} = GameWord.guess(game_word, "h", "player1")

    assert GameWord.display_word_letters(updated_game_word) == [
             {:found, "h"},
             :hidden,
             :hidden,
             :hidden,
             :hidden
           ]
  end

  test "finished?/1 returns true when word is completely guessed", %{game_word: game_word} do
    {:ok, game_word, _guess} = GameWord.guess(game_word, "h", "player1")
    {:ok, game_word, _guess} = GameWord.guess(game_word, "e", "player1")
    {:ok, game_word, _guess} = GameWord.guess(game_word, "l", "player1")
    {:ok, game_word, _guess} = GameWord.guess(game_word, "o", "player1")
    assert GameWord.finished?(game_word)
    assert game_word.finished_by_id == "player1"
  end

  test "guesses_from_player/2 returns guesses for specific player", %{game_word: game_word} do
    {:ok, game_word, _guess} = GameWord.guess(game_word, "h", "player1")
    {:ok, game_word, _guess} = GameWord.guess(game_word, "e", "player2")
    {:ok, game_word, _guess} = GameWord.guess(game_word, "l", "player1")

    player1_guesses = GameWord.guesses_from_player(game_word, "player1")
    assert length(player1_guesses) == 2
    assert Enum.all?(player1_guesses, &(&1.guessed_by_player_id == "player1"))
  end
end
