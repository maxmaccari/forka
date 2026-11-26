defmodule ForkaWeb.RoomComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ForkaWeb.ConnCase, only: [visible_text: 1]
  import ForkaWeb.RoomComponents

  alias Forka.Games.RoomListItem
  alias Forka.Games.WordAvailability

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

  describe "word availability messaging and alert" do
    test "REQ-06: explains how to broaden categories when filtered pool is too small" do
      availability =
        WordAvailability.evaluate(%{
          available_words: 3,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: true
        })

      message = insufficient_words_message(availability)
      assert message =~ "3 palavras válidas"
      assert message =~ "4"
      assert message =~ "2 por jogador"
      assert message =~ "mais categorias"
      assert message =~ "Todas as categorias"
      assert message =~ "troque o idioma"

      html =
        render_component(&word_availability_alert/1, %{
          id: "room-word-availability-alert",
          availability: availability,
          settings_path: "/rooms/room-1/settings"
        })

      doc = LazyHTML.from_fragment(html)

      assert Enum.count(LazyHTML.query(doc, ~s|#room-word-availability-alert [role="alert"]|)) ==
               1

      assert visible_text(doc) =~ "Poucas palavras para começar"
      assert visible_text(doc) =~ message

      assert Enum.count(
               LazyHTML.query(doc, ~s|#broaden-word-selection[href="/rooms/room-1/settings"]|)
             ) == 1
    end

    test "REQ-06: explains language and player-count options when all categories are already selected" do
      availability =
        WordAvailability.evaluate(%{
          available_words: 4,
          player_count: 3,
          max_players: 6,
          language: "pt",
          has_category_filter?: false
        })

      message = insufficient_words_message(availability)
      assert message =~ "4 palavras válidas"
      assert message =~ "6"
      assert message =~ "todas as categorias já estão incluídas"
      assert message =~ "troque o idioma"
      assert message =~ "menos jogadores"

      # Singular formatting for 1 word and no settings link for non-owners
      one_word =
        WordAvailability.evaluate(%{
          available_words: 1,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      one_msg = insufficient_words_message(one_word)
      assert one_msg =~ "1 palavra válida"
      refute one_msg =~ "menos jogadores"

      html =
        render_component(&word_availability_alert/1, %{
          id: "player-alert",
          availability: one_word,
          settings_path: nil
        })

      doc = LazyHTML.from_fragment(html)
      assert Enum.empty?(LazyHTML.query(doc, "#broaden-word-selection"))
    end
  end

  describe "lobby presentation components" do
    test "REQ-02: lobby_invite_card/1 renders read-only invite URL, copy button, hidden progressive share button, and live status region" do
      html =
        render_component(&lobby_invite_card/1, %{
          id: "room-invite-card",
          invite_url: "http://localhost:4000/rooms/room-1/join",
          room_name: "Noite de palavras"
        })

      doc = LazyHTML.from_fragment(html)
      card = LazyHTML.query(doc, ~s|#room-invite-card[phx-hook="ShareInvite"]|)
      assert Enum.count(card) == 1
      assert LazyHTML.attribute(card, "data-url") == ["http://localhost:4000/rooms/room-1/join"]
      assert LazyHTML.attribute(card, "data-title") == ["Noite de palavras"]

      input = LazyHTML.query(doc, "#room-invite-url[readonly]")
      assert Enum.count(input) == 1
      assert LazyHTML.attribute(input, "value") == ["http://localhost:4000/rooms/room-1/join"]

      assert Enum.count(LazyHTML.query(doc, "#copy-invite-link[data-copy-invite]")) == 1
      assert visible_text(doc) =~ "Chame a turma pelo link"
      assert visible_text(doc) =~ "Copiar link"
      assert Enum.count(LazyHTML.query(doc, "#share-invite-link[data-share-invite].hidden")) == 1
      assert Enum.count(LazyHTML.query(doc, ~s|#copy-invite-status[aria-live="polite"]|)) == 1
    end

    test "REQ-01 & EDGE-04: lobby_roster/1 renders seated players, viewer marker, owner badge, word requirement, and exact empty seats" do
      availability =
        WordAvailability.evaluate(%{
          available_words: 12,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      players = [
        %{id: "p1", username: "lia"},
        %{id: "p2", username: "bruno"}
      ]

      html =
        render_component(&lobby_roster/1, %{
          players: players,
          owner_id: "p1",
          current_player_id: "p2",
          empty_seats: 2,
          player_count: 2,
          max_players: 4,
          word_availability: availability
        })

      doc = LazyHTML.from_fragment(html)
      text = visible_text(doc)

      assert text =~ "Jogadores"
      assert text =~ "2 de 4 · 4 palavras (2 por jogador)"
      assert Enum.count(LazyHTML.query(doc, "#room-lobby-player-p1")) == 1
      assert visible_text(LazyHTML.query(doc, "#room-lobby-player-p1")) =~ "lia"
      assert visible_text(LazyHTML.query(doc, "#room-lobby-player-p1")) =~ "Anfitrião"
      assert visible_text(LazyHTML.query(doc, "#room-lobby-player-p2")) =~ "bruno · você"
      refute visible_text(LazyHTML.query(doc, "#room-lobby-player-p2")) =~ "Anfitrião"
      assert Enum.count(LazyHTML.query(doc, "#room-lobby-empty-seat-1")) == 1
      assert Enum.count(LazyHTML.query(doc, "#room-lobby-empty-seat-2")) == 1
      assert visible_text(LazyHTML.query(doc, "#room-lobby-empty-seat-1")) =~ "Lugar livre"

      # Full room -> zero empty seats
      full_html =
        render_component(&lobby_roster/1, %{
          players: players,
          owner_id: "p1",
          current_player_id: "p1",
          empty_seats: 0,
          player_count: 2,
          max_players: 2,
          word_availability: availability
        })

      full_doc = LazyHTML.from_fragment(full_html)
      assert Enum.empty?(LazyHTML.query(full_doc, "#room-lobby-empty-seat-1"))
      refute visible_text(full_doc) =~ "Lugar livre"
    end

    test "REQ-03: lobby_waiting_status/1 renders role-aware waiting copy without a start button" do
      enough =
        WordAvailability.evaluate(%{
          available_words: 8,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      shortage =
        WordAvailability.evaluate(%{
          available_words: 2,
          player_count: 2,
          max_players: 4,
          language: "pt",
          has_category_filter?: false
        })

      guest_html =
        render_component(&lobby_waiting_status/1, %{
          is_owner?: false,
          owner_username: "lia",
          player_count: 2,
          word_availability: enough
        })

      guest_doc = LazyHTML.from_fragment(guest_html)
      assert Enum.count(LazyHTML.query(guest_doc, ~s|#room-waiting-status[role="status"]|)) == 1
      assert visible_text(guest_doc) =~ "Esperando lia começar"
      assert Enum.count(LazyHTML.query(guest_doc, ".forka-dots")) == 1
      refute visible_text(guest_doc) =~ "Começar partida"

      solo_owner_html =
        render_component(&lobby_waiting_status/1, %{
          is_owner?: true,
          owner_username: "lia",
          player_count: 1,
          word_availability: enough
        })

      assert visible_text(solo_owner_html) =~ "Aguardando pelo menos mais 1 jogador para começar"

      shortage_owner_html =
        render_component(&lobby_waiting_status/1, %{
          is_owner?: true,
          owner_username: "lia",
          player_count: 2,
          word_availability: shortage
        })

      assert visible_text(shortage_owner_html) =~
               "Ajuste as configurações para ter palavras suficientes."

      ready_owner_html =
        render_component(&lobby_waiting_status/1, %{
          is_owner?: true,
          owner_username: "lia",
          player_count: 2,
          word_availability: enough
        })

      assert visible_text(ready_owner_html) =~ "Sala pronta com 2 jogadores (4 palavras)."
      refute visible_text(ready_owner_html) =~ "Começar partida"
    end
  end
end
