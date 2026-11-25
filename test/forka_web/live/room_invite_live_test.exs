defmodule ForkaWeb.RoomInviteLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games

  describe "GET /rooms/:id/join" do
    test "REQ-01: renders room details and sign-in/register links with return_to for unauthenticated guests",
         %{
           conn: conn
         } do
      owner = insert(:player, username: "bia")
      cat = insert(:category, name: "Frutas", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Roda de Sexta",
          max_players: 5,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      {:ok, lv, html} = live(conn, ~p"/rooms/#{game.id}/join")
      text = visible_text(html)

      assert page_title(lv) =~ "Roda de Sexta"
      assert has_element?(lv, "#room-invite-card")
      assert text =~ "Roda de Sexta"
      assert text =~ "1/5 jogadores"
      assert text =~ "Português"
      assert text =~ "Frutas"
      assert text =~ "bia"

      encoded = URI.encode_www_form("/rooms/#{game.id}/join")
      assert has_element?(lv, ~s|#invite-login-link[href="/players/log_in?return_to=#{encoded}"]|)

      assert has_element?(
               lv,
               ~s|#invite-register-link[href="/players/register?return_to=#{encoded}"]|
             )
    end

    test "REQ-01 & REQ-05: authenticated new player previews without mutating on GET, then joins via protected action",
         %{
           conn: conn
         } do
      owner = insert(:player)
      joiner = insert(:player, username: "carlos")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Aberta", max_players: 4})

      {:ok, lv, _html} =
        conn |> log_in_player(joiner) |> live(~p"/rooms/#{game.id}/join")

      assert has_element?(lv, "#room-invite-card")
      assert has_element?(lv, "#invite-join-button")

      before_summary = Games.get_game_summary(game.id)
      refute Enum.any?(before_summary.players, fn {_pos, gp} -> gp.player.id == joiner.id end)

      lv |> element("#invite-join-button") |> render_click()
      assert_redirect(lv, ~p"/rooms/#{game.id}")

      after_summary = Games.get_game_summary(game.id)
      assert Enum.any?(after_summary.players, fn {_pos, gp} -> gp.player.id == joiner.id end)
    end

    test "REQ-05: returning participant in playing match redirects back to /rooms/:id", %{
      conn: conn
    } do
      owner = insert(:player)
      p2 = insert(:player)
      insert(:word)
      {:ok, game} = Games.create_game(owner.id, %{name: "Em Jogo", max_players: 2})
      :ok = Games.join_game(game.id, p2.id)
      :ok = Games.start_game(game.id)

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               conn |> log_in_player(p2) |> live(~p"/rooms/#{game.id}/join")

      assert redirect_to == "/rooms/#{game.id}"
    end

    test "REQ-03: renders full, in-progress, missing, and archived states with room-list fallback link",
         %{
           conn: conn
         } do
      owner = insert(:player)
      p2 = insert(:player)
      outsider = insert(:player)
      insert(:word)

      {:ok, full_game} = Games.create_game(owner.id, %{name: "Sala Cheia", max_players: 2})
      :ok = Games.join_game(full_game.id, p2.id)

      {:ok, lv_full, html_full} =
        conn |> log_in_player(outsider) |> live(~p"/rooms/#{full_game.id}/join")

      assert visible_text(html_full) =~ "Sala cheia"
      assert has_element?(lv_full, ~s|#invite-directory-link[href="/"]|)

      :ok = Games.start_game(full_game.id)

      {:ok, lv_playing, html_playing} =
        conn |> log_in_player(outsider) |> live(~p"/rooms/#{full_game.id}/join")

      assert visible_text(html_playing) =~ "Partida em andamento"
      assert has_element?(lv_playing, ~s|#invite-directory-link[href="/"]|)

      {:ok, lv_missing, html_missing} = live(conn, ~p"/rooms/#{Ecto.UUID.generate()}/join")
      assert visible_text(html_missing) =~ "Sala não encontrada"
      assert has_element?(lv_missing, ~s|#invite-directory-link[href="/"]|)

      archived = insert(:game, status: :archived)
      {:ok, lv_archived, html_archived} = live(conn, ~p"/rooms/#{archived.id}/join")
      assert visible_text(html_archived) =~ "Esta sala foi arquivada"
      assert has_element?(lv_archived, ~s|#invite-directory-link[href="/"]|)
      refute has_element?(lv_archived, "#invite-login-link")
    end

    test "REQ-03 & REQ-05: guest viewing full or playing room keeps sign-in link with return_to for returning participants",
         %{conn: conn} do
      owner = insert(:player)
      p2 = insert(:player)
      insert(:word)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Cheia", max_players: 2})
      :ok = Games.join_game(game.id, p2.id)

      encoded = URI.encode_www_form("/rooms/#{game.id}/join")
      {:ok, lv_full, _html} = live(conn, ~p"/rooms/#{game.id}/join")

      assert has_element?(
               lv_full,
               ~s|#invite-login-link[href="/players/log_in?return_to=#{encoded}"]|
             )

      assert has_element?(lv_full, ~s|#invite-directory-link[href="/"]|)

      :ok = Games.start_game(game.id)
      {:ok, lv_playing, _html} = live(conn, ~p"/rooms/#{game.id}/join")

      assert has_element?(
               lv_playing,
               ~s|#invite-login-link[href="/players/log_in?return_to=#{encoded}"]|
             )

      assert has_element?(lv_playing, ~s|#invite-directory-link[href="/"]|)
    end
  end
end
