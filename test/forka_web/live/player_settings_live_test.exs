defmodule ForkaWeb.PlayerSettingsLiveTest do
  use ForkaWeb.ConnCase, async: true

  alias Forka.Players
  import Phoenix.LiveViewTest
  import Forka.TestHelpers

  describe "Settings page" do
    test "REQ-08: renders settings page in player shell with pt-BR copy and logout action", %{
      conn: conn
    } do
      {:ok, lv, html} =
        conn
        |> log_in_player(insert(:player))
        |> live(~p"/players/settings")

      assert page_title(lv) =~ "Minha conta"
      assert has_element?(lv, ~s|a[href="#{~p"/"}"][aria-label="Voltar para o início"]|)
      assert has_element?(lv, "#email-settings-card")
      assert has_element?(lv, "#password-settings-card")
      assert has_element?(lv, "#session-settings-card")

      assert has_element?(
               lv,
               ~s|#session-settings-card a[href="#{~p"/players/log_out"}"][data-method="delete"]|,
               "Sair da conta"
             )

      assert html =~ "Alterar e-mail"
      assert html =~ "Alterar senha"
    end

    test "redirects if player is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/players/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/players/log_in"
      assert %{"error" => "Você precisa entrar para acessar esta página."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      player = insert(:player)
      %{conn: log_in_player(conn, player), player: player, password: player.password}
    end

    test "updates the player email", %{conn: conn, password: password, player: player} do
      %{email: new_email} = params_for(:player)

      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => password,
          "player" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "Enviamos um link de confirmação para o novo e-mail."
      assert Players.get_player_by_email(player.email)
    end

    test "renders accessible pt-BR errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "current_password" => "invalid",
          "player" => %{"email" => "with spaces"}
        })

      assert has_element?(
               lv,
               ~s|input#player_email[aria-invalid="true"][aria-describedby="player_email-feedback"]|
             )

      assert result =~ "Alterar e-mail"
      assert result =~ "deve conter @ e não ter espaços"
    end

    test "renders pt-BR errors with invalid data (phx-submit)", %{conn: conn, player: player} do
      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => "invalid",
          "player" => %{"email" => player.email}
        })
        |> render_submit()

      assert result =~ "Alterar e-mail"
      assert result =~ "não foi alterado"
      assert result =~ "não é válida"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      player = insert(:player)
      %{conn: log_in_player(conn, player), player: player, password: player.password}
    end

    test "updates the player password", %{conn: conn, player: player, password: password} do
      %{password: new_password} = params_for(:player)

      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      form =
        form(lv, "#password_form", %{
          "current_password" => password,
          "player" => %{
            "email" => player.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/players/settings"

      assert get_session(new_password_conn, :player_token) != get_session(conn, :player_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) ==
               "Senha atualizada com sucesso!"

      assert Players.get_player_by_email_and_password(player.email, new_password)
    end

    test "renders pt-BR errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "current_password" => "invalid",
          "player" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Alterar senha"
      assert result =~ "deve ter no mínimo 12 caracteres"
      assert result =~ "não confere com a senha"
    end

    test "renders pt-BR errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/settings")

      result =
        lv
        |> form("#password_form", %{
          "current_password" => "invalid",
          "player" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Alterar senha"
      assert result =~ "deve ter no mínimo 12 caracteres"
      assert result =~ "não confere com a senha"
      assert result =~ "não é válida"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
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

      %{conn: log_in_player(conn, player), token: token, email: email, player: player}
    end

    test "updates the player email once", %{
      conn: conn,
      player: player,
      token: token,
      email: email
    } do
      {:error, redirect} = live(conn, ~p"/players/settings/confirm_email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/players/settings"
      assert %{"info" => message} = flash
      assert message == "E-mail alterado com sucesso!"
      refute Players.get_player_by_email(player.email)
      assert Players.get_player_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/players/settings/confirm_email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/players/settings"
      assert %{"error" => message} = flash
      assert message == "O link de alteração de e-mail é inválido ou expirou."
    end

    test "does not update email with invalid token", %{conn: conn, player: player} do
      {:error, redirect} = live(conn, ~p"/players/settings/confirm_email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/players/settings"
      assert %{"error" => message} = flash
      assert message == "O link de alteração de e-mail é inválido ou expirou."
      assert Players.get_player_by_email(player.email)
    end

    test "redirects if player is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/players/settings/confirm_email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/players/log_in"
      assert %{"error" => message} = flash
      assert message == "Você precisa entrar para acessar esta página."
    end
  end
end
