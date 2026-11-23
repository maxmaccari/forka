defmodule ForkaWeb.PlayerResetPasswordLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Forka.TestHelpers

  alias Forka.Players

  setup do
    player = insert(:player)

    token =
      extract_token_from_email(fn url ->
        Players.deliver_player_reset_password_instructions(player, url)
      end)

    %{token: token, player: player}
  end

  describe "Reset password page" do
    test "REQ-07: renders reset password page in player shell with pt-BR copy", %{
      conn: conn,
      token: token
    } do
      {:ok, lv, html} = live(conn, ~p"/players/reset_password/#{token}")

      assert page_title(lv) =~ "Redefinir senha"
      assert has_element?(lv, "#reset-password-card")
      assert has_element?(lv, "#reset_password_form")
      refute has_element?(lv, ~s|#reset_password_form [role="alert"]|)
      assert html =~ "Redefinir senha"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      {:error, {:redirect, to}} = live(conn, ~p"/players/reset_password/invalid")

      assert to == %{
               flash: %{"error" => "O link para redefinir a senha é inválido ou expirou."},
               to: ~p"/"
             }
    end

    test "REQ-07: does not show form alert or untouched confirmation error while typing password",
         %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      result =
        lv
        |> element("#reset_password_form")
        |> render_change(%{
          "_target" => ["player", "password"],
          "player" => %{
            "password" => "new valid password",
            "password_confirmation" => "",
            "_unused_password_confirmation" => ""
          }
        })

      refute has_element?(lv, ~s|#reset_password_form [role="alert"]|)
      refute result =~ "não confere com a senha"
    end

    test "REQ-07: renders pt-BR field validation errors without form alert during live validation",
         %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      result =
        lv
        |> element("#reset_password_form")
        |> render_change(
          player: %{"password" => "secret12", "password_confirmation" => "secret123456"}
        )

      refute has_element?(lv, ~s|#reset_password_form [role="alert"]|)

      assert has_element?(
               lv,
               ~s|input#player_password[aria-invalid="true"][aria-describedby="player_password-feedback"]|
             )

      assert result =~ "deve ter no mínimo 12 caracteres"
      assert result =~ "não confere com a senha"
    end
  end

  describe "Reset Password" do
    test "resets password once", %{conn: conn, token: token, player: player} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          player: %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/players/log_in")

      refute get_session(conn, :player_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Senha redefinida com sucesso!"
      assert Players.get_player_by_email_and_password(player.email, "new valid password")
    end

    test "REQ-07: shows scoped form alert and pt-BR errors on invalid submit", %{
      conn: conn,
      token: token
    } do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          player: %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        )
        |> render_submit()

      assert has_element?(
               lv,
               ~s|#reset_password_form [role="alert"]|,
               "Revise os campos abaixo para continuar."
             )

      assert result =~ "Redefinir senha"
      assert result =~ "deve ter no mínimo 12 caracteres"
      assert result =~ "não confere com a senha"
    end

    test "REQ-07: keeps reserved alert region mounted across empty, failed submit, and valid live edit",
         %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      assert has_element?(lv, "#reset_password_form-alert")
      refute has_element?(lv, "#reset_password_form-alert[role]")
      refute has_element?(lv, ~s|#reset_password_form-alert [role="alert"]|)

      lv
      |> form("#reset_password_form",
        player: %{
          "password" => "too short",
          "password_confirmation" => "does not match"
        }
      )
      |> render_submit()

      assert has_element?(
               lv,
               ~s|#reset_password_form-alert [role="alert"]|,
               "Revise os campos abaixo para continuar."
             )

      lv
      |> element("#reset_password_form")
      |> render_change(
        player: %{
          "password" => "new valid password",
          "password_confirmation" => "new valid password"
        }
      )

      assert has_element?(lv, "#reset_password_form-alert")
      refute has_element?(lv, ~s|#reset_password_form-alert [role="alert"]|)
    end
  end

  describe "Reset password navigation" do
    test "redirects to login page when Entrar link is clicked", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Entrar")
        |> render_click()
        |> follow_redirect(conn, ~p"/players/log_in")

      assert login_html =~ "Entrar na sua conta"
    end

    test "redirects to registration page when Criar conta link is clicked", %{
      conn: conn,
      token: token
    } do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password/#{token}")

      {:ok, _register_live, register_html} =
        lv
        |> element("main a", "Criar conta")
        |> render_click()
        |> follow_redirect(conn, ~p"/players/register")

      assert register_html =~ "Criar conta"
    end
  end
end
