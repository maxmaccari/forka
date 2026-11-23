defmodule ForkaWeb.PlayerConfirmationInstructionsLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Forka.Players
  alias Forka.Repo

  setup do
    %{player: insert(:player)}
  end

  describe "Resend confirmation" do
    test "REQ-06: renders resend confirmation page in player shell with accessible label and pt-BR copy",
         %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/players/confirm")

      assert page_title(lv) =~ "Reenviar confirmação"
      assert has_element?(lv, "#resend-confirmation-card")
      assert has_element?(lv, "#resend_confirmation_form")
      assert has_element?(lv, "label", "E-mail")
      assert html =~ "Reenviar instruções de confirmação"
      assert html =~ "Criar conta"
      assert html =~ "Entrar"
    end

    test "sends a new confirmation token", %{conn: conn, player: player} do
      {:ok, lv, _html} = live(conn, ~p"/players/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", player: %{email: player.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Se este e-mail estiver cadastrado e ainda não confirmado, você receberá as instruções em instantes."

      assert Repo.get_by!(Players.PlayerToken, player_id: player.id).context == "confirm"
    end

    test "does not send confirmation token if player is confirmed", %{conn: conn, player: player} do
      Repo.update!(Players.Player.confirm_changeset(player))

      {:ok, lv, _html} = live(conn, ~p"/players/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", player: %{email: player.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Se este e-mail estiver cadastrado e ainda não confirmado, você receberá as instruções em instantes."

      refute Repo.get_by(Players.PlayerToken, player_id: player.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/players/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", player: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Se este e-mail estiver cadastrado e ainda não confirmado, você receberá as instruções em instantes."

      assert Repo.all(Players.PlayerToken) == []
    end
  end
end
