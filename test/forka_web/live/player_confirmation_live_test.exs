defmodule ForkaWeb.PlayerConfirmationLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Forka.TestHelpers

  alias Forka.Players
  alias Forka.Repo

  setup do
    %{player: insert(:player)}
  end

  describe "Confirm player" do
    test "REQ-06: renders confirmation page in player shell with pt-BR copy", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/players/confirm/some-token")

      assert page_title(lv) =~ "Confirmar conta"
      assert has_element?(lv, "#confirmation-card")
      assert has_element?(lv, "#confirmation_form")
      assert html =~ "Confirmar conta"
      assert html =~ "Criar conta"
      assert html =~ "Entrar"
    end

    test "confirms the given token once", %{conn: conn, player: player} do
      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_confirmation_instructions(player, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/players/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Conta confirmada com sucesso!"

      assert Players.get_player!(player.id).confirmed_at
      refute get_session(conn, :player_token)
      assert Repo.all(Players.PlayerToken) == []

      # when not logged in
      {:ok, lv, _html} = live(conn, ~p"/players/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "O link de confirmação é inválido ou expirou."

      # when logged in
      conn =
        build_conn()
        |> log_in_player(player)

      {:ok, lv, _html} = live(conn, ~p"/players/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, player: player} do
      {:ok, lv, _html} = live(conn, ~p"/players/confirm/invalid-token")

      {:ok, conn} =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "O link de confirmação é inválido ou expirou."

      refute Players.get_player!(player.id).confirmed_at
    end

    test "REQ-02: redirects to safe return_to after confirmation and ignores unsafe return_to", %{
      conn: conn,
      player: player
    } do
      return_to = "/rooms/#{Ecto.UUID.generate()}/join"

      token =
        extract_token_from_email(fn url ->
          Players.deliver_player_confirmation_instructions(player, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/players/confirm/#{token}?return_to=#{return_to}")

      {:ok, conn} =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, return_to)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Conta confirmada com sucesso!"

      other_player = insert(:player)

      other_token =
        extract_token_from_email(fn url ->
          Players.deliver_player_confirmation_instructions(other_player, url)
        end)

      {:ok, lv_unsafe, _html} =
        live(conn, ~p"/players/confirm/#{other_token}?#{[return_to: "/rooms/foo\\bar"]}")

      {:ok, unsafe_conn} =
        lv_unsafe
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(unsafe_conn.assigns.flash, :info) ==
               "Conta confirmada com sucesso!"
    end
  end
end
