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

  def admin_factory(attrs \\ %{}) do
    password = attrs[:password] || "Password1!456"
    email = attrs[:email] || sequence(:admin_email, &"admin#{&1}@example.com")

    %Forka.Backoffice.Admin{
      email: email,
      password: password,
      hashed_password: Bcrypt.hash_pwd_salt(password)
    }
  end
end
