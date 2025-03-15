defmodule Forka.WordsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Forka.Words` context.
  """

  @doc """
  Generate a category.
  """
  def category_fixture(attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{
        language: "en",
        name: "some category"
      })
      |> Forka.Words.create_category()

    category
  end
end
