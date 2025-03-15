defmodule Forka.WordsTest do
  use Forka.DataCase

  alias Forka.Words

  describe "categories" do
    alias Forka.Words.Category

    import Forka.WordsFixtures

    @invalid_attrs %{name: nil, language: nil}

    test "list_categories/0 returns all categories" do
      category = category_fixture()
      assert Words.list_categories() == [category]
    end

    test "get_category!/1 returns the category with given id" do
      category = category_fixture()
      assert Words.get_category!(category.id) == category
    end

    test "create_category/1 with valid data creates a category" do
      valid_attrs = %{name: "some name", language: "some language"}

      assert {:ok, %Category{} = category} = Words.create_category(valid_attrs)
      assert category.name == "some name"
      assert category.language == "some language"
    end

    test "create_category/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Words.create_category(@invalid_attrs)
    end

    test "update_category/2 with valid data updates the category" do
      category = category_fixture()
      update_attrs = %{name: "some updated name", language: "some updated language"}

      assert {:ok, %Category{} = category} = Words.update_category(category, update_attrs)
      assert category.name == "some updated name"
      assert category.language == "some updated language"
    end

    test "update_category/2 with invalid data returns error changeset" do
      category = category_fixture()
      assert {:error, %Ecto.Changeset{}} = Words.update_category(category, @invalid_attrs)
      assert category == Words.get_category!(category.id)
    end

    test "delete_category/1 deletes the category" do
      category = category_fixture()
      assert {:ok, %Category{}} = Words.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> Words.get_category!(category.id) end
    end

    test "change_category/1 returns a category changeset" do
      category = category_fixture()
      assert %Ecto.Changeset{} = Words.change_category(category)
    end
  end
end
