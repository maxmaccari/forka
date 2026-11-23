defmodule ForkaWeb.PlayerForgotPasswordLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Forka.Players
  alias Forka.Repo

  describe "Forgot password page" do
    test "REQ-07: renders forgot password page in player shell with accessible label and pt-BR copy",
         %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/players/reset_password")

      assert page_title(lv) =~ "Recuperar senha"
      assert has_element?(lv, "#forgot-password-card")
      assert has_element?(lv, "#reset_password_form")
      assert has_element?(lv, "label", "E-mail")
      assert html =~ "Esqueceu a senha?"
      assert has_element?(lv, ~s|a[href="#{~p"/players/register"}"]|, "Criar conta")
      assert has_element?(lv, ~s|a[href="#{~p"/players/log_in"}"]|, "Entrar")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_player(insert(:player))
        |> live(~p"/players/reset_password")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{player: insert(:player)}
    end

    test "sends a new reset password token", %{conn: conn, player: player} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", player: %{"email" => player.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Se este e-mail estiver cadastrado, você receberá as instruções para redefinir sua senha em instantes."

      assert Repo.get_by!(Players.PlayerToken, player_id: player.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", player: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Se este e-mail estiver cadastrado, você receberá as instruções para redefinir sua senha em instantes."

      assert Repo.all(Players.PlayerToken) == []
    end
  end
end
