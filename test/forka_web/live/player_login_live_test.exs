defmodule ForkaWeb.PlayerLoginLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Log in page" do
    test "REQ-04: renders log in page in player shell with pt-BR copy", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/players/log_in")

      assert page_title(lv) =~ "Entrar"
      assert has_element?(lv, "#login-card")
      assert has_element?(lv, "#login_form")
      assert html =~ "Entrar na sua conta"
      assert html =~ "Criar conta"
      assert html =~ "Esqueceu a senha?"
      assert html =~ "E-mail ou nome de usuário"
      assert html =~ "Manter sessão conectada"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_player(insert(:player))
        |> live(~p"/players/log_in")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end
  end

  describe "player login" do
    test "redirects if player login using email with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      player = insert(:player, password: password)

      {:ok, lv, _html} = live(conn, ~p"/players/log_in")

      form =
        form(lv, "#login_form",
          player: %{email_or_username: player.email, password: password, remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects if player login using username with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      player = insert(:player, password: password)

      {:ok, lv, _html} = live(conn, ~p"/players/log_in")

      form =
        form(lv, "#login_form",
          player: %{email_or_username: player.username, password: password, remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "REQ-04: redirects to login page with localized flash error and preserves identifier on invalid credentials",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/log_in")

      form =
        form(lv, "#login_form",
          player: %{email_or_username: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "E-mail, usuário ou senha inválidos."

      assert redirected_to(conn) == ~p"/players/log_in"

      {:ok, lv, _html} = live(conn, ~p"/players/log_in")
      assert has_element?(lv, "#flash-error", "Erro!")
      assert has_element?(lv, "#flash-error", "E-mail, usuário ou senha inválidos.")
      assert has_element?(lv, ~s|#flash-error button[aria-label="fechar"]|)
      assert has_element?(lv, ~s|input[name="player[email_or_username]"][value="test@email.com"]|)
    end
  end

  describe "login navigation" do
    test "redirects to registration page when Criar conta link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/log_in")

      {:ok, register_live, _register_html} =
        lv
        |> element("main a", "Criar conta")
        |> render_click()
        |> follow_redirect(conn, ~p"/players/register")

      assert has_element?(register_live, "#registration_form")
    end

    test "redirects to forgot password page when Esqueceu a senha? link is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/players/log_in")

      {:ok, forgot_live, _forgot_html} =
        lv
        |> element("main a", "Esqueceu a senha?")
        |> render_click()
        |> follow_redirect(conn, ~p"/players/reset_password")

      assert has_element?(forgot_live, "#reset_password_form")
    end

    test "REQ-02: carries safe return_to to login form action and register link, ignoring unsafe values",
         %{
           conn: conn
         } do
      return_to = "/rooms/#{Ecto.UUID.generate()}/join"
      {:ok, lv, _html} = live(conn, ~p"/players/log_in?return_to=#{return_to}")

      assert has_element?(
               lv,
               ~s|a[href="/players/register?return_to=#{URI.encode_www_form(return_to)}"]|
             )

      assert has_element?(
               lv,
               ~s|form#login_form[action="/players/log_in?return_to=#{URI.encode_www_form(return_to)}"]|
             )

      {:ok, lv_unsafe, _html} = live(conn, ~p"/players/log_in?return_to=//evil.com")
      assert has_element?(lv_unsafe, ~s|a[href="/players/register"]|)
      assert has_element?(lv_unsafe, ~s|form#login_form[action="/players/log_in"]|)
    end
  end
end
