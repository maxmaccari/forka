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
    email = attrs[:email] || sequence(:admin_email, &"admin#{&1}@example.com")
    password = attrs[:password] || "Password1!456"

    %Forka.Backoffice.Admin{
      email: email,
      password: password,
      hashed_password: Bcrypt.hash_pwd_salt(password)
    }
  end

  def player_factory(attrs \\ %{}) do
    email = attrs[:email] || sequence(:player_email, &"player#{&1}@example.com")
    username = attrs[:username] || unique_player_username()
    password = attrs[:password] || "Password1!456"

    %Forka.Players.Player{
      email: email,
      username: username,
      password: password,
      hashed_password: Bcrypt.hash_pwd_salt(password)
    }
  end

  def game_factory() do
    owner = insert(:player)

    %Forka.Games.Schemas.Game{
      name: sequence(:game_name, &"Game #{&1}"),
      max_players: 4,
      status: :lobby,
      owner_id: owner.id,
      game_players: [],
      game_words: [],
      word_options: %{language: "en"}
    }
  end

  # Custom Helpers

  def player_registration_params(attrs \\ %{}) do
    :player
    |> build(attrs)
    |> Map.take([:email, :username, :password])
  end

  defp unique_player_username() do
    sequence(:player_username, &"player#{&1}") |> String.slice(0, 20)
  end
end
