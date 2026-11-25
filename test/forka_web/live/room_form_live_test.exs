defmodule ForkaWeb.RoomFormLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games
  alias Forka.Games.GameServer

  describe "GET /salas/nova (:new)" do
    test "AC-06: redirects unauthenticated visitor to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/players/log_in"}}} = live(conn, ~p"/salas/nova")
    end

    test "AC-06: renders defaults (PT, 4 players, all categories), switches language, and creates a room",
         %{conn: conn} do
      player = insert(:player, username: "lia")
      pt_animals = insert(:category, name: "Animais", language: "pt")
      pt_music = insert(:category, name: "Música", language: "pt")
      en_movies = insert(:category, name: "Movies", language: "en")

      conn = log_in_player(conn, player)
      {:ok, lv, html} = live(conn, ~p"/salas/nova")

      assert page_title(lv) =~ "Criar sala"
      assert has_element?(lv, "#room-form")
      assert has_element?(lv, ~s|#room-max-players button[aria-checked="true"]|, "4")
      assert has_element?(lv, ~s|#room-language button[aria-checked="true"]|, "Português")
      assert has_element?(lv, "#category-chip-all[aria-pressed='true']")
      assert html =~ "Animais"
      assert html =~ "Música"
      refute html =~ "Movies"

      # Select a PT category, then switch to EN: PT selection clears and EN categories appear
      lv |> element("#category-chip-#{pt_animals.id}") |> render_click()
      assert has_element?(lv, "#category-chip-#{pt_animals.id}[aria-pressed='true']")
      assert has_element?(lv, "#category-chip-all[aria-pressed='false']")

      lv |> element(~s|#room-language button[phx-value-value="en"]|) |> render_click()
      assert has_element?(lv, ~s|#room-language button[aria-checked="true"]|, "Inglês")
      assert has_element?(lv, "#category-chip-all[aria-pressed='true']")
      assert has_element?(lv, "#category-chip-#{en_movies.id}")
      refute has_element?(lv, "#category-chip-#{pt_animals.id}")

      # Switch back to PT, pick Música, set capacity 6, enter name, and submit
      lv |> element(~s|#room-language button[phx-value-value="pt"]|) |> render_click()
      lv |> element("#category-chip-#{pt_music.id}") |> render_click()
      lv |> element(~s|#room-max-players button[phx-value-value="6"]|) |> render_click()

      {:ok, lobby_lv, lobby_html} =
        lv
        |> form("#room-form", room_settings: %{name: "Turma de Sexta"})
        |> render_submit()
        |> follow_redirect(conn)

      assert lobby_lv.module == ForkaWeb.RoomLive
      text = visible_text(lobby_html)
      assert text =~ "Turma de Sexta"
      assert text =~ "1/6 jogadores"
      assert text =~ "Música"
    end
  end

  describe "GET /salas/:id/configuracoes (:edit)" do
    test "AC-07: prefills existing lobby settings, updates them, and returns to the lobby", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      pt_cat = insert(:category, name: "Filmes", language: "pt")
      en_cat = insert(:category, name: "Science", language: "en")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Original",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [pt_cat.id]}
        })

      conn = log_in_player(conn, owner)
      {:ok, lv, _html} = live(conn, ~p"/salas/#{game.id}/configuracoes")

      assert page_title(lv) =~ "Configurações da sala"
      assert has_element?(lv, ~s|#room-name[value="Sala Original"]|)
      assert has_element?(lv, ~s|#room-max-players button[aria-checked="true"]|, "4")
      assert has_element?(lv, ~s|#room-language button[aria-checked="true"]|, "Português")
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")

      lv |> element(~s|#room-language button[phx-value-value="en"]|) |> render_click()
      lv |> element("#category-chip-#{en_cat.id}") |> render_click()
      lv |> element(~s|#room-max-players button[phx-value-value="5"]|) |> render_click()

      {:ok, lobby_lv, lobby_html} =
        lv
        |> form("#room-form", room_settings: %{name: "Sala Atualizada"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/salas/#{game.id}")

      assert lobby_lv.module == ForkaWeb.RoomLive
      text = visible_text(lobby_html)
      assert text =~ "Sala Atualizada"
      assert text =~ "1/5 jogadores"
      assert text =~ "Inglês"
      assert text =~ "Science"
    end

    test "AC-08: blocks non-owner from mounting edit form and redirects to lobby", %{conn: conn} do
      owner = insert(:player)
      other = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala da Lia", max_players: 4})

      assert {:error,
              {:live_redirect,
               %{
                 to: "/salas/" <> _,
                 flash: %{"error" => "Apenas quem criou a sala pode editar as configurações."}
               }}} =
               conn |> log_in_player(other) |> live(~p"/salas/#{game.id}/configuracoes")
    end

    test "AC-08: blocks editing once the game is no longer in lobby", %{conn: conn} do
      owner = insert(:player)
      guest = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Em jogo", max_players: 4})
      :ok = Games.join_game(game.id, guest.id)
      insert(:word, text: "forka")
      :ok = Games.start_game(game.id)

      assert {:error,
              {:live_redirect,
               %{
                 to: "/salas/" <> _,
                 flash: %{
                   "error" => "As configurações só podem ser alteradas antes da partida começar."
                 }
               }}} =
               conn |> log_in_player(owner) |> live(~p"/salas/#{game.id}/configuracoes")
    end

    test "AC-08: redirects with flash if room starts or ownership transfers before submit", %{
      conn: conn
    } do
      owner = insert(:player)
      guest = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Corrida", max_players: 4})
      :ok = Games.join_game(game.id, guest.id)

      conn = log_in_player(conn, owner)
      {:ok, lv, _html} = live(conn, ~p"/salas/#{game.id}/configuracoes")

      :ok = Games.transfer_ownership(game.id, guest.id)

      {:ok, lobby_lv, lobby_html} =
        lv
        |> form("#room-form", room_settings: %{name: "Tarde demais"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/salas/#{game.id}")

      assert lobby_lv.module == ForkaWeb.RoomLive
      assert lobby_html =~ "Apenas quem criou a sala pode editar as configurações."
    end

    test "AC-08: redirects to directory when reopening or submitting edit on an archived room", %{
      conn: conn
    } do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Arquivada", max_players: 4})

      conn = log_in_player(conn, owner)
      {:ok, lv, _html} = live(conn, ~p"/salas/#{game.id}/configuracoes")

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      :ok = Games.archive_game(game.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      {:ok, _dir_lv, dir_html} =
        lv
        |> form("#room-form", room_settings: %{name: "Após arquivar"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert dir_html =~ "Esta sala foi arquivada."

      assert {:error,
              {:live_redirect, %{to: "/", flash: %{"error" => "Esta sala foi arquivada."}}}} =
               live(conn, ~p"/salas/#{game.id}/configuracoes")
    end
  end

  describe "validation errors, stale selections, and capacity below occupancy" do
    test "AC-09: preserves entered values when create submit fails server-side validation", %{
      conn: conn
    } do
      player = insert(:player)
      pt_cat = insert(:category, name: "Jogos", language: "pt")

      conn = log_in_player(conn, player)
      {:ok, lv, _html} = live(conn, ~p"/salas/nova")

      lv |> element(~s|#room-max-players button[phx-value-value="5"]|) |> render_click()
      lv |> element("#category-chip-#{pt_cat.id}") |> render_click()

      html =
        lv
        |> form("#room-form", room_settings: %{name: "   "})
        |> render_submit()

      assert html =~ "não pode ficar em branco"
      assert has_element?(lv, ~s|#room-max-players button[aria-checked="true"]|, "5")
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")
    end

    test "EDGE-02: rejects deleted/stale category on submit, preserves form inputs, and refreshes category chips",
         %{conn: conn} do
      player = insert(:player)
      keep_cat = insert(:category, name: "Animais", language: "pt")
      deleted_cat = insert(:category, name: "Temporária", language: "pt")

      conn = log_in_player(conn, player)
      {:ok, lv, _html} = live(conn, ~p"/salas/nova")

      lv |> element(~s|#room-max-players button[phx-value-value="5"]|) |> render_click()
      lv |> element("#category-chip-#{keep_cat.id}") |> render_click()
      lv |> element("#category-chip-#{deleted_cat.id}") |> render_click()

      # Category is deleted before the user submits
      Forka.Repo.delete!(deleted_cat)

      html =
        lv
        |> form("#room-form", room_settings: %{name: "Sala Persistente"})
        |> render_submit()

      assert has_element?(lv, "#room-categories-error")
      assert html =~ "contém categorias indisponíveis para o idioma selecionado"
      assert has_element?(lv, ~s|#room-name[value="Sala Persistente"]|)
      assert has_element?(lv, ~s|#room-max-players button[aria-checked="true"]|, "5")
      # Stale chip removed, valid selection preserved so user can resubmit cleanly
      refute has_element?(lv, "#category-chip-#{deleted_cat.id}")
      assert has_element?(lv, "#category-chip-#{keep_cat.id}[aria-pressed='true']")

      {:ok, lobby_lv, lobby_html} =
        lv
        |> form("#room-form", room_settings: %{name: "Sala Persistente"})
        |> render_submit()
        |> follow_redirect(conn)

      assert lobby_lv.module == ForkaWeb.RoomLive
      assert visible_text(lobby_html) =~ "Sala Persistente"
      assert visible_text(lobby_html) =~ "Animais"
    end

    test "EDGE-01: rejects lowering capacity below current occupancy on edit while preserving entered name",
         %{conn: conn} do
      owner = insert(:player)
      p2 = insert(:player)
      p3 = insert(:player)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Cheia", max_players: 4})
      :ok = Games.join_game(game.id, p2.id)
      :ok = Games.join_game(game.id, p3.id)

      conn = log_in_player(conn, owner)
      {:ok, lv, _html} = live(conn, ~p"/salas/#{game.id}/configuracoes")

      lv |> element(~s|#room-max-players button[phx-value-value="2"]|) |> render_click()

      html =
        lv
        |> form("#room-form", room_settings: %{name: "Novo Nome"})
        |> render_submit()

      assert has_element?(lv, "#room-max-players-error")
      assert html =~ "não pode ser menor que o número atual de jogadores (3)"
      assert has_element?(lv, ~s|#room-name[value="Novo Nome"]|)
      assert has_element?(lv, ~s|#room-max-players button[aria-checked="true"]|, "2")
      assert Games.get_game_summary(game.id).name == "Sala Cheia"
    end

    test "AC-06: re-selecting the already active language preserves selected categories", %{
      conn: conn
    } do
      player = insert(:player)
      pt_cat = insert(:category, name: "Animais", language: "pt")

      conn = log_in_player(conn, player)
      {:ok, lv, _html} = live(conn, ~p"/salas/nova")

      lv |> element("#category-chip-#{pt_cat.id}") |> render_click()
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")

      lv |> element(~s|#room-language button[phx-value-value="pt"]|) |> render_click()
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")
    end

    test "EDGE-02: handles malformed submit and validate payloads without crashing", %{
      conn: conn
    } do
      owner = insert(:player)
      pt_cat = insert(:category, name: "Animais", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Robusta",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [pt_cat.id]}
        })

      conn = log_in_player(conn, owner)
      {:ok, lv, _html} = live(conn, ~p"/salas/#{game.id}/configuracoes")

      render_change(lv, "validate", %{"room_settings" => %{"name" => ["not", "a", "binary"]}})
      assert has_element?(lv, ~s|#room-name[value="Sala Robusta"]|)

      render_submit(lv, "save", %{
        "room_settings" => %{
          "name" => "Sala Robusta",
          "max_players" => "4",
          "word_options" => "not-a-map"
        }
      })

      assert has_element?(lv, "#room-form")
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")

      render_submit(lv, "save", %{
        "room_settings" => %{
          "name" => "Sala Robusta",
          "max_players" => "4",
          "word_options" => nil
        }
      })

      assert has_element?(lv, "#room-form")
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")

      render_submit(lv, "save", %{
        "room_settings" => %{
          "name" => "Sala Robusta",
          "max_players" => "4",
          "word_options" => %{"language" => "es", "category_ids" => "scalar"}
        }
      })

      assert has_element?(lv, "#room-language-error")
      assert has_element?(lv, ~s|#room-language button[aria-checked="true"]|, "Português")
      assert has_element?(lv, "#category-chip-#{pt_cat.id}[aria-pressed='true']")
    end
  end
end
