defmodule Forka.Factory do
  use ExMachina.Ecto, repo: Forka.Repo

  def category_factory do
    %Forka.Words.Category{
      name: sequence(:category, &"Category #{&1}")
    }
  end

  def word_factory do
    %Forka.Words.Word{
      text: sequence(:word, &"Word #{&1}"),
      category: insert(:category)
    }
  end
end
