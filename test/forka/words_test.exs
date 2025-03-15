defmodule Forka.WordsTest do
  use Forka.DataCase

  alias Forka.Words

  describe "categories" do
    alias Forka.Words.Category

    @invalid_attrs %{name: "", language: "non iso character"}

    test "list_categories/0 returns all categories" do
      category = insert(:category)
      assert Words.list_categories() == [category]
    end

    test "list_categories/1 returns all categories by language" do
      pt_category = insert(:category, language: "pt")
      en_category = insert(:category, language: "en")

      assert Words.list_categories(language: "pt") == [pt_category]
      assert Words.list_categories(language: "en") == [en_category]
      assert Words.list_categories(language: "EN") == [en_category]
    end

    test "get_category!/1 returns the category with given id" do
      category = insert(:category)
      assert Words.get_category!(category.id) == category
    end

    test "create_category/1 with valid data creates a category" do
      valid_attrs = %{name: "some name", language: "en"}

      assert {:ok, %Category{} = category} = Words.create_category(valid_attrs)
      assert category.name == "some name"
      assert category.language == "en"
    end

    test "create_category/1 using a category name that already exists for that language returns an error" do
      valid_attrs = %{name: "some name", language: "en"}

      assert {:ok, %Category{}} = Words.create_category(valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Words.create_category(valid_attrs)
      assert {:ok, %Category{}} = Words.create_category(%{valid_attrs | language: "pt"})
    end

    test "create_category/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Words.create_category(@invalid_attrs)
    end

    test "update_category/2 with valid data updates the category" do
      category = insert(:category)
      update_attrs = %{name: "some updated name", language: "pt"}

      assert {:ok, %Category{} = category} = Words.update_category(category, update_attrs)
      assert category.name == "some updated name"
      assert category.language == "pt"
    end

    test "update_category/2 with invalid data returns error changeset" do
      category = insert(:category)
      assert {:error, %Ecto.Changeset{}} = Words.update_category(category, @invalid_attrs)
      assert category == Words.get_category!(category.id)
    end

    test "delete_category/1 deletes the category" do
      category = insert(:category)
      assert {:ok, %Category{}} = Words.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> Words.get_category!(category.id) end
    end

    test "change_category/1 returns a category changeset" do
      category = insert(:category)
      assert %Ecto.Changeset{} = Words.change_category(category)
    end
  end

  describe "words" do
    alias Forka.Words.Word

    @invalid_attrs %{text: nil}

    test "list_words/0 returns all words" do
      word = insert(:word)
      assert Words.list_words() == [word]
    end

    test "get_word!/1 returns the word with given id" do
      word = insert(:word)
      assert Words.get_word!(word.id) == word
    end

    test "create_word/1 with valid data creates a word" do
      category = insert(:category)
      valid_attrs = %{text: "some text", category_id: category.id}

      assert {:ok, %Word{} = word} = Words.create_word(valid_attrs)
      assert word.text == "some text"
    end

    test "create_category/1 using a name that already exists for a category returns an error" do
      category = insert(:category)
      valid_attrs = %{text: "some text", category_id: category.id}

      assert {:ok, %Word{}} = Words.create_word(valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Words.create_word(valid_attrs)

      # It works case insensitive
      case_different_attrs = %{text: String.upcase(valid_attrs.text), category_id: category.id}
      assert {:error, %Ecto.Changeset{}} = Words.create_word(case_different_attrs)

      # But I can create for other categories
      assert {:ok, %Word{}} =
               Words.create_word(%{valid_attrs | category_id: insert(:category).id})
    end

    test "create_word/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Words.create_word(@invalid_attrs)
    end

    test "update_word/2 with valid data updates the word" do
      word = insert(:word)
      update_attrs = %{text: "some updated text"}

      assert {:ok, %Word{} = word} = Words.update_word(word, update_attrs)
      assert word.text == "some updated text"
    end

    test "update_word/2 with invalid data returns error changeset" do
      word = insert(:word)
      assert {:error, %Ecto.Changeset{}} = Words.update_word(word, @invalid_attrs)
      assert word == Words.get_word!(word.id)
    end

    test "delete_word/1 deletes the word" do
      word = insert(:word)
      assert {:ok, %Word{}} = Words.delete_word(word)
      assert_raise Ecto.NoResultsError, fn -> Words.get_word!(word.id) end
    end

    test "change_word/1 returns a word changeset" do
      word = insert(:word)
      assert %Ecto.Changeset{} = Words.change_word(word)
    end
  end
end
