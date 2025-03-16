defmodule Forka.PlayersTest do
  use Forka.DataCase

  alias Forka.Players

  import Forka.TestHelpers
  alias Forka.Players.{Player, PlayerToken}

  describe "get_player_by_email/1" do
    test "does not return the player if the email does not exist" do
      refute Players.get_player_by_email("unknown@example.com")
    end

    test "returns the player if the email exists" do
      %{id: id} = player = insert(:player)
      assert %Player{id: ^id} = Players.get_player_by_email(player.email)
    end
  end

  describe "get_player_by_email_and_password/2" do
    test "does not return the player if the email does not exist" do
      refute Players.get_player_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the player if the password is not valid" do
      player = insert(:player)
      refute Players.get_player_by_email_and_password(player.email, "invalid")
    end

    test "returns the player if the email and password are valid" do
      %{id: id} = player = insert(:player)

      assert %Player{id: ^id} =
               Players.get_player_by_email_and_password(player.email, player.password)
    end
  end

  describe "get_player_by_credentials/2" do
    test "does not return the player if the email or username does not exist" do
      refute Players.get_player_by_credentials("unknown@example.com", "hello world!")
      refute Players.get_player_by_credentials("unknown_username", "hello world!")
    end

    test "does not return the player if the password is not valid" do
      player = insert(:player)
      refute Players.get_player_by_credentials(player.email, "invalid")
      refute Players.get_player_by_credentials(player.username, "invalid")
    end

    test "returns the player if the email and password are valid" do
      %{id: id} = player = insert(:player)

      assert %Player{id: ^id} =
               Players.get_player_by_credentials(player.email, player.password)
    end

    test "returns the player if the username and password are valid" do
      %{id: id} = player = insert(:player)

      assert %Player{id: ^id} =
               Players.get_player_by_credentials(player.username, player.password)
    end
  end

  describe "get_player!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Players.get_player!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the player with the given id" do
      %{id: id} = player = insert(:player)
      assert %Player{id: ^id} = Players.get_player!(player.id)
    end
  end

  describe "register_player/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Players.register_player(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Players.register_player(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Players.register_player(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = insert(:player)
      {:error, changeset} = Players.register_player(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Players.register_player(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers players with a hashed password" do
      %{email: email} = player_params = params_for(:player)
      {:ok, player} = Players.register_player(player_params)
      assert player.email == email
      assert is_binary(player.hashed_password)
      assert is_nil(player.confirmed_at)
      assert is_nil(player.password)
    end
  end

  describe "change_player_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Players.change_player_registration(%Player{})
      assert changeset.required == [:password, :username, :email]
    end

    test "allows fields to be set" do
      %{email: email, username: username, password: password} =
        player_params = params_for(:player)

      changeset =
        Players.change_player_registration(
          %Player{},
          player_params
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :username) == username
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_player_email/2" do
    test "returns a player changeset" do
      assert %Ecto.Changeset{} = changeset = Players.change_player_email(%Player{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_player_email/3" do
    setup do
      %{player: insert(:player)}
    end

    test "requires email to change", %{player: player} do
      {:error, changeset} = Players.apply_player_email(player, player.password, %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{player: player} do
      {:error, changeset} =
        Players.apply_player_email(player, player.password, %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{player: player} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Players.apply_player_email(player, player.password, %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{player: player} do
      %{email: email} = insert(:player)
      password = player.password

      {:error, changeset} = Players.apply_player_email(player, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{player: player} do
      %{email: new_email} = params_for(:player)

      {:error, changeset} =
        Players.apply_player_email(player, "invalid", %{email: new_email})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{player: player} do
      %{email: email} = params_for(:player)
      {:ok, player} = Players.apply_player_email(player, player.password, %{email: email})
      assert player.email == email
      assert Players.get_player!(player.id).email != email
    end
  end

  describe "deliver_player_update_email_instructions/3" do
    setup do
      %{player: insert(:player)}
    end

    test "sends token through notification", %{player: player} do
      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_update_email_instructions(player, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert player_token = Repo.get_by(PlayerToken, token: :crypto.hash(:sha256, token))
      assert player_token.player_id == player.id
      assert player_token.sent_to == player.email
      assert player_token.context == "change:current@example.com"
    end
  end

  describe "update_player_email/2" do
    setup do
      player = insert(:player)
      %{email: email} = params_for(:player)

      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_update_email_instructions(
            %{player | email: email},
            player.email,
            url
          )
        end)

      %{player: player, token: token, email: email}
    end

    test "updates the email with a valid token", %{player: player, token: token, email: email} do
      assert Players.update_player_email(player, token) == :ok
      changed_player = Repo.get!(Player, player.id)
      assert changed_player.email != player.email
      assert changed_player.email == email
      assert changed_player.confirmed_at
      assert changed_player.confirmed_at != player.confirmed_at
      refute Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not update email with invalid token", %{player: player} do
      assert Players.update_player_email(player, "oops") == :error
      assert Repo.get!(Player, player.id).email == player.email
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not update email if player email changed", %{player: player, token: token} do
      assert Players.update_player_email(%{player | email: "current@example.com"}, token) ==
               :error

      assert Repo.get!(Player, player.id).email == player.email
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not update email if token expired", %{player: player, token: token} do
      {1, nil} = Repo.update_all(PlayerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Players.update_player_email(player, token) == :error
      assert Repo.get!(Player, player.id).email == player.email
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end
  end

  describe "change_player_password/2" do
    test "returns a player changeset" do
      assert %Ecto.Changeset{} = changeset = Players.change_player_password(%Player{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Players.change_player_password(%Player{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_player_password/3" do
    setup do
      %{player: insert(:player)}
    end

    test "validates password", %{player: player} do
      {:error, changeset} =
        Players.update_player_password(player, player.password, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{player: player} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Players.update_player_password(player, player.password, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{player: player} do
      %{password: valid_player_password} = params_for(:player)

      {:error, changeset} =
        Players.update_player_password(player, "invalid", %{password: valid_player_password})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{player: player} do
      player_password = player.password
      player = Map.put(player, :password, nil)

      {:ok, player} =
        Players.update_player_password(player, player_password, %{
          password: "new valid password"
        })

      assert is_nil(player.password)
      assert Players.get_player_by_email_and_password(player.email, "new valid password")
    end

    test "deletes all tokens for the given player", %{player: player} do
      _ = Players.generate_player_session_token(player)

      {:ok, _} =
        Players.update_player_password(player, player.password, %{
          password: "new valid password"
        })

      refute Repo.get_by(PlayerToken, player_id: player.id)
    end
  end

  describe "generate_player_session_token/1" do
    setup do
      %{player: insert(:player)}
    end

    test "generates a token", %{player: player} do
      token = Players.generate_player_session_token(player)
      assert player_token = Repo.get_by(PlayerToken, token: token)
      assert player_token.context == "session"

      # Creating the same token for another player should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%PlayerToken{
          token: player_token.token,
          player_id: insert(:player).id,
          context: "session"
        })
      end
    end
  end

  describe "get_player_by_session_token/1" do
    setup do
      player = insert(:player)
      token = Players.generate_player_session_token(player)
      %{player: player, token: token}
    end

    test "returns player by token", %{player: player, token: token} do
      assert session_player = Players.get_player_by_session_token(token)
      assert session_player.id == player.id
    end

    test "does not return player for invalid token" do
      refute Players.get_player_by_session_token("oops")
    end

    test "does not return player for expired token", %{token: token} do
      {1, nil} = Repo.update_all(PlayerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Players.get_player_by_session_token(token)
    end
  end

  describe "delete_player_session_token/1" do
    test "deletes the token" do
      player = insert(:player)
      token = Players.generate_player_session_token(player)
      assert Players.delete_player_session_token(token) == :ok
      refute Players.get_player_by_session_token(token)
    end
  end

  describe "deliver_player_confirmation_instructions/2" do
    setup do
      %{player: insert(:player)}
    end

    test "sends token through notification", %{player: player} do
      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_confirmation_instructions(player, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert player_token = Repo.get_by(PlayerToken, token: :crypto.hash(:sha256, token))
      assert player_token.player_id == player.id
      assert player_token.sent_to == player.email
      assert player_token.context == "confirm"
    end
  end

  describe "confirm_player/1" do
    setup do
      player = insert(:player)

      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_confirmation_instructions(player, url)
        end)

      %{player: player, token: token}
    end

    test "confirms the email with a valid token", %{player: player, token: token} do
      assert {:ok, confirmed_player} = Players.confirm_player(token)
      assert confirmed_player.confirmed_at
      assert confirmed_player.confirmed_at != player.confirmed_at
      assert Repo.get!(Player, player.id).confirmed_at
      refute Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not confirm with invalid token", %{player: player} do
      assert Players.confirm_player("oops") == :error
      refute Repo.get!(Player, player.id).confirmed_at
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not confirm email if token expired", %{player: player, token: token} do
      {1, nil} = Repo.update_all(PlayerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Players.confirm_player(token) == :error
      refute Repo.get!(Player, player.id).confirmed_at
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end
  end

  describe "deliver_player_reset_password_instructions/2" do
    setup do
      %{player: insert(:player)}
    end

    test "sends token through notification", %{player: player} do
      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_reset_password_instructions(player, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert player_token = Repo.get_by(PlayerToken, token: :crypto.hash(:sha256, token))
      assert player_token.player_id == player.id
      assert player_token.sent_to == player.email
      assert player_token.context == "reset_password"
    end
  end

  describe "get_player_by_reset_password_token/1" do
    setup do
      player = insert(:player)

      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_reset_password_instructions(player, url)
        end)

      %{player: player, token: token}
    end

    test "returns the player with valid token", %{player: %{id: id}, token: token} do
      assert %Player{id: ^id} = Players.get_player_by_reset_password_token(token)
      assert Repo.get_by(PlayerToken, player_id: id)
    end

    test "does not return the player with invalid token", %{player: player} do
      refute Players.get_player_by_reset_password_token("oops")
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end

    test "does not return the player if token expired", %{player: player, token: token} do
      {1, nil} = Repo.update_all(PlayerToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Players.get_player_by_reset_password_token(token)
      assert Repo.get_by(PlayerToken, player_id: player.id)
    end
  end

  describe "reset_player_password/2" do
    setup do
      %{player: insert(:player)}
    end

    test "validates password", %{player: player} do
      {:error, changeset} =
        Players.reset_player_password(player, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{player: player} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Players.reset_player_password(player, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{player: player} do
      # On tests, the player password is filled by convenience through the factory,
      # but we need to nilify it to properly test the password reset behavior.
      # This ensures we're testing the actual reset functionality rather than
      # just updating a player that already has a password set.
      player = Map.put(player, :password, nil)

      {:ok, updated_player} =
        Players.reset_player_password(player, %{password: "new valid password"})

      assert is_nil(updated_player.password)
      assert Players.get_player_by_email_and_password(player.email, "new valid password")
    end

    test "deletes all tokens for the given player", %{player: player} do
      _ = Players.generate_player_session_token(player)
      {:ok, _} = Players.reset_player_password(player, %{password: "new valid password"})
      refute Repo.get_by(PlayerToken, player_id: player.id)
    end
  end

  describe "inspect/2 for the Player module" do
    test "does not include password" do
      refute inspect(%Player{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
