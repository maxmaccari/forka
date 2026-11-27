defmodule Forka.GamesTest do
  use Forka.DataCase

  alias Forka.Games
  alias Forka.Games.Core
  alias Forka.Games.GameServer
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Event
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Scope

  import Forka.TestHelpers

  test "concurrent calls reopen one idle playing game" do
    {game, _owner, _other} = start_list_audit_game()
    game_pid = GameServer.whereis(game.id)
    game_ref = Process.monitor(game_pid)
    send(game_pid, :timeout)
    assert_receive {:DOWN, ^game_ref, :process, ^game_pid, :normal}

    game_supervisor = Process.whereis(Forka.GamesSupervisor)
    task_supervisor = start_supervised!(Task.Supervisor)
    :ok = :sys.suspend(game_supervisor)

    callers =
      try do
        for _ <- 1..2 do
          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              receive do
                :reopen -> Games.get_game_summary(game.id)
              end
            end)

          :erlang.trace(task.pid, true, [:send])
          send(task.pid, :reopen)
          caller = task.pid

          assert_receive {:trace, ^caller, :send, {:"$gen_call", _, {:start_child, _}}, _},
                         1_000

          :erlang.trace(task.pid, false, [:send])
          task
        end
      after
        :sys.resume(game_supervisor)
      end

    for caller <- callers do
      assert %{game_status: :playing} = Task.await(caller)
    end
  end

  test "legacy summaries omit old events until a new command is saved" do
    owner = insert(:player)
    game = insert(:game, owner: owner)

    for {type, tick, at} <- [
          {:game_started, 3, ~U[2025-03-18 12:00:00Z]},
          {:player_guessed, 1, ~U[2025-03-18 12:01:00Z]}
        ] do
      Repo.insert!(%Event{game_id: game.id, type: type, tick: tick, at: at})
    end

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert %{last_events: []} = Games.get_game_summary(game.id)

    assert %{last_events: [%{type: :game_started}, %{type: :player_guessed}]} =
             Games.get_game_summary(game.id, load_all_events: true)

    assert {:ok, :joined} = Games.join_room(Scope.for_player(owner), game.id)
    assert %{last_events: [%{type: :player_joined, tick: 4}]} = Games.get_game_summary(game.id)
  end

  test "retrying a lobby leave does not republish the previous event" do
    owner = insert(:player)
    guest = insert(:player)
    guest_scope = Scope.for_player(guest)
    {:ok, game} = Games.create_game(owner.id, %{name: "Retry a leave", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert {:ok, :joined} = Games.join_room(guest_scope, game.id)
    assert :ok = Games.subscribe_to_game(game.id)
    assert :ok = Games.leave_game(guest_scope, game.id)
    assert_receive {:game_updated, %{last_events: [%{type: :player_left, tick: 2}]}}
    assert {:error, :not_a_participant} = Games.leave_game(guest_scope, game.id)
    refute_received {:game_updated, _}
  end

  @tag audit_f04: true
  test "F-04 exposes the saved event for each consecutive public command" do
    owner = insert(:player)
    guest = insert(:player)
    {:ok, game} = Games.create_game(owner.id, %{name: "Event counter", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert {:ok, :joined} = Games.join_room(Scope.for_player(guest), game.id)
    assert [%{tick: 1, type: :player_joined}] = Games.get_game_summary(game.id).last_events

    assert :ok =
             Games.update_room_settings(Scope.for_player(owner), game.id, %{
               name: "Updated counter"
             })

    assert [%{tick: 2, type: :settings_updated}] = Games.get_game_summary(game.id).last_events

    assert {:ok, %{tick: 2, events: events}} = Repository.get_game_state(game.id)
    assert Enum.map(events, &{&1.tick, &1.type}) == [{2, :settings_updated}, {1, :player_joined}]
  end

  @tag audit_f04: true
  test "F-04 resumes a legacy game above its largest stored event tick" do
    owner = insert(:player)
    game = insert(:game, owner: owner)

    Forka.Repo.insert!(%Event{
      game_id: game.id,
      type: :settings_updated,
      tick: 4,
      at: ~U[2025-03-18 12:00:00Z]
    })

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert {:ok, :joined} = Games.join_room(Scope.for_player(owner), game.id)
    assert [%{tick: 5, type: :player_joined}] = Games.get_game_summary(game.id).last_events
    assert {:ok, %{tick: 5, events: events}} = Repository.get_game_state(game.id)
    assert Enum.map(events, &{&1.tick, &1.type}) == [{5, :player_joined}, {4, :settings_updated}]
  end

  @tag audit_f09: true
  test "F-09 finishing a game updates the list and an ordinary correct guess stays room-only" do
    {game, owner, other} = start_list_audit_game()
    scopes = %{owner.id => Scope.for_player(owner), other.id => Scope.for_player(other)}
    assert :ok = Games.subscribe_to_game_list()
    assert :ok = Games.subscribe_to_game(game.id)
    game_id = game.id
    current = Games.get_game_summary(game_id).current_player_id
    {:ok, persisted} = Repository.get_game_state(game_id)
    [l1, l2] = String.graphemes(persisted.game_words[0].word.text)

    assert :ok = Games.guess(scopes[current], game_id, l1)

    assert_receive {:game_updated,
                    %{game_status: :playing, current_word_letters: [{:found, ^l1}, :hidden]}}

    refute_receive {:game_list_updated, %{id: ^game_id}}, 50

    assert :ok = Games.guess(scopes[current], game_id, l2)

    for idx <- 1..3 do
      [w1, w2] = String.graphemes(persisted.game_words[idx].word.text)
      assert :ok = Games.guess(scopes[current], game_id, w1)
      assert :ok = Games.guess(scopes[current], game_id, w2)
    end

    assert_receive {:game_list_updated, %{id: ^game_id, status: :finished, action: :updated}}
  end

  @tag audit_f09: true
  test "F-09 the game list observes a surrender ending the round and its restart" do
    {game, owner, other} = start_list_audit_game()
    scopes = %{owner.id => Scope.for_player(owner), other.id => Scope.for_player(other)}
    assert :ok = Games.subscribe_to_game_list()
    game_id = game.id
    current = Games.get_game_summary(game_id).current_player_id
    next = Enum.find([owner.id, other.id], &(&1 != current))

    assert :ok = Games.give_up_game(scopes[current], game_id)
    refute_receive {:game_list_updated, %{id: ^game_id}}, 50
    assert :ok = Games.give_up_game(scopes[next], game_id)
    assert_receive {:game_list_updated, %{id: ^game_id, status: :game_over, action: :updated}}

    assert :ok = Games.restart_game(Forka.Scope.for_player(owner), game_id)
    assert_receive {:game_list_updated, %{id: ^game_id, status: :lobby, action: :updated}}
  end

  @tag audit_f09: true
  test "F-09 the game list observes an ownership transfer exactly once" do
    {game, owner, other} = start_list_audit_game()
    assert :ok = Games.subscribe_to_game_list()
    game_id = game.id
    other_id = other.id

    assert :ok = Games.transfer_ownership(Forka.Scope.for_player(owner), game_id, other_id)

    assert_receive {:game_list_updated,
                    %{id: ^game_id, owner: %{id: ^other_id}, status: :playing, action: :updated}}

    assert {:error, :already_owner} =
             Games.transfer_ownership(Forka.Scope.for_player(other), game_id, other_id)

    refute_receive {:game_list_updated, %{id: ^game_id}}, 50
  end

  defp start_list_audit_game do
    category = insert(:category, name: "List audit")

    for text <- ~w(ab cd ef gh) do
      Forka.Repo.insert!(%Forka.Words.Word{text: text, category_id: category.id})
    end

    owner = insert(:player)
    other = insert(:player)

    {:ok, game} = Games.create_game(owner.id, %{name: "List audit", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert {:ok, :joined} = Games.join_room(Scope.for_player(other), game.id)
    assert :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)
    {game, owner, other}
  end

  describe "list_games/1" do
    test "returns paginated games with count" do
      # Create test data
      owner = insert(:player)

      # Create games with different statuses
      insert(:game, owner: owner, status: :lobby, name: "Lobby Game 1")
      insert(:game, owner: owner, status: :lobby, name: "Lobby Game 2")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 1")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 2")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 3")
      insert(:game, owner: owner, status: :archived, name: "Archived Game 1")

      # Test default pagination (first page)
      result = Games.list_games()
      assert %{games: games, games_count: count} = result
      assert length(games) == 6
      assert count == 6

      # Test with per_page option
      result = Games.list_games(per_page: 2)
      assert %{games: games, games_count: count} = result
      assert length(games) == 2
      assert count == 6

      # Test with page option
      result = Games.list_games(page: 2, per_page: 2)
      assert %{games: games, games_count: count} = result
      assert length(games) == 2
      assert count == 6

      # Test with game_status filter
      result = Games.list_games(game_status: :playing)
      assert %{games: games, games_count: count} = result
      assert length(games) == 3
      assert count == 3
      assert Enum.all?(games, fn game -> game.status == :playing end)

      # Test with combined pagination and status filter
      result = Games.list_games(page: 1, per_page: 1, game_status: :lobby)
      assert %{games: games, games_count: count} = result
      assert length(games) == 1
      assert count == 2
      assert hd(games).status == :lobby

      # Test with empty result
      result = Games.list_games(game_status: :finished)
      assert %{games: [], games_count: 0} = result
    end

    test "returns empty result when no games exist" do
      result = Games.list_games()
      assert %{games: [], games_count: 0} = result
    end
  end

  describe "list_directory_rooms/0" do
    test "AC-03: returns visible rooms with player counts, owner username, language, and resolved categories while excluding archived rooms" do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      cat_music = insert(:category, name: "Música", language: "pt")
      cat_games = insert(:category, name: "Jogos", language: "pt")

      {:ok, lobby_game} =
        Games.create_game(owner.id, %{
          name: "Noite de palavras",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat_music.id, cat_games.id]}
        })

      {:ok, :joined} = Games.join_room(Scope.for_player(guest), lobby_game.id)

      playing_game =
        insert(:game,
          owner: owner,
          status: :playing,
          name: "Turma do RPG",
          max_players: 4,
          word_options: %Forka.Games.Schemas.WordOptions{language: "en", category_ids: []}
        )

      finished_game =
        insert(:game,
          owner: owner,
          status: :finished,
          name: "Revanche",
          max_players: 4
        )

      game_over_game =
        insert(:game,
          owner: owner,
          status: :game_over,
          name: "Todo mundo caiu",
          max_players: 2
        )

      archived_game =
        insert(:game,
          owner: owner,
          status: :archived,
          name: "Sala arquivada",
          max_players: 4
        )

      rooms = Games.list_directory_rooms()
      room_ids = Enum.map(rooms, & &1.id)

      assert lobby_game.id in room_ids
      assert playing_game.id in room_ids
      assert finished_game.id in room_ids
      assert game_over_game.id in room_ids
      refute archived_game.id in room_ids

      lobby_item = Enum.find(rooms, &(&1.id == lobby_game.id))
      assert lobby_item.name == "Noite de palavras"
      assert lobby_item.status == :lobby
      assert lobby_item.player_count == 2
      assert lobby_item.max_players == 6
      assert lobby_item.owner_username == "lia"
      assert lobby_item.language == "pt"
      assert lobby_item.category_names == ["Jogos", "Música"]

      playing_item = Enum.find(rooms, &(&1.id == playing_game.id))
      assert playing_item.status == :playing
      assert playing_item.player_count == 0
      assert playing_item.language == "en"
      assert playing_item.category_names == []
    end

    test "AC-03: returns an empty list when no visible rooms exist" do
      owner = insert(:player)
      insert(:game, owner: owner, status: :archived, name: "Antiga")

      assert Games.list_directory_rooms() == []
    end

    test "caps the public directory query at directory_limit/0 newest rooms" do
      owner = insert(:player)
      limit = Games.directory_limit()

      for i <- 1..(limit + 2) do
        insert(:game, owner: owner, status: :lobby, name: "Sala #{i}")
      end

      assert length(Games.list_directory_rooms()) == limit
      assert length(Games.list_directory_rooms(limit: limit + 50)) == limit
      assert length(Games.list_directory_rooms(limit: 5)) == 5

      assert %{rooms: page_rooms, has_more?: true} = Games.list_directory_rooms_page()
      assert length(page_rooms) == limit
      assert %{rooms: small_page, has_more?: true} = Games.list_directory_rooms_page(limit: 5)
      assert length(small_page) == 5
    end

    test "list_directory_rooms_page/1 reports has_more?: false when visible rooms equal the limit" do
      owner = insert(:player)

      for i <- 1..3 do
        insert(:game, owner: owner, status: :lobby, name: "Sala #{i}")
      end

      assert %{rooms: rooms, has_more?: false} = Games.list_directory_rooms_page(limit: 3)
      assert length(rooms) == 3

      assert %{rooms: capped_rooms, has_more?: true} = Games.list_directory_rooms_page(limit: 2)
      assert length(capped_rooms) == 2
    end
  end

  describe "create_game/2" do
    test "creates a game with valid parameters" do
      owner = insert(:player)
      params = %{name: "Test Game", max_players: 4}

      assert {:ok, game} = Games.create_game(owner.id, params)
      assert game.name == "Test Game"
      assert game.max_players == 4
      assert game.status == :lobby
      assert game.owner_id == owner.id
    end

    test "returns error with invalid parameters" do
      owner = insert(:player)
      params = %{name: nil, max_players: -1}

      assert {:error, changeset} = Games.create_game(owner.id, params)
      assert "can't be blank" in errors_on(changeset).name
      assert errors_on(changeset).max_players
    end

    test "AC-03: auto-joins the owner at position 0 and broadcasts player_count 1" do
      :ok = Games.subscribe_to_game_list()
      owner = insert(:player, username: "lia")
      cat_pt = insert(:category, name: "Animais", language: "pt")

      assert {:ok, game} =
               Games.create_game(owner.id, %{
                 name: "  Sala da Lia  ",
                 max_players: 4,
                 word_options: %{language: "pt", category_ids: [cat_pt.id]}
               })

      assert game.name == "Sala da Lia"

      summary = Games.get_game_summary(game.id)
      assert map_size(summary.players) == 1
      assert summary.players[0].player.id == owner.id

      assert_receive {:game_list_updated, payload}
      assert payload.id == game.id
      assert payload.player_count == 1
      assert payload.language == "pt"
      assert payload.category_names == ["Animais"]
    end

    test "EDGE-02: create_game/2 rejects unsupported language, malformed UUIDs, and cross-language categories even with padded language" do
      owner = insert(:player)
      en_cat = insert(:category, name: "Animals", language: "en")
      stale_id = Ecto.UUID.generate()

      assert {:error, %Ecto.Changeset{} = cs_lang} =
               Games.create_game(owner.id, %{
                 name: "Sala ES",
                 max_players: 4,
                 word_options: %{language: "es", category_ids: []}
               })

      assert errors_on(cs_lang).word_options.language

      assert {:error, %Ecto.Changeset{} = cs_malformed} =
               Games.create_game(owner.id, %{
                 name: "Sala UUID Ruim",
                 max_players: 4,
                 word_options: %{language: "pt", category_ids: ["not-a-uuid"]}
               })

      assert "contém categorias indisponíveis para o idioma selecionado" in errors_on(
               cs_malformed
             ).word_options.category_ids

      # Padded uppercase language normalizes to "pt" and still rejects EN + stale category IDs
      assert {:error, %Ecto.Changeset{} = cs_cat} =
               Games.create_game(owner.id, %{
                 name: "Sala Mista",
                 max_players: 4,
                 word_options: %{language: " PT ", category_ids: [en_cat.id, stale_id]}
               })

      assert "contém categorias indisponíveis para o idioma selecionado" in errors_on(cs_cat).word_options.category_ids
    end
  end

  describe "update_settings/3 and scoped update_room_settings/3" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Test Game", max_players: 4})
      %{game: game, owner: owner, owner_scope: Forka.Scope.for_player(owner)}
    end

    test "AC-04: updates game settings in lobby state for owner via scope", %{
      game: game,
      owner_scope: owner_scope
    } do
      cat_pt = insert(:category, name: "Filmes", language: "pt")

      settings = %{
        name: "New Name",
        max_players: 6,
        word_options: %{language: "pt", category_ids: [cat_pt.id]}
      }

      assert :ok = Games.update_room_settings(owner_scope, game.id, settings)
      updated_game = Games.get_game_summary(game.id)
      assert updated_game.name == "New Name"
      assert updated_game.max_players == 6
      assert updated_game.word_options.language == "pt"
      assert updated_game.word_options.category_ids == [cat_pt.id]
    end

    test "AC-04: returns {:error, :unauthorized} for non-owner scope", %{game: game} do
      other = insert(:player)
      other_scope = Forka.Scope.for_player(other)

      assert {:error, :unauthorized} =
               Games.update_room_settings(other_scope, game.id, %{name: "Nope"})

      assert Games.get_game_summary(game.id).name == "Test Game"
    end

    test "EDGE-01: rejects max_players below current live occupancy", %{
      game: game,
      owner_scope: owner_scope
    } do
      p2 = insert(:player)
      p3 = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(p3), game.id)

      assert {:error, %Ecto.Changeset{} = cs} =
               Games.update_room_settings(owner_scope, game.id, %{max_players: 2})

      assert errors_on(cs).max_players == [
               "não pode ser menor que o número atual de jogadores (3)"
             ]
    end

    test "EDGE-02: validates language-only and category-only partial updates inside serialized state",
         %{game: game, owner_scope: owner_scope} do
      pt_cat = insert(:category, name: "Filmes", language: "pt")
      en_cat = insert(:category, name: "Movies", language: "en")

      # Category-only patch against current EN language accepts EN category and rejects PT category
      assert :ok =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{category_ids: [en_cat.id]}
               })

      assert {:error, %Ecto.Changeset{} = cs_wrong_cat} =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{category_ids: [pt_cat.id]}
               })

      assert "contém categorias indisponíveis para o idioma selecionado" in errors_on(
               cs_wrong_cat
             ).word_options.category_ids

      # Language-only patch to PT while en_cat is still selected rejects stale EN category
      assert {:error, %Ecto.Changeset{} = cs_lang_only} =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: " PT "}
               })

      assert "contém categorias indisponíveis para o idioma selecionado" in errors_on(
               cs_lang_only
             ).word_options.category_ids

      # Switching language while clearing categories succeeds
      assert :ok =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: " PT ", category_ids: []}
               })

      assert Games.get_game_summary(game.id).word_options.language == "pt"

      # Top-level name-only patch still validates effective word_options if a selected category was deleted
      assert :ok =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: "pt", category_ids: [pt_cat.id]}
               })

      Forka.Repo.delete!(pt_cat)

      assert {:error, %Ecto.Changeset{} = cs_stale_on_name} =
               Games.update_room_settings(owner_scope, game.id, %{name: "Renomeada"})

      assert "contém categorias indisponíveis para o idioma selecionado" in errors_on(
               cs_stale_on_name
             ).word_options.category_ids
    end

    test "AC-04: returns {:error, :game_not_in_lobby} when game not in lobby", %{
      game: game,
      owner_scope: owner_scope
    } do
      player1 = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(player1), game.id)
      insert_list(4, :word)
      :ok = Games.start_game(owner_scope, game.id)

      assert {:error, :game_not_in_lobby} =
               Games.update_room_settings(owner_scope, game.id, %{name: "New Name"})
    end

    test "AC-04: legacy room with non-PT/EN language still persists unrelated state changes" do
      owner = insert(:player)
      guest = insert(:player)

      legacy_game =
        insert(:game,
          owner: owner,
          word_options: %Forka.Games.Schemas.WordOptions{language: "es", category_ids: []}
        )

      assert {:ok, :joined} = Games.join_room(Scope.for_player(guest), legacy_game.id)
      assert Games.get_game_summary(legacy_game.id).word_options.language == "es"
    end
  end

  describe "leave_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      player = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(player), game.id)
      %{game: game, player: player}
    end

    test "removes player from game", %{game: game, player: player} do
      assert :ok = Games.leave_game(Scope.for_player(player), game.id)

      game_state = Games.get_game_summary(game.id)
      refute Enum.any?(game_state.players, fn {_, p} -> p.player.id == player.id end)
    end

    test "REQ-04 & REQ-05: owner leave transfers controls to lowest seat and last-player leave archives room" do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      owner_scope = Scope.for_player(owner)
      p2_scope = Scope.for_player(p2)
      p3_scope = Scope.for_player(p3)

      {:ok, game} = Games.create_room(owner_scope, %{name: "Sala Handoff", max_players: 4})
      assert {:ok, :joined} = Games.join_room(p2_scope, game.id)
      assert {:ok, :joined} = Games.join_room(p3_scope, game.id)

      assert :ok = Games.subscribe_to_room_lobby(p2_scope, game.id)
      assert :ok = Games.subscribe_to_game_list()
      flush_messages()

      # Owner leaves -> p2 (lowest remaining seat) becomes owner
      assert :ok = Games.leave_game(owner_scope, game.id)
      assert_receive {:room_lobby_updated, payload}
      assert {:ok, p2_lobby} = Games.room_lobby_from_payload(p2_scope, payload)
      assert p2_lobby.owner_username == "bruno"
      assert p2_lobby.can_edit_settings? == true
      assert_receive {:game_list_updated, %{id: id, owner_username: "bruno", player_count: 2}}
      assert id == game.id

      # Former owner loses settings permission; new owner gains it
      assert {:error, :unauthorized} =
               Games.update_room_settings(owner_scope, game.id, %{name: "Bloqueado"})

      assert :ok = Games.update_room_settings(p2_scope, game.id, %{name: "Sala do Bruno"})
      flush_messages()

      # p3 leaves, then p2 leaves as last player -> room archives and GameServer stops
      assert :ok = Games.leave_game(p3_scope, game.id)
      flush_messages()

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      assert :ok = Games.leave_game(p2_scope, game.id)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_receive {:room_lobby_updated, %{status: :archived, player_count: 0}}
      assert_receive {:game_list_updated, %{id: archived_id, status: :archived}}
      assert archived_id == game.id
      assert {:error, :game_archived} = Games.get_room_lobby(p2_scope, game.id)
    end

    test "REQ-04: leave_game/3 verifies confirmed consequence against current GameServer state via Scope API" do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      owner_scope = Scope.for_player(owner)
      guest_scope = Scope.for_player(guest)

      {:ok, game} = Games.create_room(owner_scope, %{name: "Sala Confirm", max_players: 4})
      assert {:ok, :joined} = Games.join_room(guest_scope, game.id)

      assert {:error, {:confirmation_required, %Forka.Games.RoomLobby{} = lobby}} =
               Games.leave_game(owner_scope, game.id, confirm: false)

      assert lobby.is_owner? == true
      assert lobby.owner_id == owner.id
      assert lobby.player_count == 2

      # Confirming :archive while guest is present fails without mutating
      assert {:error, {:confirmation_required, %Forka.Games.RoomLobby{player_count: 2}}} =
               Games.leave_game(owner_scope, game.id, confirm: :archive)

      assert :ok = Games.leave_game(guest_scope, game.id, confirm: false)

      # Confirming stale {:handoff, guest.id} after guest left fails without archiving
      assert {:error, {:confirmation_required, %Forka.Games.RoomLobby{} = solo_lobby}} =
               Games.leave_game(owner_scope, game.id, confirm: {:handoff, guest.id})

      assert solo_lobby.player_count == 1
      assert GameServer.whereis(game.id) != nil

      assert :ok = Games.leave_game(owner_scope, game.id, confirm: :archive)
      assert {:error, :game_archived} = Games.get_room_lobby(owner_scope, game.id)
    end

    test "REQ-05: calls queued behind final leave_game stop return {:error, :game_archived} instead of exiting" do
      owner = insert(:player, username: "lia")
      joiner = insert(:player, username: "bruno")
      owner_scope = Scope.for_player(owner)
      joiner_scope = Scope.for_player(joiner)

      {:ok, game} = Games.create_room(owner_scope, %{name: "Sala Shutdown", max_players: 4})
      game_pid = GameServer.whereis(game.id)
      ref = Process.monitor(game_pid)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      joiner_id = joiner.id

      queued_calls = [
        {:join_room, fn -> Games.join_room(joiner_scope, game.id) end},
        {:get_game, fn -> Games.get_room_lobby(joiner_scope, game.id) end},
        {:get_game, fn -> Games.subscribe_to_room_lobby(joiner_scope, game.id) end},
        {:get_game, fn -> Games.get_room_settings_for_edit(owner_scope, game.id) end},
        {:update_settings,
         fn -> Games.update_room_settings(owner_scope, game.id, %{name: "Tarde"}) end},
        {:leave_game, fn -> Games.leave_game(joiner_scope, game.id) end},
        {:start_game, fn -> Games.start_game(owner_scope, game.id) end},
        {:give_up, fn -> Games.give_up_game(owner_scope, game.id) end},
        {:guess, fn -> Games.guess(owner_scope, game.id, "a") end},
        {:transfer_ownership,
         fn -> Games.transfer_ownership(owner_scope, game.id, joiner_id) end},
        {:restart_game, fn -> Games.restart_game(owner_scope, game.id) end},
        {:archive_game, fn -> Games.archive_game(owner_scope, game.id) end}
      ]

      :ok = :sys.suspend(game_pid)

      {leave_task, queued_tasks} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          leave_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.leave_game(owner_scope, game.id, confirm: :archive)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :leave_game and elem(msg, 1) == owner_id

          queued_tasks =
            Enum.map(queued_calls, fn {tag, fun} ->
              task = Task.Supervisor.async_nolink(task_supervisor, fun)

              assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, queued_msg}}, 1_000
              assert elem(queued_msg, 0) == tag

              {tag, task}
            end)

          {leave_task, queued_tasks}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(leave_task, 5_000)
      assert_receive {:DOWN, ^ref, :process, ^game_pid, :normal}

      for {tag, task} <- queued_tasks do
        assert {:error, :game_archived} == Task.await(task, 5_000),
               "expected #{tag} queued behind final leave to return {:error, :game_archived}"
      end

      assert {:error, :game_archived} = Games.join_room(joiner_scope, game.id)
      assert {:error, :game_archived} = Games.get_room_lobby(joiner_scope, game.id)
    end

    test "REQ-05: calls queued behind archive_game stop return {:error, :game_archived} instead of exiting" do
      owner = insert(:player, username: "lia")
      joiner = insert(:player, username: "bruno")
      owner_scope = Scope.for_player(owner)
      joiner_scope = Scope.for_player(joiner)

      {:ok, game} = Games.create_room(owner_scope, %{name: "Sala Archive Race", max_players: 4})
      game_pid = GameServer.whereis(game.id)
      ref = Process.monitor(game_pid)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      joiner_id = joiner.id

      :ok = :sys.suspend(game_pid)

      {archive_task, join_task, lobby_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          archive_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.archive_game(owner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :archive_game and elem(msg, 1) == owner_id

          join_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(joiner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, join_msg}}, 1_000
          assert elem(join_msg, 0) == :join_room and elem(join_msg, 1) == joiner_id

          lobby_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_lobby(joiner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, lobby_msg}}, 1_000
          assert elem(lobby_msg, 0) == :get_game

          {archive_task, join_task, lobby_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(archive_task, 5_000)
      assert_receive {:DOWN, ^ref, :process, ^game_pid, :normal}
      assert {:error, :game_archived} = Task.await(join_task, 5_000)
      assert {:error, :game_archived} = Task.await(lobby_task, 5_000)
    end

    test "REQ-05: calls queued behind idle timeout on a playing game recover by reopening the server" do
      {game, owner, _other} = start_list_audit_game()
      owner_scope = Scope.for_player(owner)
      game_pid = GameServer.whereis(game.id)
      ref = Process.monitor(game_pid)
      task_supervisor = start_supervised!(Task.Supervisor)

      :ok = :sys.suspend(game_pid)

      {lobby_task, join_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          send(game_pid, :timeout)
          assert_receive {:trace, ^game_pid, :receive, :timeout}, 1_000

          lobby_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_lobby(owner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, lobby_msg}}, 1_000
          assert elem(lobby_msg, 0) == :get_game

          join_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(owner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, join_msg}}, 1_000
          assert elem(join_msg, 0) == :join_room

          {lobby_task, join_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert_receive {:DOWN, ^ref, :process, ^game_pid, :normal}
      assert {:ok, %Forka.Games.RoomLobby{status: :playing}} = Task.await(lobby_task, 5_000)
      assert {:ok, :returning_participant} = Task.await(join_task, 5_000)
    end

    test "MAX-53 EDGE-02: owner and target leaving in either order end with one owner" do
      task_supervisor = start_supervised!(Task.Supervisor)

      # Case A1: 2 players with UI confirm opts — owner first, target second
      owner_a1 = insert(:player, username: "lia_a1")
      target_a1 = insert(:player, username: "bruno_a1")
      owner_a1_scope = Scope.for_player(owner_a1)
      target_a1_scope = Scope.for_player(target_a1)
      {:ok, game_a1} = Games.create_room(owner_a1_scope, %{name: "Sala Ordem A1", max_players: 4})
      assert {:ok, :joined} = Games.join_room(target_a1_scope, game_a1.id)
      on_exit(fn -> stop_game_server(game_a1.id) end)

      {first_res, second_res} =
        queue_two_leaves(
          task_supervisor,
          game_a1.id,
          {owner_a1.id,
           fn ->
             Games.leave_game(owner_a1_scope, game_a1.id, confirm: {:handoff, target_a1.id})
           end},
          {target_a1.id, fn -> Games.leave_game(target_a1_scope, game_a1.id, confirm: false) end}
        )

      assert :ok = first_res

      assert {:error,
              {:confirmation_required,
               %Forka.Games.RoomLobby{
                 status: :lobby,
                 owner_id: owner_after_a1,
                 player_count: 1
               }}} = second_res

      assert owner_after_a1 == target_a1.id
      assert {:ok, lobby_a1} = Games.get_room_lobby(target_a1_scope, game_a1.id)
      assert lobby_a1.status == :lobby
      assert lobby_a1.owner_id == target_a1.id
      assert Enum.map(lobby_a1.players, & &1.id) == [target_a1.id]

      # Case A2: 2 players with UI confirm opts — target first, owner second
      owner_a2 = insert(:player, username: "lia_a2")
      target_a2 = insert(:player, username: "bruno_a2")
      owner_a2_scope = Scope.for_player(owner_a2)
      target_a2_scope = Scope.for_player(target_a2)
      {:ok, game_a2} = Games.create_room(owner_a2_scope, %{name: "Sala Ordem A2", max_players: 4})
      assert {:ok, :joined} = Games.join_room(target_a2_scope, game_a2.id)
      on_exit(fn -> stop_game_server(game_a2.id) end)

      {first_res, second_res} =
        queue_two_leaves(
          task_supervisor,
          game_a2.id,
          {target_a2.id, fn -> Games.leave_game(target_a2_scope, game_a2.id, confirm: false) end},
          {owner_a2.id,
           fn ->
             Games.leave_game(owner_a2_scope, game_a2.id, confirm: {:handoff, target_a2.id})
           end}
        )

      assert :ok = first_res

      assert {:error,
              {:confirmation_required,
               %Forka.Games.RoomLobby{
                 status: :lobby,
                 owner_id: owner_after_a2,
                 player_count: 1
               }}} = second_res

      assert owner_after_a2 == owner_a2.id
      assert {:ok, lobby_a2} = Games.get_room_lobby(owner_a2_scope, game_a2.id)
      assert lobby_a2.status == :lobby
      assert lobby_a2.owner_id == owner_a2.id
      assert Enum.map(lobby_a2.players, & &1.id) == [owner_a2.id]
    end
  end

  describe "start_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      {:ok, :joined} = Games.join_room(Scope.for_player(player1), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(player2), game.id)

      insert_list(6, :word)

      %{game: game, owner: owner, players: [player1, player2]}
    end

    test "starts game successfully", %{game: game, owner: owner} do
      assert :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :playing
      assert game_summary.current_player_id != nil
    end

    test "returns error with insufficient players", %{game: game, owner: owner, players: players} do
      # Remove all players except owner
      Enum.each(players, fn player ->
        Games.leave_game(Scope.for_player(player), game.id)
      end)

      assert {:error, :game_not_ready} = Games.start_game(Forka.Scope.for_player(owner), game.id)
    end
  end

  describe "guess/3" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      {:ok, :joined} = Games.join_room(Scope.for_player(player1), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(player2), game.id)

      for text <- ~w(banana papaia goiaba manga laranja amora), do: insert(:word, text: text)

      :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      %{
        game: game,
        owner: owner,
        players: [player1, player2],
        all_players: [owner, player1, player2]
      }
    end

    test "processes valid guess", %{game: game, all_players: all_players} do
      game_summary = Games.get_game_summary(game.id)
      current_player = Enum.find(all_players, &(&1.id == game_summary.current_player_id))

      assert :ok = Games.guess(Scope.for_player(current_player), game.id, "a")

      updated_state = Games.get_game_summary(game.id)
      assert "a" in Enum.map(updated_state.guesses, & &1.letter)
    end

    test "returns error for invalid player turn", %{game: game, all_players: all_players} do
      game_summary = Games.get_game_summary(game.id)

      non_current_player =
        Enum.find(all_players, fn player ->
          player.id != game_summary.current_player_id
        end)

      assert {:error, :not_player_turn} =
               Games.guess(Scope.for_player(non_current_player), game.id, "a")
    end
  end

  describe "game completion scenarios" do
    setup do
      insert_list(6, :word)

      owner = insert(:player)

      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      {:ok, :joined} = Games.join_room(Scope.for_player(player1), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(player2), game.id)

      :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      %{game: game, owner: owner, player1: player1, player2: player2}
    end

    test "game over when all players give up", %{
      game: game,
      owner: owner,
      player1: player1,
      player2: player2
    } do
      :ok = Games.give_up_game(Scope.for_player(owner), game.id)
      :ok = Games.give_up_game(Scope.for_player(player1), game.id)
      :ok = Games.give_up_game(Scope.for_player(player2), game.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :game_over
      assert game_summary.current_player_id == nil
    end

    test "game finishes when all words completed", %{
      game: game,
      owner: owner,
      player1: player1,
      player2: player2
    } do
      {:ok, persisted} = Repository.get_game_state(game.id)
      game_summary = Games.get_game_summary(game.id)

      current_player =
        Enum.find([owner, player1, player2], &(&1.id == game_summary.current_player_id))

      for idx <- 0..5 do
        unique_letters =
          persisted.game_words[idx].word.text
          |> String.downcase()
          |> String.graphemes()
          |> Enum.uniq()

        for letter <- unique_letters do
          assert :ok = Games.guess(Scope.for_player(current_player), game.id, letter)
        end
      end

      # Verify the game is finished after all letters are guessed
      finished_game_summary = Games.get_game_summary(game.id)
      assert finished_game_summary.game_status == :finished
    end
  end

  describe "game subscriptions" do
    setup do
      insert_list(6, :word)
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      :ok = Games.subscribe_to_game(game.id)
      %{game: game, owner: owner}
    end

    test "subscribers receive updates on game changes", %{game: game} do
      player = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(player), game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.players[1].player.id == player.id
    end

    test "subscribers receive game state changes", %{game: game, owner: owner} do
      {:ok, :joined} = Games.join_room(Scope.for_player(insert(:player)), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(insert(:player)), game.id)

      flush_messages()

      :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing
    end

    test "subscribers can unsubscribe from game updates", %{game: game} do
      :ok = Games.unsubscribe_from_game(game.id)
      player = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(player), game.id)

      refute_receive {:game_updated, _}
    end
  end

  describe "game list subscriptions" do
    setup do
      # Subscribe to the game list before each test
      :ok = Games.subscribe_to_game_list()
      %{}
    end

    test "subscribers receive game creation notification" do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      assert_receive {:game_list_updated, game_list_data}
      assert game_list_data.id == game.id
      assert game_list_data.action == :created
      assert game_list_data.status == :lobby
      assert game_list_data.player_count == 1
      assert game_list_data.owner.id == owner.id
    end

    test "subscribers receive updates when players join" do
      owner = insert(:player)
      player = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      # Flush the creation message
      assert_receive {:game_list_updated, _}

      # Join a player
      {:ok, :joined} = Games.join_room(Scope.for_player(player), game.id)

      assert_receive {:game_list_updated, game_list_data}
      assert game_list_data.id == game.id
      assert game_list_data.action == :updated
      assert game_list_data.player_count == 2
    end

    test "subscribers receive updates when game status changes" do
      # Create game with enough players to start
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      player1 = insert(:player)
      player2 = insert(:player)
      {:ok, :joined} = Games.join_room(Scope.for_player(player1), game.id)
      {:ok, :joined} = Games.join_room(Scope.for_player(player2), game.id)

      # Add words so the game can start
      insert_list(6, :word)

      # Flush previous messages
      flush_messages()

      # Start the game
      :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      assert_receive {:game_list_updated, game_list_data}
      assert game_list_data.id == game.id
      assert game_list_data.action == :updated
      assert game_list_data.status == :playing
    end

    test "subscribers receive updates when games are archived" do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      # Flush the creation message
      assert_receive {:game_list_updated, _}

      # Archive the game
      :ok = Games.archive_game(Forka.Scope.for_player(owner), game.id)

      # Sleep to ensure the message has time to propagate
      Process.sleep(10)

      assert_receive {:game_list_updated, game_list_data}
      assert game_list_data.id == game.id
      assert game_list_data.action == :updated
      assert game_list_data.status == :archived
    end

    test "subscribers can unsubscribe from game list updates" do
      :ok = Games.unsubscribe_from_game_list()

      owner = insert(:player)
      {:ok, _game} = Games.create_game(owner.id, params_for(:game))

      refute_receive {:game_list_updated, _}
    end

    test "AC-04: broadcasts owner username, word language, and resolved category names on create and settings update" do
      owner = insert(:player, username: "lia")
      cat_cinema = insert(:category, name: "Cinema", language: "pt")
      cat_sports = insert(:category, name: "Esportes", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala PT",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [cat_cinema.id]}
        })

      assert_receive {:game_list_updated, created_data}
      assert created_data.id == game.id
      assert created_data.owner_username == "lia"
      assert created_data.language == "pt"
      assert created_data.category_names == ["Cinema"]

      created_item = Games.room_list_item_from_event(created_data)
      assert created_item.owner_username == "lia"
      assert created_item.language == "pt"
      assert created_item.category_names == ["Cinema"]

      :ok =
        Games.update_room_settings(Forka.Scope.for_player(owner), game.id, %{
          word_options: %{language: "pt", category_ids: [cat_sports.id, cat_cinema.id]}
        })

      assert_receive {:game_list_updated, updated_data}
      assert updated_data.id == game.id
      assert updated_data.action == :updated
      assert updated_data.language == "pt"
      assert updated_data.category_names == ["Cinema", "Esportes"]
    end
  end

  describe "scoped room lobby and authorization" do
    test "AC-05: rejects empty or nil scope on all scoped room APIs" do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Segura", max_players: 4})
      empty_scope = %Forka.Scope{player: nil}

      for bad_scope <- [empty_scope, nil] do
        assert {:error, :unauthorized} =
                 Games.create_room(bad_scope, %{name: "X", max_players: 4})

        assert {:error, :unauthorized} = Games.get_room_lobby(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.subscribe_to_room_lobby(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.get_room_settings_for_edit(bad_scope, game.id)

        assert {:error, :unauthorized} =
                 Games.update_room_settings(bad_scope, game.id, %{name: "Y"})
      end
    end

    test "AC-05: lobby subscription delivers only lobby-safe fields to a signed-in non-member" do
      owner = insert(:player, username: "lia")
      viewer = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      viewer_scope = Forka.Scope.for_player(viewer)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Aberta", max_players: 4})
      assert :ok = Games.subscribe_to_room_lobby(viewer_scope, game.id)

      assert :ok = Games.update_room_settings(owner_scope, game.id, %{name: "Sala Atualizada"})

      assert_receive {:room_lobby_updated, payload}
      assert payload.id == game.id
      assert payload.name == "Sala Atualizada"
      assert payload.owner_username == "lia"
      assert payload.players == [%{id: owner.id, username: "lia"}]
      refute Map.has_key?(payload, :guesses)
      refute Map.has_key?(payload, :current_word_summary)
      refute Map.has_key?(payload, :current_word_letters)
      refute Map.has_key?(payload, :last_events)
      refute Enum.any?(payload.players, &Map.has_key?(&1, :email))

      assert {:ok, lobby} = Games.room_lobby_from_payload(viewer_scope, payload)
      assert lobby.can_edit_settings? == false
    end

    test "AC-05: returns {:error, :game_archived} across scoped room APIs after archival" do
      owner = insert(:player)
      owner_scope = Forka.Scope.for_player(owner)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Arquivada", max_players: 4})

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      assert :ok = Games.archive_game(Forka.Scope.for_player(owner), game.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert {:error, :game_archived} = Games.get_room_lobby(owner_scope, game.id)
      assert {:error, :game_archived} = Games.subscribe_to_room_lobby(owner_scope, game.id)
      assert {:error, :game_archived} = Games.get_room_settings_for_edit(owner_scope, game.id)

      assert {:error, :game_archived} =
               Games.update_room_settings(owner_scope, game.id, %{name: "Outro nome"})
    end

    test "AC-04: rejects explicit nil word_options without crashing GameServer" do
      owner = insert(:player)
      owner_scope = Forka.Scope.for_player(owner)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Segura", max_players: 4})

      assert {:error, %Ecto.Changeset{} = cs} =
               Games.update_room_settings(owner_scope, game.id, %{
                 name: "Sala Segura",
                 word_options: nil
               })

      assert errors_on(cs).word_options == ["can't be blank"]
      assert {:ok, lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby.name == "Sala Segura"
    end

    test "AC-04: rejects name-only update on a legacy room with an unsupported language" do
      owner = insert(:player)
      owner_scope = Forka.Scope.for_player(owner)

      legacy_game =
        insert(:game,
          owner: owner,
          name: "Sala Legado",
          max_players: 4,
          word_options: %Forka.Games.Schemas.WordOptions{language: "es", category_ids: []}
        )

      assert {:error, %Ecto.Changeset{} = cs} =
               Games.update_room_settings(owner_scope, legacy_game.id, %{name: "Novo Nome"})

      assert errors_on(cs).word_options.language
    end

    test "EDGE-02: rejects category_ids exceeding the max limit on create and update" do
      owner = insert(:player)
      owner_scope = Forka.Scope.for_player(owner)
      limit = WordOptions.max_categories()
      oversized = List.duplicate(Ecto.UUID.generate(), limit + 1)

      assert {:error, %Ecto.Changeset{} = create_cs} =
               Games.create_room(owner_scope, %{
                 name: "Muitas categorias",
                 max_players: 4,
                 word_options: %{language: "pt", category_ids: oversized}
               })

      assert errors_on(create_cs).word_options.category_ids

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Normal", max_players: 4})

      assert {:error, %Ecto.Changeset{} = update_cs} =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: "pt", category_ids: oversized}
               })

      assert errors_on(update_cs).word_options.category_ids
    end
  end

  describe "join_room/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Convite", max_players: 2})
      %{owner: owner, game: game}
    end

    test "REQ-05: returns {:ok, :joined} for new player, {:ok, :already_joined} without duplicate broadcast",
         %{
           game: game
         } do
      player = insert(:player)
      scope = Forka.Scope.for_player(player)
      :ok = Games.subscribe_to_room_lobby(scope, game.id)

      assert {:ok, :joined} = Games.join_room(scope, game.id)
      assert_receive {:room_lobby_updated, %{player_count: 2}}

      assert {:ok, :already_joined} = Games.join_room(scope, game.id)
      refute_receive {:room_lobby_updated, _}
    end

    test "REQ-04: returns {:error, :maximum_players} when full for non-participant", %{game: game} do
      p2 = insert(:player)
      p3 = insert(:player)
      assert {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p2), game.id)
      assert {:error, :maximum_players} = Games.join_room(Forka.Scope.for_player(p3), game.id)
    end

    test "REQ-05: returns {:ok, :returning_participant} for participant in playing room and {:error, :game_already_started} for outsider",
         %{
           owner: owner,
           game: game
         } do
      p2 = insert(:player)
      outsider = insert(:player)
      insert_list(4, :word)
      assert {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p2), game.id)
      assert :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      assert {:ok, :returning_participant} =
               Games.join_room(Forka.Scope.for_player(owner), game.id)

      assert {:ok, :returning_participant} = Games.join_room(Forka.Scope.for_player(p2), game.id)

      assert {:error, :game_already_started} =
               Games.join_room(Forka.Scope.for_player(outsider), game.id)
    end

    test "REQ-04: returns {:error, :unauthorized} for nil scope and {:error, :not_found} for invalid or missing game_id" do
      player = insert(:player)
      scope = Forka.Scope.for_player(player)

      assert {:error, :unauthorized} = Games.join_room(nil, Ecto.UUID.generate())
      assert {:error, :not_found} = Games.join_room(scope, "not-a-uuid")
      assert {:error, :not_found} = Games.join_room(scope, Ecto.UUID.generate())
    end

    test "REQ-07: simultaneous joins to the last seat yield exactly one :joined and :maximum_players for the rest" do
      owner = insert(:player)

      {:ok, game} =
        Games.create_room(Forka.Scope.for_player(owner), %{name: "Última Vaga", max_players: 2})

      contenders = insert_list(5, :player)

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      :ok = :sys.suspend(game_pid)

      tasks =
        try do
          Enum.map(contenders, fn player ->
            scope = Forka.Scope.for_player(player)

            task =
              Task.Supervisor.async_nolink(task_supervisor, fn ->
                receive do
                  :go -> {player.id, Games.join_room(scope, game.id)}
                end
              end)

            :erlang.trace(task.pid, true, [:send])
            send(task.pid, :go)
            caller = task.pid

            assert_receive {:trace, ^caller, :send, {:"$gen_call", _, {:join_room, _}}, _}, 1_000

            :erlang.trace(task.pid, false, [:send])
            task
          end)
        after
          :sys.resume(game_pid)
        end

      results = Enum.map(tasks, &Task.await(&1, 5_000))
      joined = Enum.filter(results, fn {_id, res} -> res == {:ok, :joined} end)
      rejected = Enum.filter(results, fn {_id, res} -> res == {:error, :maximum_players} end)

      assert length(joined) == 1
      assert length(rejected) == length(contenders) - 1

      [{winner_id, {:ok, :joined}}] = joined
      summary = Games.get_game_summary(game.id)
      assert map_size(summary.players) == 2

      summary_ids = summary.players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()
      assert summary_ids == MapSet.new([owner.id, winner_id])

      assert {:ok, persisted} = Repository.get_game_state(game.id)
      assert map_size(persisted.game_players) == 2

      persisted_ids =
        persisted.game_players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      assert persisted_ids == MapSet.new([owner.id, winner_id])
    end
  end

  describe "get_room_invite/1" do
    test "REQ-01: returns safe public room preview with availability_state, language, and categories" do
      owner = insert(:player, username: "maria")
      cat = insert(:category, name: "Animais", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala de Convite",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      assert {:ok, %Forka.Games.RoomInvite{} = invite} = Games.get_room_invite(game.id)
      assert invite.id == game.id
      assert invite.name == "Sala de Convite"
      assert invite.status == :lobby
      assert invite.availability_state == :open
      assert invite.max_players == 4
      assert invite.player_count == 1
      assert invite.language == "pt"
      assert invite.category_names == ["Animais"]
      assert invite.owner_username == "maria"
    end

    test "REQ-03: classifies full and playing states and returns :not_found or :game_archived" do
      owner = insert(:player)
      p2 = insert(:player)
      insert_list(4, :word)
      {:ok, full_game} = Games.create_game(owner.id, %{name: "Cheia", max_players: 2})
      {:ok, :joined} = Games.join_room(Scope.for_player(p2), full_game.id)

      assert {:ok, %{availability_state: :full}} = Games.get_room_invite(full_game.id)

      :ok = Games.start_game(Forka.Scope.for_player(owner), full_game.id)
      assert {:ok, %{availability_state: :playing}} = Games.get_room_invite(full_game.id)

      assert {:error, :not_found} = Games.get_room_invite("bad-id")
      assert {:error, :not_found} = Games.get_room_invite(Ecto.UUID.generate())

      archived = insert(:game, status: :archived)
      assert {:error, :game_archived} = Games.get_room_invite(archived.id)
    end

    test "REQ-01: reads persisted room metadata without starting a cold GameServer" do
      owner = insert(:player, username: "sofia")
      cold_game = insert(:game, name: "Sala Fria", status: :lobby, max_players: 4, owner: owner)

      assert :global.whereis_name({Forka.Games.GameServer, cold_game.id}) == :undefined

      assert {:ok, %Forka.Games.RoomInvite{name: "Sala Fria", owner_username: "sofia"}} =
               Games.get_room_invite(cold_game.id)

      assert :global.whereis_name({Forka.Games.GameServer, cold_game.id}) == :undefined
    end
  end

  describe "REQ-04 & REQ-05: scoped owner commands and stale command rejection" do
    setup do
      owner = insert(:player, username: "dona")
      member = insert(:player, username: "membro")
      outsider = insert(:player, username: "visitante")
      for text <- ~w(ab cd ef gh), do: insert(:word, text: text)

      {:ok, game} =
        Games.create_room(Forka.Scope.for_player(owner), %{name: "Sala Dono", max_players: 4})

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(member), game.id)

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      %{
        game: game,
        owner: owner,
        member: member,
        outsider: outsider,
        owner_scope: Forka.Scope.for_player(owner),
        member_scope: Forka.Scope.for_player(member),
        outsider_scope: Forka.Scope.for_player(outsider)
      }
    end

    test "REQ-04: rejects nil and empty scope with {:error, :unauthorized}, invalid game_id with {:error, :not_found}, and removes unscoped update_settings/3",
         %{game: game, owner_scope: owner_scope, member: member} do
      refute function_exported?(Games, :update_settings, 3)

      for bad_scope <- [nil, %Forka.Scope{player: nil}] do
        assert {:error, :unauthorized} = Games.start_game(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.transfer_ownership(bad_scope, game.id, member.id)
        assert {:error, :unauthorized} = Games.restart_game(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.archive_game(bad_scope, game.id)

        assert {:error, :unauthorized} =
                 Games.update_room_settings(bad_scope, game.id, %{name: "X"})
      end

      assert {:error, :not_found} = Games.start_game(owner_scope, "not-a-uuid")
      assert {:error, :not_found} = Games.transfer_ownership(owner_scope, "not-a-uuid", member.id)
      assert {:error, :not_found} = Games.restart_game(owner_scope, "not-a-uuid")
      assert {:error, :not_found} = Games.archive_game(owner_scope, "not-a-uuid")
      assert {:error, :not_found} = Games.start_game(owner_scope, Ecto.UUID.generate())
    end

    test "REQ-04 & REQ-06: non-owner cannot invoke owner commands or spoof owner_id/player_id in settings params",
         %{
           game: game,
           owner: owner,
           member: member,
           member_scope: member_scope,
           outsider_scope: outsider_scope
         } do
      :ok = Games.subscribe_to_game(game.id)

      for scope <- [member_scope, outsider_scope] do
        assert {:error, :unauthorized} = Games.start_game(scope, game.id)
        assert {:error, :unauthorized} = Games.transfer_ownership(scope, game.id, member.id)
        assert {:error, :unauthorized} = Games.restart_game(scope, game.id)
        assert {:error, :unauthorized} = Games.archive_game(scope, game.id)

        assert {:error, :unauthorized} =
                 Games.update_room_settings(scope, game.id, %{
                   "name" => "Hijacked",
                   "owner_id" => owner.id,
                   "player_id" => owner.id
                 })
      end

      refute_receive {:game_updated, _}
      summary = Games.get_game_summary(game.id)
      assert summary.name == "Sala Dono"
      assert summary.owner.id == owner.id
      assert summary.game_status == :lobby
    end

    test "REQ-05: stale commands from old owner are rejected after ownership transfer while new owner succeeds",
         %{
           game: game,
           owner_scope: owner_scope,
           member: member,
           member_scope: member_scope,
           outsider: outsider
         } do
      assert :ok = Games.transfer_ownership(owner_scope, game.id, member.id)
      :ok = Games.subscribe_to_game(game.id)

      # Stale lobby commands from old owner are rejected
      assert {:error, :unauthorized} =
               Games.update_room_settings(owner_scope, game.id, %{name: "Stale Edit"})

      assert {:error, :unauthorized} = Games.start_game(owner_scope, game.id)
      assert {:error, :unauthorized} = Games.transfer_ownership(owner_scope, game.id, outsider.id)
      assert {:error, :unauthorized} = Games.restart_game(owner_scope, game.id)
      assert {:error, :unauthorized} = Games.archive_game(owner_scope, game.id)
      refute_receive {:game_updated, _}

      # New owner can edit and start; old owner stays rejected in playing and non-playing phases
      assert :ok = Games.update_room_settings(member_scope, game.id, %{name: "Sala do Membro"})
      assert :ok = Games.start_game(member_scope, game.id)
      assert {:error, :unauthorized} = Games.restart_game(owner_scope, game.id)
      assert {:error, :unauthorized} = Games.archive_game(owner_scope, game.id)
      assert {:error, :game_in_progress} = Games.restart_game(member_scope, game.id)
      assert {:error, :game_in_progress} = Games.archive_game(member_scope, game.id)

      # Transfer works in playing phase too, and only to a participant
      assert {:error, :player_not_found} =
               Games.transfer_ownership(member_scope, game.id, outsider.id)

      assert {:error, :already_owner} = Games.transfer_ownership(member_scope, game.id, member.id)
    end

    test "REQ-05: stale lobby-only commands are rejected after game starts",
         %{
           game: game,
           owner_scope: owner_scope,
           member_scope: member_scope,
           outsider_scope: outsider_scope
         } do
      assert :ok = Games.start_game(owner_scope, game.id)
      :ok = Games.subscribe_to_game(game.id)

      assert {:error, :game_not_in_lobby} =
               Games.update_room_settings(owner_scope, game.id, %{name: "Tarde Demais"})

      assert {:error, :game_already_initialized} = Games.start_game(owner_scope, game.id)
      assert {:error, :unauthorized} = Games.start_game(member_scope, game.id)
      assert {:error, :game_in_progress} = Games.restart_game(owner_scope, game.id)
      assert {:error, :game_in_progress} = Games.archive_game(owner_scope, game.id)
      assert {:error, :game_already_started} = Games.join_room(outsider_scope, game.id)
      assert {:ok, :returning_participant} = Games.join_room(member_scope, game.id)

      refute_receive {:game_updated, _}
      assert Games.get_game_summary(game.id).game_status == :playing
    end

    test "STALE-01: transfer_ownership/4 with lobby_only: true rejects started and archived rooms",
         %{game: game, owner_scope: owner_scope, member: member, member_scope: member_scope} do
      assert :ok = Games.start_game(owner_scope, game.id)

      assert {:error, :game_not_in_lobby} =
               Games.transfer_ownership(owner_scope, game.id, member.id, lobby_only: true)

      assert {:error, :unauthorized} =
               Games.transfer_ownership(member_scope, game.id, member.id, lobby_only: true)

      assert :ok = Games.give_up_game(owner_scope, game.id)
      assert :ok = Games.give_up_game(member_scope, game.id)
      assert :ok = Games.archive_game(owner_scope, game.id)

      assert {:error, :game_archived} =
               Games.transfer_ownership(owner_scope, game.id, member.id, lobby_only: true)
    end
  end

  describe "REQ-04 & REQ-06: scoped participant commands and crafted player_id protection" do
    setup do
      owner = insert(:player, username: "dona")
      member = insert(:player, username: "membro")
      outsider = insert(:player, username: "visitante")
      for text <- ~w(ab cd ef gh), do: insert(:word, text: text)

      {:ok, game} =
        Games.create_room(Forka.Scope.for_player(owner), %{name: "Sala Jogo", max_players: 3})

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(member), game.id)

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      %{
        game: game,
        owner: owner,
        member: member,
        outsider: outsider,
        owner_scope: Forka.Scope.for_player(owner),
        member_scope: Forka.Scope.for_player(member),
        outsider_scope: Forka.Scope.for_player(outsider)
      }
    end

    test "REQ-04: rejects nil/empty scope with {:error, :unauthorized}, invalid game_id with {:error, :not_found}, and removes unscoped join_game/2",
         %{game: game, member_scope: member_scope} do
      refute function_exported?(Games, :join_game, 2)

      for bad_scope <- [nil, %Forka.Scope{player: nil}] do
        assert {:error, :unauthorized} = Games.leave_game(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.give_up_game(bad_scope, game.id)
        assert {:error, :unauthorized} = Games.guess(bad_scope, game.id, "a")
      end

      assert {:error, :not_found} = Games.leave_game(member_scope, "not-a-uuid")
      assert {:error, :not_found} = Games.give_up_game(member_scope, "not-a-uuid")
      assert {:error, :not_found} = Games.guess(member_scope, "not-a-uuid", "a")
      assert {:error, :not_found} = Games.leave_game(member_scope, Ecto.UUID.generate())
    end

    test "REQ-04 & REQ-05: enforces membership on leave_game/2, give_up_game/2, and guess/3 in lobby and playing phases",
         %{
           game: game,
           owner: owner,
           member: member,
           owner_scope: owner_scope,
           member_scope: member_scope,
           outsider_scope: outsider_scope
         } do
      :ok = Games.subscribe_to_game(game.id)

      # Lobby: outsider rejected with :not_a_participant; seated member cannot guess/give_up in lobby
      assert {:error, :not_a_participant} = Games.leave_game(outsider_scope, game.id)
      assert {:error, :not_a_participant} = Games.give_up_game(outsider_scope, game.id)
      assert {:error, :not_a_participant} = Games.guess(outsider_scope, game.id, "a")
      assert {:error, :game_not_playing} = Games.give_up_game(member_scope, game.id)
      assert {:error, :game_not_playing} = Games.guess(member_scope, game.id, "a")
      refute_receive {:game_updated, _}

      # Start game: stale leave_game rejected for seated member; outsider rejected on all three
      assert :ok = Games.start_game(owner_scope, game.id)
      flush_messages()

      assert {:error, :game_already_started} = Games.leave_game(member_scope, game.id)
      assert {:error, :not_a_participant} = Games.leave_game(outsider_scope, game.id)
      assert {:error, :not_a_participant} = Games.give_up_game(outsider_scope, game.id)
      assert {:error, :not_a_participant} = Games.guess(outsider_scope, game.id, "a")
      refute_receive {:game_updated, _}

      # Only the current turn player's own scope can guess; the other seated player gets :not_player_turn
      summary = Games.get_game_summary(game.id)
      scopes = %{owner.id => owner_scope, member.id => member_scope}
      current_id = summary.current_player_id
      other_id = Enum.find([owner.id, member.id], &(&1 != current_id))

      assert {:error, :not_player_turn} = Games.guess(scopes[other_id], game.id, "a")
      assert :ok = Games.guess(scopes[current_id], game.id, "a")
    end

    test "REQ-06: crafted raw player_id cannot act for another player on leave, give_up, or guess",
         %{
           game: game,
           owner: owner,
           member: member,
           owner_scope: owner_scope,
           member_scope: member_scope
         } do
      # Passing raw (game.id, member.id) as if calling old unscoped APIs is rejected as :unauthorized
      assert {:error, :unauthorized} = Games.leave_game(game.id, member.id)
      assert {:error, :unauthorized} = Games.give_up_game(game.id, member.id)
      assert {:error, :unauthorized} = Games.guess(game.id, owner.id, "a")

      # Acting with member_scope affects ONLY member (never owner)
      assert :ok = Games.leave_game(member_scope, game.id)
      after_leave = Games.get_game_summary(game.id)
      player_ids = after_leave.players |> Map.values() |> Enum.map(& &1.player.id)
      assert player_ids == [owner.id]
      assert {:error, :not_a_participant} = Games.leave_game(member_scope, game.id)

      # Re-join member, start, and prove give_up_game only marks the scoped actor dead
      assert {:ok, :joined} = Games.join_room(member_scope, game.id)
      assert :ok = Games.start_game(owner_scope, game.id)
      assert :ok = Games.give_up_game(member_scope, game.id)

      after_give_up = Games.get_game_summary(game.id)
      players_by_id = Map.new(after_give_up.players, fn {_pos, gp} -> {gp.player.id, gp} end)
      assert players_by_id[member.id].status == :dead
      assert players_by_id[owner.id].status == :alive
    end
  end

  describe "word availability and roster re-validation" do
    test "REQ-05 & EDGE-02: get_room_lobby/2 and room_lobby_updated payloads re-evaluate availability on join, leave, settings change, and deleted category" do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      owner_scope = Forka.Scope.for_player(owner)

      cat_small = insert(:category, name: "Pequena", language: "pt")
      cat_extra = insert(:category, name: "Extra", language: "pt")

      for text <- ~w(alfa bravo charlie delta) do
        insert(:word, text: text, category: cat_small)
      end

      for text <- ~w(eco foxtrot) do
        insert(:word, text: text, category: cat_extra)
      end

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Disponibilidade",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat_small.id]}
        })

      assert :ok = Games.subscribe_to_room_lobby(owner_scope, game.id)

      # 1 player in lobby, 4 words available -> waiting_for_players
      assert {:ok, lobby_1} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby_1.word_availability.available_words == 4
      assert lobby_1.word_availability.required_words == 4
      assert lobby_1.word_availability.status == :waiting_for_players
      assert lobby_1.word_availability.has_category_filter? == true

      # 2nd player joins -> 4 available >= 4 required -> ready
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      assert_receive {:room_lobby_updated, payload_2}
      assert {:ok, lobby_2} = Games.room_lobby_from_payload(owner_scope, payload_2)
      assert lobby_2.word_availability.status == :ready
      assert lobby_2.word_availability.ready? == true

      # 3rd player joins -> 4 available < 6 required -> insufficient_words
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), game.id)
      assert_receive {:room_lobby_updated, payload_3}
      assert {:ok, lobby_3} = Games.room_lobby_from_payload(owner_scope, payload_3)
      assert lobby_3.word_availability.status == :insufficient_words
      assert lobby_3.word_availability.available_words == 4
      assert lobby_3.word_availability.required_words == 6
      assert lobby_3.word_availability.missing_words == 2

      # Broadening categories to include cat_extra -> 6 available >= 6 required -> ready
      assert :ok =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: "pt", category_ids: [cat_small.id, cat_extra.id]}
               })

      assert_receive {:room_lobby_updated, payload_broad}
      assert {:ok, lobby_broad} = Games.room_lobby_from_payload(owner_scope, payload_broad)
      assert lobby_broad.word_availability.status == :ready
      assert lobby_broad.word_availability.available_words == 6
      assert lobby_broad.word_availability.required_words == 6

      # EDGE-02: if selected category is deleted externally, availability drops to 0 with filter still true
      assert :ok =
               Games.update_room_settings(owner_scope, game.id, %{
                 word_options: %{language: "pt", category_ids: [cat_extra.id]}
               })

      assert_receive {:room_lobby_updated, _}
      Repo.delete!(cat_extra)

      assert {:ok, lobby_deleted} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby_deleted.word_availability.available_words == 0
      assert lobby_deleted.word_availability.has_category_filter? == true
      assert lobby_deleted.word_availability.status == :insufficient_words

      assert {:error, {:insufficient_words, %{available: 0, required: 6}}} =
               Games.start_game(owner_scope, game.id)
    end

    test "EDGE-03: lobby projection of a started room omits word_availability" do
      cat_pt = insert(:category, name: "Frutas", language: "pt")

      # "maçã" and "maca" fold to 1 -> 4 distinct words, enough for 2 players
      for text <- ~w(maçã maca banana uva pera) do
        insert(:word, text: text, category: cat_pt)
      end

      owner = insert(:player)
      p2 = insert(:player)
      owner_scope = Forka.Scope.for_player(owner)

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Jogando",
          max_players: 2,
          word_options: %{language: "pt", category_ids: [cat_pt.id]}
        })

      {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      :ok = Games.start_game(owner_scope, game.id)

      assert {:ok, playing_lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert playing_lobby.status == :playing
      assert playing_lobby.word_availability == nil
    end
  end

  describe "OWN-04: fallback handling for ownerless rooms" do
    test "OWN-04: list_directory_rooms_page/1 hides ownerless rooms without repairing them and keeps pagination counts accurate" do
      base = ~U[2026-11-27 10:00:00Z]

      set_inserted_at = fn game_id, offset_seconds ->
        ts = DateTime.add(base, offset_seconds, :second)

        from(g in Forka.Games.Schemas.Game, where: g.id == ^game_id)
        |> Repo.update_all(set: [inserted_at: ts])
      end

      healthy_owner = insert(:player, username: "lia")
      member = insert(:player, username: "bruno")

      {:ok, healthy} =
        Repository.insert_game(healthy_owner.id, %{name: "Saudavel", max_players: 4})

      set_inserted_at.(healthy.id, 10)

      # Ownerless populated room ahead of healthy room
      shared_owner = insert(:player, username: "ex_dono")

      {:ok, shared_orphan} =
        Repository.insert_game(shared_owner.id, %{name: "Orfa Com Membro", max_players: 4})

      {:ok, shared_state} = Repository.get_game_state(shared_orphan.id)
      {:ok, shared_state} = Core.join_game(shared_state, Repository.get_player(member.id))
      {:ok, _} = Repository.save_game_state(shared_state)
      set_inserted_at.(shared_orphan.id, 30)
      Repo.delete!(shared_owner)

      # Ownerless empty rooms both ahead of and behind the healthy room
      solo_owner1 = insert(:player, username: "caio")

      {:ok, empty_ahead} =
        Repository.insert_game(solo_owner1.id, %{name: "Vazia 1", max_players: 4})

      set_inserted_at.(empty_ahead.id, 20)
      Repo.delete!(solo_owner1)

      solo_owner2 = insert(:player, username: "duda")

      {:ok, empty_behind} =
        Repository.insert_game(solo_owner2.id, %{name: "Vazia 2", max_players: 4})

      set_inserted_at.(empty_behind.id, 5)
      Repo.delete!(solo_owner2)

      page = Games.list_directory_rooms_page(limit: 1)
      assert Enum.map(page.rooms, & &1.id) == [healthy.id]
      assert page.has_more? == false

      # Directory read does not repair ownerless rooms or start servers
      assert GameServer.whereis(shared_orphan.id) == nil
      assert GameServer.whereis(empty_ahead.id) == nil
      assert GameServer.whereis(empty_behind.id) == nil
      assert {:ok, %{owner: nil, status: :lobby}} = Repository.get_game_state(shared_orphan.id)
      assert {:ok, %{owner: nil, status: :lobby}} = Repository.get_game_state(empty_ahead.id)
      assert {:ok, %{owner: nil, status: :lobby}} = Repository.get_game_state(empty_behind.id)
    end

    test "OWN-04: opening an ownerless room repairs it by promoting next seat or archiving when empty" do
      owner1 = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      owner2 = insert(:player, username: "caio")

      {:ok, shared_game} = Repository.insert_game(owner1.id, %{name: "Com Bruno", max_players: 4})
      {:ok, shared_state} = Repository.get_game_state(shared_game.id)
      {:ok, shared_state} = Core.join_game(shared_state, Repository.get_player(p2.id))
      {:ok, _} = Repository.save_game_state(shared_state)

      {:ok, solo_game} = Repository.insert_game(owner2.id, %{name: "Solo Orfa", max_players: 4})

      on_exit(fn ->
        if pid = GameServer.whereis(shared_game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      Repo.delete!(owner1)
      Repo.delete!(owner2)

      # Invite preview heals shared room in persistence without starting a GameServer
      assert GameServer.whereis(shared_game.id) == nil
      :ok = Games.subscribe_to_game_list()
      flush_messages()

      assert {:ok, %Forka.Games.RoomInvite{owner_username: "bruno", player_count: 1}} =
               Games.get_room_invite(shared_game.id)

      assert GameServer.whereis(shared_game.id) == nil

      assert_receive {:game_list_updated,
                      %{id: shared_id, owner_username: "bruno", player_count: 1}}

      assert shared_id == shared_game.id

      {:ok, persisted_shared} = Repository.get_game_state(shared_game.id)
      assert persisted_shared.owner.id == p2.id
      assert Map.keys(persisted_shared.game_players) == [0]
      assert persisted_shared.game_players[0].player.id == p2.id

      assert Enum.count(persisted_shared.events, &(&1.type == :ownership_transferred_to)) == 1

      # Directory now shows the repaired room
      %{rooms: rooms} = Games.list_directory_rooms_page()
      assert Enum.find(rooms, &(&1.id == shared_game.id)).owner_username == "bruno"

      # Invite preview archives empty ownerless room without starting a GameServer
      assert {:error, :game_archived} = Games.get_room_invite(solo_game.id)
      assert GameServer.whereis(solo_game.id) == nil
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(solo_game.id)
    end

    test "OWN-04: get_room_lobby/2 reconciles a running GameServer whose sole owner was deleted and returns :game_archived" do
      owner = insert(:player, username: "lia")
      outsider = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Running Solo", max_players: 4})

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)

      Repo.delete!(owner)

      assert {:error, :game_archived} = Games.get_room_lobby(Scope.for_player(outsider), game.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert {:error, :game_archived} = Games.get_room_invite(game.id)
    end

    @tag sandbox: :auto
    test "F-01 & F-13: concurrent previews of an empty cold orphan serialize, archive once, and never start a GameServer" do
      owner = insert(:player, username: "f13_solo")
      {:ok, game} = Repository.insert_game(owner.id, %{name: "Solo Paralela", max_players: 4})

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end

        cleanup_unboxed_records([game.id], [owner.id])
      end)

      Repo.delete!(owner)

      task_supervisor = start_supervised!(Task.Supervisor)
      games_sup = Process.whereis(Forka.GamesSupervisor)
      {lock_holder, holder_pid, holder_pg_pid} = hold_game_row_lock(task_supervisor, game.id)
      on_exit(fn -> send(holder_pid, :release_lock) end)

      tasks =
        try do
          :erlang.trace(games_sup, true, [:receive])

          first_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_invite(game.id)
            end)

          wait_for_pg_blocker(holder_pg_pid, 2_000)

          second_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              receive do: (:go -> Games.get_room_invite(game.id))
            end)

          second_pid = second_task.pid
          :erlang.trace(second_pid, true, [:send])
          send(second_pid, :go)

          # Second preview contends on the per-room lifecycle lock while first holds it
          assert_receive {:trace, ^second_pid, :send, {:"$gen_call", _, {:set_lock, _}}, _},
                         2_000

          send(holder_pid, :release_lock)
          [first_task, second_task]
        after
          :erlang.trace(:all, false, [:receive, :send])
        end

      assert :ok = Task.await(lock_holder, 5_000)
      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert results == [{:error, :game_archived}, {:error, :game_archived}]
      assert GameServer.whereis(game.id) == nil
      refute_receive {:trace, ^games_sup, :receive, {:"$gen_call", _, {:start_child, _}}}

      {:ok, persisted} = Repository.get_game_state(game.id)
      assert persisted.status == :archived
      assert persisted.owner == nil
      assert persisted.game_players == %{}
      assert Enum.count(persisted.events, &(&1.type == :game_archived)) == 1
    end

    @tag sandbox: :auto
    test "F-13: preview-first race with join serializes on lifecycle lock, keeps unrelated room B unblocked, and preserves join and transfer" do
      owner_a = insert(:player, username: "f13_pf_lia")
      member_a = insert(:player, username: "f13_pf_bruno")
      joiner_a = insert(:player, username: "f13_pf_caio")
      owner_b = insert(:player, username: "f13_pf_duda")
      joiner_b = insert(:player, username: "f13_pf_eva")

      {:ok, game_a} = Repository.insert_game(owner_a.id, %{name: "Orfa PF A", max_players: 4})
      {:ok, state_a} = Repository.get_game_state(game_a.id)
      {:ok, state_a} = Core.join_game(state_a, Repository.get_player(member_a.id))
      {:ok, _} = Repository.save_game_state(state_a)

      {:ok, game_b} = Repository.insert_game(owner_b.id, %{name: "Sala PF B", max_players: 4})

      on_exit(fn ->
        for id <- [game_a.id, game_b.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end

        cleanup_unboxed_records([game_a.id, game_b.id], [
          owner_a.id,
          member_a.id,
          joiner_a.id,
          owner_b.id,
          joiner_b.id
        ])
      end)

      Repo.delete!(owner_a)

      task_supervisor = start_supervised!(Task.Supervisor)
      games_sup = Process.whereis(Forka.GamesSupervisor)
      {lock_holder, holder_pid, holder_pg_pid} = hold_game_row_lock(task_supervisor, game_a.id)
      on_exit(fn -> send(holder_pid, :release_lock) end)

      {preview_task, join_task} =
        try do
          preview_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_invite(game_a.id)
            end)

          # Preview acquired the lifecycle lock and is blocked on room A's FOR UPDATE row lock
          wait_for_pg_blocker(holder_pg_pid, 2_000)
          assert GameServer.whereis(game_a.id) == nil

          :erlang.trace(games_sup, true, [:send, :set_on_spawn])

          join_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(Scope.for_player(joiner_a), game_a.id)
            end)

          # Join registers A's child promptly; the child (not supervisor) waits on A's lifecycle lock
          child_a = wait_for_registered_game_server(game_a.id, 2_000)

          receive do
            {:trace, ^child_a, :send, {:"$gen_call", _, {:set_lock, _}}, _} ->
              :ok
          after
            2_000 -> flunk("child_a did not contend on room A's lifecycle lock")
          end

          # Unrelated room B opens and accepts joins while room A is blocked
          assert {:ok, :joined} = Games.join_room(Scope.for_player(joiner_b), game_b.id)
          assert is_pid(GameServer.whereis(game_b.id))

          send(holder_pid, :release_lock)
          {preview_task, join_task}
        after
          :erlang.trace(:all, false, [:send, :set_on_spawn])
        end

      assert :ok = Task.await(lock_holder, 5_000)

      assert {:ok, %Forka.Games.RoomInvite{owner_username: "f13_pf_bruno"}} =
               Task.await(preview_task, 5_000)

      assert {:ok, :joined} = Task.await(join_task, 5_000)

      # Subsequent ownership transfer and both seats persist cleanly
      assert :ok =
               Games.transfer_ownership(Scope.for_player(member_a), game_a.id, joiner_a.id)

      {:ok, persisted} = Repository.get_game_state(game_a.id)
      assert persisted.owner.id == joiner_a.id

      assert persisted.game_players
             |> Map.values()
             |> Enum.map(& &1.player.id)
             |> Enum.sort() == Enum.sort([member_a.id, joiner_a.id])

      # Exactly one promotion from repair plus one explicit transfer
      handoff_events =
        Enum.filter(persisted.events, &(&1.type == :ownership_transferred_to))

      assert length(handoff_events) == 2

      assert Enum.count(handoff_events, fn ev ->
               ev.payload["to_player_id"] == member_a.id
             end) == 1
    end

    @tag sandbox: :auto
    test "F-13: startup-first race with preview and caller waits past 5s via readiness path with one repair" do
      owner_a = insert(:player, username: "f13_sf_lia")
      member_a = insert(:player, username: "f13_sf_bruno")
      joiner_a = insert(:player, username: "f13_sf_caio")

      {:ok, game_a} = Repository.insert_game(owner_a.id, %{name: "Orfa SF A", max_players: 4})
      {:ok, state_a} = Repository.get_game_state(game_a.id)
      {:ok, state_a} = Core.join_game(state_a, Repository.get_player(member_a.id))
      {:ok, _} = Repository.save_game_state(state_a)

      on_exit(fn ->
        if pid = GameServer.whereis(game_a.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end

        cleanup_unboxed_records([game_a.id], [owner_a.id, member_a.id, joiner_a.id])
      end)

      Repo.delete!(owner_a)

      task_supervisor = start_supervised!(Task.Supervisor)
      {lock_holder, holder_pid, holder_pg_pid} = hold_game_row_lock(task_supervisor, game_a.id)
      on_exit(fn -> send(holder_pid, :release_lock) end)

      {join_task, preview_task, lobby_task} =
        try do
          join_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(Scope.for_player(joiner_a), game_a.id)
            end)

          child_a = wait_for_registered_game_server(game_a.id, 2_000)
          wait_for_pg_blocker(holder_pg_pid, 2_000)

          :erlang.trace(child_a, true, [:receive])

          preview_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_invite(game_a.id)
            end)

          lobby_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_lobby(Scope.for_player(member_a), game_a.id)
            end)

          expected_callers = MapSet.new([preview_task.pid, lobby_task.pid])
          wait_for_ensure_ready_calls(child_a, expected_callers, 2_000)

          Process.send_after(holder_pid, :release_lock, 5_200)
          {join_task, preview_task, lobby_task}
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert :ok = Task.await(lock_holder, 10_000)
      assert {:ok, :joined} = Task.await(join_task, 10_000)

      assert {:ok, %Forka.Games.RoomInvite{owner_username: "f13_sf_bruno"}} =
               Task.await(preview_task, 10_000)

      assert {:ok, %Forka.Games.RoomLobby{owner_username: "f13_sf_bruno"}} =
               Task.await(lobby_task, 10_000)

      {:ok, persisted} = Repository.get_game_state(game_a.id)
      assert persisted.owner.id == member_a.id

      assert persisted.game_players
             |> Map.values()
             |> Enum.map(& &1.player.id)
             |> Enum.sort() == Enum.sort([member_a.id, joiner_a.id])

      assert Enum.count(persisted.events, &(&1.type == :ownership_transferred_to)) == 1
    end

    test "F-13: preview retries cold repair without starting a child when observed PID disappears" do
      owner = insert(:player, username: "f13_dis_lia")
      member = insert(:player, username: "f13_dis_bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Desaparece", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(member), game.id)

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      games_sup = Process.whereis(Forka.GamesSupervisor)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        if running = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, running)
        end
      end)

      # Delete owner directly so DB row is ownerless while old GameServer pid is still registered
      Repo.delete!(owner)
      :ok = :sys.suspend(pid)

      preview_task =
        try do
          :erlang.trace(pid, true, [:receive])
          :erlang.trace(games_sup, true, [:receive])

          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_invite(game.id)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:get_game, _}}}, 2_000

          # Terminate the observed PID normally before it processes :get_game
          :ok = :sys.terminate(pid, :normal)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
          task
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert {:ok, %Forka.Games.RoomInvite{owner_username: "f13_dis_bruno", player_count: 1}} =
               Task.await(preview_task, 5_000)

      assert GameServer.whereis(game.id) == nil
      refute_receive {:trace, ^games_sup, :receive, {:"$gen_call", _, {:start_child, _}}}

      {:ok, persisted} = Repository.get_game_state(game.id)
      assert persisted.owner.id == member.id
      assert persisted.status == :lobby
    end
  end

  describe "remove_player_from_games/1" do
    test "validates UUID input and handles a player in no active rooms" do
      assert {:error, :invalid_player_id} = Games.remove_player_from_games("not-a-uuid")

      player = insert(:player)
      assert :ok = Games.remove_player_from_games(player.id)
    end

    test "removes a player across multiple running, cold, playing, non-owner, and archived rooms" do
      target = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      insert_list(6, :word)

      # 1. Running lobby room owned by target with p2 -> promotes p2
      {:ok, running_shared} =
        Games.create_room(Scope.for_player(target), %{name: "Lobby Viva", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), running_shared.id)

      # 2. Cold sole-owner lobby room (no running GameServer) -> archived, no server left behind
      {:ok, cold_solo} = Repository.insert_game(target.id, %{name: "Fria Solo", max_players: 4})
      assert GameServer.whereis(cold_solo.id) == nil

      # 3. Cold shared lobby room (no running GameServer) -> promoted to p2
      {:ok, cold_shared} =
        Repository.insert_game(target.id, %{name: "Fria Com Bruno", max_players: 4})

      {:ok, cs} = Repository.get_game_state(cold_shared.id)
      {:ok, cs} = Core.join_game(cs, Repository.get_player(p2.id))
      {:ok, _} = Repository.save_game_state(cs)
      assert GameServer.whereis(cold_shared.id) == nil

      # 4. Running playing match owned by target with p2 & p3 -> continues without target
      {:ok, playing_game} =
        Games.create_room(Scope.for_player(target), %{name: "Partida", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), playing_game.id)
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), playing_game.id)
      assert :ok = Games.start_game(Scope.for_player(target), playing_game.id)

      # 5. Room owned by p2 where target is a non-owner member -> target dropped, p2 stays owner
      {:ok, non_owner_room} =
        Games.create_room(Scope.for_player(p2), %{name: "Do Bruno", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(target), non_owner_room.id)

      # 6. Already-archived room owned by target -> untouched, no server started
      {:ok, archived_room} =
        Repository.insert_game(target.id, %{name: "Ja Arquivada", max_players: 4})

      {:ok, as} = Repository.get_game_state(archived_room.id)
      {:ok, arch} = Core.archive_game(as)
      {:ok, _} = Repository.save_game_state(arch)

      on_exit(fn ->
        for id <- [running_shared.id, cold_shared.id, playing_game.id, non_owner_room.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end
      end)

      assert :ok = Games.remove_player_from_games(target.id)

      assert Games.get_game_summary(running_shared.id).owner.id == p2.id
      assert map_size(Games.get_game_summary(running_shared.id).players) == 1

      assert GameServer.whereis(cold_solo.id) == nil
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(cold_solo.id)

      assert Games.get_game_summary(cold_shared.id).owner.id == p2.id

      playing_summary = Games.get_game_summary(playing_game.id)
      assert playing_summary.game_status == :playing
      assert playing_summary.owner.id in [p2.id, p3.id]
      refute Enum.any?(playing_summary.players, fn {_, gp} -> gp.player.id == target.id end)

      non_owner_summary = Games.get_game_summary(non_owner_room.id)
      assert non_owner_summary.owner.id == p2.id
      assert Map.keys(non_owner_summary.players) == [0]
      assert non_owner_summary.players[0].player.id == p2.id

      assert GameServer.whereis(archived_room.id) == nil
      assert {:ok, %{status: :archived}} = Repository.get_game_state(archived_room.id)
    end

    test "sequentially removing all players of a room archives it and stops the server" do
      p1 = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, game} = Games.create_room(Scope.for_player(p1), %{name: "Lote", max_players: 4})
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)

      assert :ok = Games.remove_player_from_games(p1.id)
      assert Games.get_game_summary(game.id).owner.id == p2.id

      assert :ok = Games.remove_player_from_games(p2.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(game.id)
    end

    test "returns an error tuple instead of crashing when a room server fails during removal" do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, game} = Games.create_room(Scope.for_player(owner), %{name: "Falha", max_players: 4})
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)

      pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      :ok = :sys.suspend(pid)

      task =
        try do
          :erlang.trace(pid, true, [:receive])

          t =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.remove_player_from_games(owner.id)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:remove_player, _}}}, 2_000
          Process.exit(pid, :kill)
          t
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert {:error, _reason} = Task.await(task, 5_000)

      # Wait for DynamicSupervisor to finish handling the :transient restart before sandbox teardown
      _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

      if restarted_pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, restarted_pid)
      end
    end

    test "fallback recovers if a player rejoins or creates a room between removal and account deletion" do
      target = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, shared} =
        Games.create_room(Scope.for_player(target), %{name: "Rejoin", max_players: 4})

      on_exit(fn ->
        if pid = GameServer.whereis(shared.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), shared.id)

      assert :ok = Games.remove_player_from_games(target.id)

      # Target rejoins shared room and creates a brand new room before the DB delete runs
      assert {:ok, :joined} = Games.join_room(Scope.for_player(target), shared.id)

      {:ok, brand_new} =
        Games.create_room(Scope.for_player(target), %{name: "Nova Antes Delete", max_players: 4})

      Repo.delete!(target)

      # Public directory hides the ownerless brand_new room
      %{rooms: rooms} = Games.list_directory_rooms_page()
      refute Enum.any?(rooms, &(&1.id == brand_new.id))

      # Opening brand_new archives it via fallback
      assert {:error, :game_archived} = Games.get_room_invite(brand_new.id)

      # Next read on shared drops the deleted rejoined player via running reconciliation
      summary = Games.get_game_summary(shared.id)
      assert summary.owner.id == p2.id
      assert Map.keys(summary.players) == [0]
      assert summary.players[0].player.id == p2.id
    end

    test "F-14: acknowledges removal when a GameServer crashes after persisting the handoff before replying" do
      owner = insert(:player, username: "f14_lost_lia")
      p2 = insert(:player, username: "f14_lost_bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Reply Perdido", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      handler_id = "f14-kill-after-commit-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:forka, :repo, :query],
          fn _event, _measurements, metadata, target_pid ->
            # count_available_words queries "words" inside broadcast_lobby! only after save_game_state committed
            if self() == target_pid and is_binary(metadata[:query]) and
                 String.contains?(metadata[:query], ~s|FROM "words"|) do
              :telemetry.detach(handler_id)
              Process.exit(self(), :kill)
            end
          end,
          pid
        )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

        if restarted = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, restarted)
        end
      end)

      assert :ok = Games.remove_player_from_games(owner.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000

      {:ok, persisted} = Repository.get_game_state(game.id)
      assert persisted.owner.id == p2.id
      assert Map.keys(persisted.game_players) == [0]
      assert persisted.game_players[0].player.id == p2.id
    end

    test "F-14: reports uncertain removal outcome when exit cannot confirm cancellation while player remains persisted" do
      owner = insert(:player, username: "f14_noconn_lia")
      p2 = insert(:player, username: "f14_noconn_bruno")
      owner_id = owner.id

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Sem Conexao", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

        if restarted = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, restarted)
        end
      end)

      :ok = :sys.suspend(pid)

      task =
        try do
          :erlang.trace(pid, true, [:receive])

          t =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.remove_player_from_games(owner.id)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:remove_player, ^owner_id}}},
                         2_000

          Process.exit(pid, :noconnection)
          t
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert {:error, {:removal_outcome_unknown, _reason}} = Task.await(task, 5_000)
      assert {:ok, %{owner: %{id: ^owner_id}}} = Repository.get_game_state(game.id)
    end
  end

  describe "F-12: isolated per-room startup and readiness" do
    @tag sandbox: :auto
    test "F-12: holding room A's row lock does not block room B startup and callers on A wait past 5s for readiness" do
      owner_a = insert(:player, username: "f12_lia")
      joiner_a = insert(:player, username: "f12_bruno")
      owner_b = insert(:player, username: "f12_caio")
      joiner_b = insert(:player, username: "f12_duda")

      {:ok, game_a} = Repository.insert_game(owner_a.id, %{name: "Sala A", max_players: 4})
      {:ok, game_b} = Repository.insert_game(owner_b.id, %{name: "Sala B", max_players: 4})

      on_exit(fn ->
        for id <- [game_a.id, game_b.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end

        cleanup_unboxed_records([game_a.id, game_b.id], [
          owner_a.id,
          joiner_a.id,
          owner_b.id,
          joiner_b.id
        ])
      end)

      task_supervisor = start_supervised!(Task.Supervisor)
      {lock_holder, holder_pid, holder_pg_pid} = hold_game_row_lock(task_supervisor, game_a.id)

      on_exit(fn -> send(holder_pid, :release_lock) end)

      {task_a1, task_a2} =
        try do
          task_a1 =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(Scope.for_player(joiner_a), game_a.id)
            end)

          # Room A registers its child promptly and blocks on its DB row lock inside handle_continue/2
          child_a = wait_for_registered_game_server(game_a.id, 2_000)
          wait_for_pg_blocker(holder_pg_pid, 2_000)

          # Unrelated cold room B starts and serves requests before room A is released
          assert {:ok, :joined} = Games.join_room(Scope.for_player(joiner_b), game_b.id)
          assert is_pid(GameServer.whereis(game_b.id))
          summary_b = Games.get_game_summary(game_b.id)

          assert summary_b.players |> Map.values() |> Enum.map(& &1.player.id) |> Enum.sort() ==
                   Enum.sort([owner_b.id, joiner_b.id])

          # Issue a second operation on room A through the already-registered branch while A is blocked
          :erlang.trace(child_a, true, [:receive])

          task_a2 =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_lobby(Scope.for_player(owner_a), game_a.id)
            end)

          assert_receive {:trace, ^child_a, :receive,
                          {:"$gen_call", {caller_pid, _}, :ensure_ready}},
                         2_000

          assert caller_pid == task_a2.pid

          # Hold past the default 5_000ms GenServer.call timeout, then release
          Process.send_after(holder_pid, :release_lock, 5_200)

          {task_a1, task_a2}
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert :ok = Task.await(lock_holder, 10_000)
      assert {:ok, :joined} = Task.await(task_a1, 10_000)

      assert {:ok, %Forka.Games.RoomLobby{owner_id: owner_a_id}} = Task.await(task_a2, 10_000)
      assert owner_a_id == owner_a.id
    end

    @tag sandbox: :auto
    test "F-12: empty cold orphan stops normally with :game_archived and leaves sibling room running" do
      orphan_owner = insert(:player, username: "f12_orfa")
      sibling_owner = insert(:player, username: "f12_irma")
      outsider = insert(:player, username: "f12_visitante")

      {:ok, orphan} = Repository.insert_game(orphan_owner.id, %{name: "Orfa F12", max_players: 4})

      {:ok, sibling} =
        Games.create_room(Scope.for_player(sibling_owner), %{name: "Irma F12", max_players: 4})

      sibling_pid = GameServer.whereis(sibling.id)
      sibling_ref = Process.monitor(sibling_pid)

      on_exit(fn ->
        for id <- [orphan.id, sibling.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end

        cleanup_unboxed_records([orphan.id, sibling.id], [
          orphan_owner.id,
          sibling_owner.id,
          outsider.id
        ])
      end)

      Repo.delete!(orphan_owner)

      task_supervisor = start_supervised!(Task.Supervisor)
      {lock_holder, holder_pid, holder_pg_pid} = hold_game_row_lock(task_supervisor, orphan.id)

      on_exit(fn -> send(holder_pid, :release_lock) end)

      {task_join, task_lobby, orphan_pid, orphan_ref} =
        try do
          task_join =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(Scope.for_player(outsider), orphan.id)
            end)

          orphan_pid = wait_for_registered_game_server(orphan.id, 2_000)
          orphan_ref = Process.monitor(orphan_pid)
          wait_for_pg_blocker(holder_pg_pid, 2_000)

          :erlang.trace(orphan_pid, true, [:receive])

          task_lobby =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.get_room_lobby(Scope.for_player(outsider), orphan.id)
            end)

          assert_receive {:trace, ^orphan_pid, :receive,
                          {:"$gen_call", {caller_pid, _}, :ensure_ready}},
                         2_000

          assert caller_pid == task_lobby.pid

          send(holder_pid, :release_lock)
          {task_join, task_lobby, orphan_pid, orphan_ref}
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert :ok = Task.await(lock_holder, 5_000)
      assert {:error, :game_archived} = Task.await(task_join, 5_000)
      assert {:error, :game_archived} = Task.await(task_lobby, 5_000)
      assert_receive {:DOWN, ^orphan_ref, :process, ^orphan_pid, :normal}, 2_000
      assert GameServer.whereis(orphan.id) == nil
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(orphan.id)

      refute_receive {:DOWN, ^sibling_ref, :process, ^sibling_pid, _}, 100
      assert GameServer.whereis(sibling.id) == sibling_pid
      assert Games.get_game_summary(sibling.id).game_status == :lobby
    end
  end

  defp hold_game_row_lock(task_supervisor, game_id) do
    test_pid = self()
    {:ok, uuid_bin} = Ecto.UUID.dump(game_id)

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        {:ok, :ok} =
          Repo.transaction(
            fn ->
              %{rows: [[pg_pid]]} = Repo.query!("SELECT pg_backend_pid()", [])
              Repo.query!("SELECT id FROM games WHERE id = $1 FOR UPDATE", [uuid_bin])
              send(test_pid, {:row_locked, self(), pg_pid})

              receive do
                :release_lock -> :ok
              end
            end,
            timeout: :infinity
          )

        :ok
      end)

    receive do
      {:row_locked, holder_pid, pg_pid} -> {task, holder_pid, pg_pid}
    after
      2_000 -> flunk("could not acquire PostgreSQL FOR UPDATE lock on game #{game_id}")
    end
  end

  defp wait_for_registered_game_server(game_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_registered_game_server(game_id, deadline)
  end

  defp do_wait_for_registered_game_server(game_id, deadline) do
    case GameServer.whereis(game_id) do
      pid when is_pid(pid) ->
        pid

      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("GameServer for #{game_id} did not register before timeout")
        else
          receive do
          after
            10 -> do_wait_for_registered_game_server(game_id, deadline)
          end
        end
    end
  end

  defp wait_for_pg_blocker(holder_pg_pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_pg_blocker(holder_pg_pid, deadline)
  end

  defp do_wait_for_pg_blocker(holder_pg_pid, deadline) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid))",
        [holder_pg_pid]
      )

    if count > 0 do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("no PostgreSQL backend blocked on lock holder #{holder_pg_pid}")
      else
        receive do
        after
          10 -> do_wait_for_pg_blocker(holder_pg_pid, deadline)
        end
      end
    end
  end

  defp wait_for_ensure_ready_calls(child_pid, expected_pids, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_ensure_ready_calls(child_pid, expected_pids, deadline)
  end

  defp do_wait_for_ensure_ready_calls(child_pid, remaining, deadline) do
    if MapSet.size(remaining) == 0 do
      :ok
    else
      remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:trace, ^child_pid, :receive, {:"$gen_call", {caller_pid, _}, :ensure_ready}} ->
          do_wait_for_ensure_ready_calls(
            child_pid,
            MapSet.delete(remaining, caller_pid),
            deadline
          )

        {:trace, ^child_pid, :receive, _other} ->
          do_wait_for_ensure_ready_calls(child_pid, remaining, deadline)
      after
        remaining_ms ->
          flunk(
            "callers did not queue :ensure_ready on #{inspect(child_pid)}: #{inspect(remaining)}"
          )
      end
    end
  end

  defp cleanup_unboxed_records(game_ids, player_ids) do
    from(g in Forka.Games.Schemas.Game, where: g.id in ^game_ids) |> Repo.delete_all()
    from(p in Forka.Players.Player, where: p.id in ^player_ids) |> Repo.delete_all()
  end

  defp queue_two_leaves(task_supervisor, game_id, {first_id, first_fun}, {second_id, second_fun}) do
    game_pid = GameServer.whereis(game_id)
    :ok = :sys.suspend(game_pid)

    {first_task, second_task} =
      try do
        :erlang.trace(game_pid, true, [:receive])

        first_task = Task.Supervisor.async_nolink(task_supervisor, first_fun)
        assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, first_msg}}, 1_000
        assert elem(first_msg, 0) == :leave_game and elem(first_msg, 1) == first_id

        second_task = Task.Supervisor.async_nolink(task_supervisor, second_fun)
        assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, second_msg}}, 1_000
        assert elem(second_msg, 0) == :leave_game and elem(second_msg, 1) == second_id

        {first_task, second_task}
      after
        :erlang.trace(game_pid, false, [:receive])
        :sys.resume(game_pid)
      end

    {Task.await(first_task, 5_000), Task.await(second_task, 5_000)}
  end

  defp stop_game_server(game_id) do
    if pid = GameServer.whereis(game_id) do
      DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
    end

    :ok
  end
end
