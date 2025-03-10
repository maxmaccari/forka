defmodule Forka.Games.WordTest do
  use ExUnit.Case
  alias Forka.Games.Word

  doctest Forka.Games.Word

  test "new/2 creates a new Word struct" do
    word = Word.new("hello", "greeting")
    assert %Word{word: "hello", category: "greeting"} = word
  end

  test "contain_letter?/2 checks if word contains a letter" do
    word = Word.new("hello", "greeting")
    assert Word.contain_letter?(word, "h")
    refute Word.contain_letter?(word, "z")
  end

  test "finished?/2 returns true if all letters are guessed" do
    word = Word.new("hello", "greeting")
    guessed_letters = ["h", "e", "l", "o"]
    assert Word.finished?(word, guessed_letters)
  end

  test "check_word_letters/2 returns correct letter visibility" do
    word = Word.new("hello", "greeting")
    guessed_letters = ["h", "e"]

    assert Word.check_word_letters(word, guessed_letters) == [
             {:found, "h"},
             {:found, "e"},
             :hidden,
             :hidden,
             :hidden
           ]
  end
end
