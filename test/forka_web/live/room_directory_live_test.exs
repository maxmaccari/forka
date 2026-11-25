defmodule ForkaWeb.RoomDirectoryLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games
  alias ForkaWeb.RoomDirectoryLive

  describe "initial render, loading, empty state, and room list" do
    test "AC-07: GET / renders player header with active Salas nav and initial loading skeleton",
         %{
           conn: conn
         } do
      html = conn |> get(~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      refute html =~ "Phoenix Framework"
      assert Enum.count(LazyHTML.query(doc, ~s|header nav a[href="/"][aria-current="page"]|)) == 1
      assert Enum.count(LazyHTML.query(doc, "#rooms-loading")) == 1
      assert LazyHTML.text(LazyHTML.query(doc, "main h1")) =~ "Salas"
    end

    test "AC-07: shows empty state when no visible rooms exist after async load", %{conn: conn} do
      owner = insert(:player)
      insert(:game, owner: owner, status: :archived, name: "Arquivada")

      {:ok, lv, _html} = live(conn, ~p"/")
      html = render_async(lv)

      assert page_title(lv) =~ "Salas"
      refute has_element?(lv, "#rooms-loading")
      assert has_element?(lv, "#rooms-empty")
      assert html =~ "Nenhuma sala aberta"
      assert html =~ "Ao vivo · nenhuma sala"
    end

    test "AC-07: renders visible rooms with details and count after async load", %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      cat_music = insert(:category, name: "Música", language: "pt")

      {:ok, open_game} =
        Games.create_game(owner.id, %{
          name: "Noite de palavras",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat_music.id]}
        })

      :ok = Games.join_game(open_game.id, owner.id)
      :ok = Games.join_game(open_game.id, guest.id)

      playing_game =
        insert(:game,
          owner: owner,
          status: :playing,
          name: "Turma do RPG",
          max_players: 4
        )

      archived_game =
        insert(:game,
          owner: owner,
          status: :archived,
          name: "Sala antiga",
          max_players: 4
        )

      {:ok, lv, _html} = live(conn, ~p"/")
      html = render_async(lv)
      text = visible_text(html)

      refute has_element?(lv, "#rooms-empty")
      assert has_element?(lv, "#rooms-#{open_game.id}")
      assert has_element?(lv, "#rooms-#{playing_game.id}")
      refute has_element?(lv, "#rooms-#{archived_game.id}")
      assert text =~ "Ao vivo · 2 salas"
      assert text =~ "Noite de palavras"
      assert text =~ "de lia"
      assert text =~ "PT"
      assert text =~ "2/6 jogadores"
      assert text =~ "Música"
      assert text =~ "Turma do RPG"
      assert text =~ "Em andamento"
    end

    test "AC-08: handle_async failure exposes recoverable error state and retry_load restarts loading" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          loading?: true,
          load_error: nil,
          pending_events: [],
          rooms_count: 0,
          room_ids: MapSet.new()
        }
      }

      {:noreply, failed_socket} =
        RoomDirectoryLive.handle_async(:load_rooms, {:exit, :db_unavailable}, socket)

      assert failed_socket.assigns.loading? == false
      assert failed_socket.assigns.load_error == "Não foi possível carregar as salas agora."

      {:noreply, retried_socket} =
        RoomDirectoryLive.handle_event("retry_load", %{}, failed_socket)

      assert retried_socket.assigns.loading? == true
      assert retried_socket.assigns.load_error == nil
    end

    test "load error status shows disconnected copy and ignores PubSub events until retry" do
      socket =
        %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            current_player: nil,
            directory_limit: Games.directory_limit(),
            capped?: false,
            loading?: true,
            load_error: nil,
            pending_events: [],
            rooms_count: 0,
            room_order: [],
            room_ids: MapSet.new()
          },
          private: %{
            lifecycle: %Phoenix.LiveView.Lifecycle{},
            live_temp: %{}
          }
        }
        |> Phoenix.LiveView.stream(:rooms, [])

      {:noreply, failed_socket} =
        RoomDirectoryLive.handle_async(:load_rooms, {:exit, :db_unavailable}, socket)

      event = %{
        id: Ecto.UUID.generate(),
        name: "Criada durante erro",
        status: :lobby,
        player_count: 1,
        max_players: 4,
        owner_username: "eva",
        language: "pt",
        category_names: []
      }

      {:noreply, after_event_socket} =
        RoomDirectoryLive.handle_info({:game_list_updated, event}, failed_socket)

      assert after_event_socket.assigns.rooms_count == 0
      assert after_event_socket.assigns.room_ids == MapSet.new()
      assert after_event_socket.assigns.pending_events == []

      html = render_component(&RoomDirectoryLive.render/1, after_event_socket.assigns)
      assert html =~ "Sem conexão com a lista"
      refute html =~ "Ao vivo"
      assert html =~ "Erro ao carregar salas"
    end

    test "shows capped notice in live status when directory hits directory_limit/0" do
      limit = Games.directory_limit()

      socket =
        %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            current_player: nil,
            directory_limit: limit,
            capped?: true,
            loading?: false,
            load_error: nil,
            pending_events: [],
            rooms_count: limit,
            room_order: [],
            room_ids: MapSet.new()
          },
          private: %{
            lifecycle: %Phoenix.LiveView.Lifecycle{},
            live_temp: %{}
          }
        }
        |> Phoenix.LiveView.stream(:rooms, [])

      html = render_component(&RoomDirectoryLive.render/1, socket.assigns)

      assert visible_text(html) =~
               "Ao vivo · #{limit} salas · mostrando as #{limit} mais recentes"
    end
  end

  describe "live PubSub updates" do
    test "AC-09: streams newly created rooms, player count/capacity changes, settings updates, and status transitions live",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      cat_games = insert(:category, name: "Jogos", language: "pt")
      insert(:word, text: "forka", category: cat_games)

      {:ok, lv, _html} = live(conn, ~p"/")
      _ = render_async(lv)

      assert has_element?(lv, "#rooms-empty")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala ao vivo",
          max_players: 2,
          word_options: %{language: "pt", category_ids: [cat_games.id]}
        })

      text = lv |> render() |> visible_text()
      refute has_element?(lv, "#rooms-empty")
      assert has_element?(lv, "#rooms-#{game.id}")
      assert text =~ "Ao vivo · 1 sala"
      assert text =~ "Sala ao vivo"
      assert text =~ "1/2 jogadores"
      assert text =~ "Jogos"

      assert lv |> render() |> visible_text() =~ "1/2 jogadores"

      :ok = Games.join_game(game.id, guest.id)
      full_text = lv |> render() |> visible_text()
      assert full_text =~ "2/2 jogadores"
      assert full_text =~ "Cheia"

      :ok = Games.update_settings(game.id, owner.id, %{name: "Sala renomeada"})
      assert render(lv) =~ "Sala renomeada"

      :ok = Games.start_game(game.id)
      playing_html = render(lv)
      assert playing_html =~ "Jogando"
      assert playing_html =~ "Em andamento"
    end

    test "AC-09: removes archived rooms live and restores empty state when last room disappears",
         %{
           conn: conn
         } do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala temporária", max_players: 4})

      {:ok, lv, _html} = live(conn, ~p"/")
      _ = render_async(lv)

      assert has_element?(lv, "#rooms-#{game.id}")
      assert render(lv) =~ "Ao vivo · 1 sala"

      :ok = Games.archive_game(game.id)

      html = render(lv)
      refute has_element?(lv, "#rooms-#{game.id}")
      assert has_element?(lv, "#rooms-empty")
      assert html =~ "Ao vivo · nenhuma sala"
      assert html =~ "Nenhuma sala aberta"
    end

    test "EDGE-02: replays PubSub events that arrive while the initial async load is still in flight" do
      id = Ecto.UUID.generate()

      socket =
        %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            directory_limit: Games.directory_limit(),
            capped?: false,
            loading?: true,
            load_error: nil,
            pending_events: [],
            rooms_count: 0,
            room_order: [],
            room_ids: MapSet.new()
          },
          private: %{
            lifecycle: %Phoenix.LiveView.Lifecycle{},
            live_temp: %{}
          }
        }
        |> Phoenix.LiveView.stream(:rooms, [])

      event = %{
        id: id,
        name: "Chegou durante load",
        status: :lobby,
        player_count: 1,
        max_players: 4,
        owner_username: "eva",
        language: "pt",
        category_names: []
      }

      {:noreply, buffered_socket} =
        RoomDirectoryLive.handle_info({:game_list_updated, event}, socket)

      assert buffered_socket.assigns.pending_events == [event]

      {:noreply, loaded_socket} =
        RoomDirectoryLive.handle_async(:load_rooms, {:ok, []}, buffered_socket)

      assert loaded_socket.assigns.loading? == false
      assert loaded_socket.assigns.pending_events == []
      assert loaded_socket.assigns.rooms_count == 1
      assert MapSet.member?(loaded_socket.assigns.room_ids, id)
    end

    test "enforces directory cap on live updates: ignores unknown updates and evicts oldest on new room",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      limit = Games.directory_limit()

      games =
        for i <- 1..(limit + 1) do
          insert(:game, owner: owner, status: :lobby, name: "Sala #{i}")
        end

      ordered = Enum.sort_by(games, &{DateTime.to_unix(&1.inserted_at), &1.id}, :desc)
      oldest_game = List.last(ordered)
      second_oldest_game = Enum.at(ordered, limit - 1)

      {:ok, lv, _html} = live(conn, ~p"/")
      initial_text = lv |> render_async() |> visible_text()

      refute has_element?(lv, "#rooms-#{oldest_game.id}")
      assert has_element?(lv, "#rooms-#{second_oldest_game.id}")

      assert initial_text =~
               "Ao vivo · #{limit} salas · mostrando as #{limit} mais recentes"

      # An :updated broadcast for a room beyond the cap must not insert it or raise the count
      :ok = Games.join_game(oldest_game.id, owner.id)
      after_update_text = lv |> render() |> visible_text()
      refute has_element?(lv, "#rooms-#{oldest_game.id}")
      assert after_update_text =~ "Ao vivo · #{limit} salas · mostrando as #{limit} mais recentes"

      # A :created broadcast prepends the new room and evicts the oldest visible room to stay capped
      {:ok, created_game} = Games.create_game(owner.id, %{name: "Sala novinha", max_players: 4})
      after_create_text = lv |> render() |> visible_text()
      assert has_element?(lv, "#rooms-#{created_game.id}")
      refute has_element?(lv, "#rooms-#{second_oldest_game.id}")
      assert after_create_text =~ "Ao vivo · #{limit} salas · mostrando as #{limit} mais recentes"

      # Archiving a visible room keeps the capped notice because older rooms remain hidden
      :ok = Games.archive_game(created_game.id)
      after_archive_text = lv |> render() |> visible_text()
      refute has_element?(lv, "#rooms-#{created_game.id}")

      assert after_archive_text =~
               "Ao vivo · #{limit - 1} salas · mostrando as #{limit} mais recentes"
    end

    test "does not show capped notice when visible room count equals directory_limit/0", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      limit = Games.directory_limit()

      for i <- 1..limit do
        insert(:game, owner: owner, status: :lobby, name: "Sala #{i}")
      end

      {:ok, lv, _html} = live(conn, ~p"/")
      text = lv |> render_async() |> visible_text()

      assert text =~ "Ao vivo · #{limit} salas"
      refute text =~ "mostrando as #{limit} mais recentes"
    end
  end

  describe "entry points and header controls" do
    test "AC-10: guests have login entry points for create and join and cannot bypass via socket events",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala aberta", max_players: 4})

      {:ok, lv, _html} = live(conn, ~p"/")
      _ = render_async(lv)

      assert has_element?(lv, ~s|#create-room-desktop[href="/players/log_in"]|)
      assert has_element?(lv, ~s|#create-room-mobile[href="/players/log_in"]|)
      assert has_element?(lv, ~s|#rooms-#{game.id} a[href="/players/log_in"]|, "Entrar")

      # Security S2: forged socket events from an unauthenticated visitor redirect to login
      assert {:error, {:live_redirect, %{to: "/players/log_in"}}} =
               render_hook(lv, "create_room", %{})

      {:ok, lv2, _html} = live(conn, ~p"/")
      _ = render_async(lv2)

      assert {:error, {:live_redirect, %{to: "/players/log_in"}}} =
               render_hook(lv2, "join_room", %{"id" => game.id})
    end

    test "AC-10: signed-in players trigger create and join entry points with pt-BR feedback", %{
      conn: conn
    } do
      player = insert(:player, username: "ana")
      {:ok, game} = Games.create_game(player.id, %{name: "Sala aberta", max_players: 4})

      {:ok, lv, _html} = conn |> log_in_player(player) |> live(~p"/")
      _ = render_async(lv)

      join_html =
        lv
        |> element(~s|#rooms-#{game.id} button[phx-click="join_room"]|)
        |> render_click()

      assert join_html =~ "A entrada na sala estará disponível em breve."

      lv |> element("#create-room-desktop") |> render_click()
      assert_redirect(lv, ~p"/salas/nova")
    end

    test "AC-11: header connects theme toggle and account links for both guests and signed-in players",
         %{conn: conn} do
      guest_doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
      assert Enum.count(LazyHTML.query(guest_doc, "header [data-theme-toggle]")) == 1
      assert Enum.count(LazyHTML.query(guest_doc, ~s|header a[href="/players/register"]|)) == 1
      assert Enum.count(LazyHTML.query(guest_doc, ~s|header a[href="/players/log_in"]|)) == 1

      player = insert(:player, email: "ana@example.com")

      authed_doc =
        conn
        |> log_in_player(player)
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert Enum.count(LazyHTML.query(authed_doc, "header [data-theme-toggle]")) == 1
      assert Enum.count(LazyHTML.query(authed_doc, ~s|header a[href="/players/settings"]|)) == 1

      assert Enum.count(
               LazyHTML.query(
                 authed_doc,
                 ~s|header a[href="/players/log_out"][data-method="delete"]|
               )
             ) == 1
    end

    test "EDGE-03: unavailable rooms do not render a join entry point", %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, full_game} = Games.create_game(owner.id, %{name: "Sala cheia", max_players: 2})
      :ok = Games.join_game(full_game.id, owner.id)
      :ok = Games.join_game(full_game.id, guest.id)

      {:ok, lv, _html} = conn |> log_in_player(owner) |> live(~p"/")
      html = render_async(lv)

      assert has_element?(lv, "#rooms-#{full_game.id}")
      assert html =~ "Cheia"
      refute has_element?(lv, ~s|#rooms-#{full_game.id} button[phx-click="join_room"]|)
      refute has_element?(lv, ~s|#rooms-#{full_game.id} a[href="/players/log_in"]|)
    end
  end
end
