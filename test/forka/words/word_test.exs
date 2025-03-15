defmodule Forka.Words.WordTest do
  use Forka.DataCase, async: true

  alias Forka.Words.Word
  alias Forka.Words.Category

  describe "changeset/2" do
    setup do
      {:ok, category} = Repo.insert(%Category{name: "Test Category", language: "en"})
      %{category: category}
    end

    test "validates required fields" do
      changeset = Word.changeset(%Word{}, %{})
      assert %{text: ["can't be blank"], category_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates with valid attributes", %{category: category} do
      changeset = Word.changeset(%Word{}, %{text: "example", category_id: category.id})
      assert changeset.valid?
    end

    test "enforces unique constraint on text and category_id", %{category: category} do
      # This test requires database interaction
      {:ok, _} = Repo.insert(%Word{text: "unique word", category_id: category.id})

      {:error, changeset} =
        %Word{}
        |> Word.changeset(%{text: "unique word", category_id: category.id})
        |> Repo.insert()

      assert %{text: ["has already been taken"]} = errors_on(changeset)

      # Different category should work
      {:ok, other_category} = Repo.insert(%Category{name: "Other Category", language: "pt"})

      changeset = Word.changeset(%Word{}, %{text: "unique word", category_id: other_category.id})
      assert changeset.valid?
    end
  end
end
