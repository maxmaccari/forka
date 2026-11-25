defmodule ForkaWeb.RoomComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ForkaWeb.ConnCase, only: [visible_text: 1]
  import ForkaWeb.RoomComponents

  alias Forka.Games.RoomListItem

  describe "room_status_badge/1" do
    test "AC-05: renders human pt-BR labels and semantic tones for every visible status" do
      lobby = render_component(&room_status_badge/1, %{status: :lobby})
      assert lobby =~ "Na sala"
      assert lobby =~ "bg-success-soft"

      playing = render_component(&room_status_badge/1, %{status: :playing})
      assert playing =~ "Jogando"
      assert playing =~ "bg-warning-soft"

      finished = render_component(&room_status_badge/1, %{status: :finished})
      assert finished =~ "Terminada"
      assert finished =~ "bg-sunken"

      game_over = render_component(&room_status_badge/1, %{status: :game_over})
      assert game_over =~ "Terminada"
      assert game_over =~ "bg-sunken"
    end
  end

  describe "room_card/1" do
    test "AC-05: renders open room with name, badge, owner, language, categories, capacity, and signed-in join button" do
      room = %RoomListItem{
        id: "room-1",
        name: "Noite de palavras",
        status: :lobby,
        player_count: 4,
        max_players: 6,
        owner_username: "Lia",
        language: "pt",
        category_names: ["Cinema", "Jogos", "Música"]
      }

      html =
        render_component(&room_card/1, %{
          id: "rooms-room-1",
          room: room,
          current_player: %{id: "p1", username: "Ana"}
        })

      doc = LazyHTML.from_fragment(html)
      card = LazyHTML.query(doc, "#rooms-room-1")

      assert Enum.count(card) == 1
      card_text = visible_text(card)
      assert card_text =~ "Noite de palavras"
      assert card_text =~ "Na sala"
      assert card_text =~ "de Lia"
      assert card_text =~ "PT"
      assert card_text =~ "4/6 jogadores"
      assert card_text =~ "Cinema, Jogos, Música"

      btn = LazyHTML.query(doc, ~s|#rooms-room-1 button[phx-click="join_room"]|)
      assert Enum.count(btn) == 1
      assert LazyHTML.attribute(btn, "phx-value-id") == ["room-1"]
      assert LazyHTML.attribute(btn, "aria-label") == ["Entrar na sala Noite de palavras"]
      assert LazyHTML.text(btn) =~ "Entrar"
    end

    test "AC-05: renders login link for guests on open room and all-categories fallback when category_names is empty" do
      room = %RoomListItem{
        id: "room-2",
        name: "Friday words",
        status: :lobby,
        player_count: 1,
        max_players: 4,
        owner_username: "Ana",
        language: "en",
        category_names: []
      }

      html =
        render_component(&room_card/1, %{
          id: "rooms-room-2",
          room: room,
          current_player: nil
        })

      doc = LazyHTML.from_fragment(html)
      assert LazyHTML.text(doc) =~ "EN"
      assert LazyHTML.text(doc) =~ "Todas as categorias"

      link = LazyHTML.query(doc, ~s|#rooms-room-2 a[href="/rooms/room-2/join"]|)
      assert Enum.count(link) == 1
      assert LazyHTML.attribute(link, "aria-label") == ["Entrar na sala Friday words"]
    end

    test "AC-05: renders availability notes instead of join CTA for full, playing, and finished rooms" do
      base = %RoomListItem{
        id: "room-3",
        name: "Turma do RPG",
        status: :lobby,
        player_count: 5,
        max_players: 5,
        owner_username: "Caio",
        language: "pt",
        category_names: ["Jogos", "Música", "Cinema", "Esportes"]
      }

      full_html =
        render_component(&room_card/1, %{id: "r-full", room: base, current_player: %{id: "p1"}})

      assert full_html =~ "Cheia"
      assert full_html =~ "Jogos, Música, Cinema +1"
      refute full_html =~ ~s|phx-click="join_room"|

      playing_html =
        render_component(&room_card/1, %{
          id: "r-play",
          room: %{base | status: :playing, player_count: 3},
          current_player: %{id: "p1"}
        })

      assert playing_html =~ "Jogando"
      assert playing_html =~ "Em andamento"
      refute playing_html =~ ~s|phx-click="join_room"|

      ended_html =
        render_component(&room_card/1, %{
          id: "r-end",
          room: %{base | status: :finished},
          current_player: %{id: "p1"}
        })

      assert ended_html =~ "Terminada"
      assert ended_html =~ "Acabou"
      refute ended_html =~ ~s|phx-click="join_room"|
    end
  end

  describe "loading, empty, and error states" do
    test "AC-06: renders accessible loading skeleton, empty state, and error alert with retry" do
      loading_doc =
        render_component(&rooms_loading_skeleton/1, %{}) |> LazyHTML.from_fragment()

      loading = LazyHTML.query(loading_doc, "#rooms-loading")
      assert Enum.count(loading) == 1
      assert LazyHTML.attribute(loading, "aria-busy") == ["true"]

      empty_doc = render_component(&rooms_empty_state/1, %{}) |> LazyHTML.from_fragment()
      assert LazyHTML.text(empty_doc) =~ "Nenhuma sala aberta"
      assert LazyHTML.text(empty_doc) =~ "Crie uma sala e mande o link para a turma."

      error_doc =
        render_component(&rooms_error_state/1, %{
          message: "Não foi possível carregar as salas agora."
        })
        |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(error_doc, ~s|#rooms-error [role="alert"]|)) == 1
      assert LazyHTML.text(error_doc) =~ "Não foi possível carregar as salas agora."
      assert Enum.count(LazyHTML.query(error_doc, ~s|button[phx-click="retry_load"]|)) == 1
    end
  end
end
