defmodule Forka.Factory do
  use ExMachina.Ecto, repo: Forka.Repo

  def category_factory do
    %Forka.Words.Category{
      name: sequence(:category, &"Category #{&1}")
    }
  end
end
