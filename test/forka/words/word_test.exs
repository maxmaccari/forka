defmodule Forka.Words.WordTest do
  use Forka.DataCase, async: true

  alias Forka.Words.Word
  alias Forka.Words.Category

  test "the admin changeset attaches a missing category error to the select field" do
    assert {:error, changeset} =
             %Word{}
             |> Word.admin_changeset(%{text: "orphan", category_id: Ecto.UUID.generate()}, [])
             |> Repo.insert()

    assert %{category_id: ["does not exist"]} = errors_on(changeset)
  end

  describe "changeset/2" do
    setup do
      {:ok, category} = Repo.insert(%Category{name: "Test Category", language: "en"})
      %{category: category}
    end

    test "validates required fields" do
      changeset = Word.changeset(%Word{}, %{})
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates with valid attributes", %{category: category} do
      changeset = Word.changeset(%Word{}, %{text: "example", category_id: category.id})
      assert changeset.valid?
    end

    test "enforces unique constraint on text and category_id", %{category: category} do
      # This test requires database interaction
      {:ok, _} = Repo.insert(%Word{text: "unique word", category_id: category.id})

      {:error, changeset} =
        %Word{category_id: category.id}
        |> Word.changeset(%{text: "unique word"})
        |> Repo.insert()

      assert %{text: ["has already been taken"]} = errors_on(changeset)

      # Different category should work
      {:ok, other_category} = Repo.insert(%Category{name: "Other Category", language: "pt"})

      changeset = Word.changeset(%Word{category_id: other_category.id}, %{text: "unique word"})
      assert changeset.valid?
    end

    test "F-09: returns an error instead of raising when the category does not exist" do
      {:error, changeset} =
        %Word{}
        |> Word.changeset(%{text: "orphan", category_id: Ecto.UUID.generate()})
        |> Repo.insert()

      assert %{category: ["does not exist"]} = errors_on(changeset)
    end
  end
end
