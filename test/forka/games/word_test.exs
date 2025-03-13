defmodule Forka.Games.WordTest do
  use ExUnit.Case
  alias Forka.Games.Word

  doctest Forka.Games.Word

  test "new/2 creates a new Word struct" do
    assert %Word{text: "hello", category: "greeting"} = Word.new("hello", "greeting")

    # Downcasing letters
    assert %Word{text: "hello", category: "greeting"} = Word.new("HELLO", "greeting")

    # Allow space
    assert %Word{text: "hello world", category: "greeting"} =
             Word.new("hello world", "greeting")

    # Allow one space
    assert %Word{text: "hello world", category: "greeting"} =
             Word.new("hello  world", "greeting")

    # Allow hyphens
    assert %Word{text: "hello-world", category: "greeting"} =
             Word.new("hello-world", "greeting")

    # Allow one hyphen
    assert %Word{text: "hello-world", category: "greeting"} =
             Word.new("hello--world", "greeting")

    # Trim
    assert %Word{text: "hello", category: "greeting"} =
             Word.new("   hello   ", "greeting")

    #  Remove numbers
    assert %Word{text: "hello", category: "greeting"} =
             Word.new("he0123456789llo", "greeting")

    #  Remove speial chracters
    assert %Word{text: "hello", category: "greeting"} =
             Word.new("he@#$%llo", "greeting")
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

  test "finished?/2 returns true if all letters are guessed ignoring spaces" do
    word = Word.new("hello world", "greeting")
    guessed_letters = ["h", "e", "l", "o", "w", "r", "d"]
    assert Word.finished?(word, guessed_letters)
  end

  test "finished?/2 returns true if all letters are guessed ignoring hiphens" do
    word = Word.new("hello-world", "greeting")
    guessed_letters = ["h", "e", "l", "o", "w", "r", "d"]
    assert Word.finished?(word, guessed_letters)
  end

  test "check_word_letters/2 returns correct letter visibility" do
    guessed_letters = ["h", "e"]

    assert Word.check_word_letters(Word.new("hello", ""), guessed_letters) == [
             {:found, "h"},
             {:found, "e"},
             :hidden,
             :hidden,
             :hidden
           ]

    assert Word.check_word_letters(Word.new("hello world", ""), guessed_letters) == [
             {:found, "h"},
             {:found, "e"},
             :hidden,
             :hidden,
             :hidden,
             {:found, " "},
             :hidden,
             :hidden,
             :hidden,
             :hidden,
             :hidden
           ]

    assert Word.check_word_letters(Word.new("hello-world", ""), guessed_letters) == [
             {:found, "h"},
             {:found, "e"},
             :hidden,
             :hidden,
             :hidden,
             {:found, "-"},
             :hidden,
             :hidden,
             :hidden,
             :hidden,
             :hidden
           ]
  end

  test "letters_count_in_word/2 returns correct letter count" do
    word = Word.new("hello", "greeting")
    assert Word.letters_count_in_word(word, "l") == 2
    assert Word.letters_count_in_word(word, "h") == 1
    assert Word.letters_count_in_word(word, "z") == 0
  end

  test "letters_count/1 returns correct letters count ignoring spaces and hyphens" do
    assert Word.letters_count(Word.new("hello", "")) == 5
    assert Word.letters_count(Word.new("hello world", "")) == 10
    assert Word.letters_count(Word.new("hello-world", "")) == 10
  end
end
