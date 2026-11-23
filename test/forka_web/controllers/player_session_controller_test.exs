defmodule ForkaWeb.PlayerSessionControllerTest do
  use ForkaWeb.ConnCase, async: true

  setup do
    %{player: insert(:player)}
  end

  describe "POST /players/log_in" do
    test "logs the player in", %{conn: conn, player: player} do
      conn =
        post(conn, ~p"/players/log_in", %{
          "player" => %{"email" => player.email, "password" => player.password}
        })

      assert get_session(conn, :player_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ player.email
      assert response =~ ~p"/players/settings"
      assert response =~ ~p"/players/log_out"
    end

    test "logs the player in with remember me", %{conn: conn, player: player} do
      conn =
        post(conn, ~p"/players/log_in", %{
          "player" => %{
            "email" => player.email,
            "password" => player.password,
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_forka_web_player_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the player in with return to", %{conn: conn, player: player} do
      conn =
        conn
        |> init_test_session(player_return_to: "/foo/bar")
        |> post(~p"/players/log_in", %{
          "player" => %{
            "email" => player.email,
            "password" => player.password
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Bem-vindo de volta!"
    end

    test "login following registration", %{conn: conn, player: player} do
      conn =
        conn
        |> post(~p"/players/log_in", %{
          "_action" => "registered",
          "player" => %{
            "email" => player.email,
            "password" => player.password
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Conta criada com sucesso!"
    end

    test "login following password update", %{conn: conn, player: player} do
      conn =
        conn
        |> post(~p"/players/log_in", %{
          "_action" => "password_updated",
          "player" => %{
            "email" => player.email,
            "password" => player.password
          }
        })

      assert redirected_to(conn) == ~p"/players/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Senha atualizada com sucesso!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/players/log_in", %{
          "player" => %{"email" => "invalid@email.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "E-mail, usuário ou senha inválidos."

      assert redirected_to(conn) == ~p"/players/log_in"
    end

    test "REQ-02: preserves email_or_username in flash after invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/players/log_in", %{
          "player" => %{"email_or_username" => "lia_jogadora", "password" => "wrong_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "E-mail, usuário ou senha inválidos."

      assert Phoenix.Flash.get(conn.assigns.flash, :email_or_username) == "lia_jogadora"
      assert redirected_to(conn) == ~p"/players/log_in"
    end
  end

  describe "DELETE /players/log_out" do
    test "logs the player out", %{conn: conn, player: player} do
      conn = conn |> log_in_player(player) |> delete(~p"/players/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :player_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Você saiu da conta."

      home_doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
      info_flash = LazyHTML.query(home_doc, "#flash-info")
      assert LazyHTML.text(info_flash) =~ "Sucesso!"
      assert LazyHTML.text(info_flash) =~ "Você saiu da conta."
      assert LazyHTML.attribute(LazyHTML.query(info_flash, "button"), "aria-label") == ["fechar"]
    end

    test "succeeds even if the player is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/players/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :player_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Você saiu da conta."
    end
  end
end
