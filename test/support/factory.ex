defmodule Forka.Factory do
  alias Forka.Games.Schemas.WordOptions
  use ExMachina.Ecto, repo: Forka.Repo

  def category_factory do
    %Forka.Words.Category{
      name: sequence(:category, &"Category #{&1}")
    }
  end

  def word_factory do
    %Forka.Words.Word{
      text: sequence(:word, &unique_random_sequence_of_letters/1),
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

  def game_factory(attrs \\ %{}) do
    owner = attrs[:owner] || insert(:player)

    %Forka.Games.Schemas.Game{
      name: attrs[:name] || sequence(:game_name, &"Game #{&1}"),
      max_players: attrs[:max_players] || 4,
      status: attrs[:status] || :lobby,
      owner_id: attrs[:owner_id] || owner.id,
      game_players: attrs[:game_player] || [],
      game_words: attrs[:game_words] || [],
      word_options: attrs[:word_options] || WordOptions.new(%{language: "en"})
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

  defp unique_random_sequence_of_letters(number) do
    letters = "abcdefghijklmnopqrstuvwxyz"

    base = number_to_letters(number)

    random_part =
      1..10
      |> Enum.map(fn _ -> String.at(letters, :rand.uniform(26) - 1) end)
      |> Enum.join("")

    base <> random_part
  end

  defp number_to_letters(number) do
    # Base case: if number is 0, return an empty string
    if number < 0 do
      ""
    else
      # Convert number to base-26 representation
      # We subtract 1 from the remainder to map 0->a, 1->b, etc.
      remainder = rem(number, 26)
      quotient = div(number, 26)

      # Convert the remainder to a letter (a-z)
      letter = <<remainder + ?a>>

      # Recursively process the quotient and append the current letter
      if quotient == 0 do
        letter
      else
        number_to_letters(quotient - 1) <> letter
      end
    end
  end
end
