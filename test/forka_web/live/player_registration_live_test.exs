defmodule ForkaWeb.PlayerRegistrationLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Registration page" do
    test "REQ-05: renders registration page in player shell with pt-BR copy", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/players/register")

      assert page_title(lv) =~ "Criar conta"
      assert has_element?(lv, "#registration-card")
      assert has_element?(lv, "#registration_form")
      assert html =~ "Criar conta"
      assert html =~ "Entrar"
      assert html =~ "Nome de usuário"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_player(insert(:player))
        |> live(~p"/players/register")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test "REQ-05: renders accessible pt-BR validation errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          player: %{
            "email" => "with spaces",
            "username" => "bad user!",
            "password" => "too short"
          }
        )

      refute has_element?(lv, ~s|#registration_form [role="alert"]|)

      assert has_element?(
               lv,
               ~s|input#player_email[aria-invalid="true"][aria-describedby="player_email-feedback"]|
             )

      assert result =~ "Criar conta"
      assert result =~ "deve conter @ e não ter espaços"
      assert result =~ "use apenas letras, números e underline (_)"
      assert result =~ "deve ter no mínimo 12 caracteres"
    end
  end

  describe "register player" do
    test "creates account and logs the player in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/register")

      %{email: email} = player_params = player_registration_params()
      form = form(lv, "#registration_form", player: player_params)
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ email
      assert response =~ "Minha conta"
      assert response =~ "Sair"
    end

    test "REQ-05: renders scoped alert and pt-BR error for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/register")

      player = insert(:player, email: "test@email.com")

      result =
        lv
        |> form("#registration_form",
          player: %{"email" => player.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert has_element?(
               lv,
               ~s|#registration_form [role="alert"]|,
               "Revise os campos abaixo para continuar."
             )

      assert result =~ "já está em uso"
    end

    test "REQ-05: keeps reserved alert region mounted across empty, failed submit, and valid live edit",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/register")

      assert has_element?(lv, "#registration_form-alert")
      refute has_element?(lv, "#registration_form-alert[role]")
      refute has_element?(lv, ~s|#registration_form-alert [role="alert"]|)

      player = insert(:player)

      lv
      |> form("#registration_form",
        player: %{"email" => player.email, "password" => "valid_password"}
      )
      |> render_submit()

      assert has_element?(
               lv,
               ~s|#registration_form-alert [role="alert"]|,
               "Revise os campos abaixo para continuar."
             )

      lv
      |> element("#registration_form")
      |> render_change(player: player_registration_params())

      assert has_element?(lv, "#registration_form-alert")
      refute has_element?(lv, ~s|#registration_form-alert [role="alert"]|)
    end
  end

  describe "registration navigation" do
    test "redirects to login page when Entrar link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Entrar")
        |> render_click()
        |> follow_redirect(conn, ~p"/players/log_in")

      assert login_html =~ "Entrar na sua conta"
    end
  end
end
