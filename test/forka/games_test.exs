defmodule Forka.GamesTest do
  use Forka.DataCase

  alias Forka.Games
  alias Forka.Games.GameServer
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Event
  alias Forka.Games.Schemas.WordOptions

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

    assert :ok = Games.join_game(game.id, owner.id)
    assert %{last_events: [%{type: :player_joined, tick: 4}]} = Games.get_game_summary(game.id)
  end

  test "retrying a lobby leave does not republish the previous event" do
    owner = insert(:player)
    guest = insert(:player)
    {:ok, game} = Games.create_game(owner.id, %{name: "Retry a leave", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert :ok = Games.join_game(game.id, guest.id)
    assert :ok = Games.subscribe_to_game(game.id)
    assert :ok = Games.leave_game(game.id, guest.id)
    assert_receive {:game_updated, %{last_events: [%{type: :player_left, tick: 2}]}}
    assert :ok = Games.leave_game(game.id, guest.id)
    refute_received {:game_updated, _}
  end

  @tag audit_f04: true
  test "F-04 exposes the saved event for each consecutive public command" do
    owner = insert(:player)
    {:ok, game} = Games.create_game(owner.id, %{name: "Event counter", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert :ok = Games.join_game(game.id, owner.id)
    assert [%{tick: 1, type: :player_joined}] = Games.get_game_summary(game.id).last_events
    assert :ok = Games.update_settings(game.id, owner.id, %{name: "Updated counter"})
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

    assert :ok = Games.join_game(game.id, owner.id)
    assert [%{tick: 5, type: :player_joined}] = Games.get_game_summary(game.id).last_events
    assert {:ok, %{tick: 5, events: events}} = Repository.get_game_state(game.id)
    assert Enum.map(events, &{&1.tick, &1.type}) == [{5, :player_joined}, {4, :settings_updated}]
  end

  @tag audit_f09: true
  test "F-09 finishing a game updates the list and an ordinary correct guess stays room-only" do
    {game, _owner, _other} = start_list_audit_game()
    assert :ok = Games.subscribe_to_game_list()
    assert :ok = Games.subscribe_to_game(game.id)
    game_id = game.id
    current = Games.get_game_summary(game_id).current_player_id

    assert :ok = Games.guess(game_id, current, "a")

    assert_receive {:game_updated,
                    %{game_status: :playing, current_word_letters: [{:found, "a"}, :hidden]}}

    refute_receive {:game_list_updated, %{id: ^game_id}}, 50

    assert :ok = Games.guess(game_id, current, "b")
    assert_receive {:game_list_updated, %{id: ^game_id, status: :finished, action: :updated}}
  end

  @tag audit_f09: true
  test "F-09 the game list observes a surrender ending the round and its restart" do
    {game, owner, other} = start_list_audit_game()
    assert :ok = Games.subscribe_to_game_list()
    game_id = game.id
    current = Games.get_game_summary(game_id).current_player_id
    next = Enum.find([owner.id, other.id], &(&1 != current))

    assert :ok = Games.give_up_game(game_id, current)
    refute_receive {:game_list_updated, %{id: ^game_id}}, 50
    assert :ok = Games.give_up_game(game_id, next)
    assert_receive {:game_list_updated, %{id: ^game_id, status: :game_over, action: :updated}}

    assert :ok = Games.restart_game(game_id)
    assert_receive {:game_list_updated, %{id: ^game_id, status: :lobby, action: :updated}}
  end

  @tag audit_f09: true
  test "F-09 the game list observes an ownership transfer exactly once" do
    {game, _owner, other} = start_list_audit_game()
    assert :ok = Games.subscribe_to_game_list()
    game_id = game.id
    other_id = other.id

    assert :ok = Games.transfer_ownership(game_id, other_id)

    assert_receive {:game_list_updated,
                    %{id: ^game_id, owner: %{id: ^other_id}, status: :playing, action: :updated}}

    assert {:error, :already_owner} = Games.transfer_ownership(game_id, other_id)
    refute_receive {:game_list_updated, %{id: ^game_id}}, 50
  end

  defp start_list_audit_game do
    category = insert(:category, name: "List audit")
    Forka.Repo.insert!(%Forka.Words.Word{text: "ab", category_id: category.id})
    owner = insert(:player)
    other = insert(:player)

    {:ok, game} = Games.create_game(owner.id, %{name: "List audit", max_players: 2})

    on_exit(fn ->
      if pid = GameServer.whereis(game.id) do
        DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
      end
    end)

    assert :ok = Games.join_game(game.id, owner.id)
    assert :ok = Games.join_game(game.id, other.id)
    assert :ok = Games.start_game(game.id)
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

      :ok = Games.join_game(lobby_game.id, owner.id)
      :ok = Games.join_game(lobby_game.id, guest.id)

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
      :ok = Games.join_game(game.id, p2.id)
      :ok = Games.join_game(game.id, p3.id)

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
      :ok = Games.join_game(game.id, player1.id)
      insert(:word, %{text: "hangman"})
      :ok = Games.start_game(game.id)

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

      assert :ok = Games.join_game(legacy_game.id, guest.id)
      assert Games.get_game_summary(legacy_game.id).word_options.language == "es"
    end
  end

  describe "join_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Test Game", max_players: 4})
      %{game: game}
    end

    test "adds player to game successfully", %{game: game} do
      player = insert(:player)
      assert :ok = Games.join_game(game.id, player.id)

      # Verify player was added
      game_state = Games.get_game_summary(game.id)
      assert Enum.any?(game_state.players, fn {_, p} -> p.player.id == player.id end)
    end

    test "returns error when game is full", %{game: game} do
      # Fill game to max capacity
      for _ <- 1..game.max_players do
        player = insert(:player)
        Games.join_game(game.id, player.id)
      end

      extra_player = insert(:player)
      assert {:error, :maximum_players} = Games.join_game(game.id, extra_player.id)
    end
  end

  describe "leave_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      player = insert(:player)
      :ok = Games.join_game(game.id, player.id)
      %{game: game, player: player}
    end

    test "removes player from game", %{game: game, player: player} do
      assert :ok = Games.leave_game(game.id, player.id)

      game_state = Games.get_game_summary(game.id)
      refute Enum.any?(game_state.players, fn {_, p} -> p.player.id == player.id end)
    end
  end

  describe "start_game/1" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      insert(:word)

      %{game: game, players: [player1, player2]}
    end

    test "starts game successfully", %{game: game} do
      assert :ok = Games.start_game(game.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :playing
      assert game_summary.current_player_id != nil
    end

    test "returns error with insufficient players", %{game: game, players: players} do
      # Remove all players except owner
      Enum.each(players, fn player ->
        Games.leave_game(game.id, player.id)
      end)

      assert {:error, :game_not_ready} = Games.start_game(game.id)
    end
  end

  describe "guess/3" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      insert(:word, text: "banana")

      :ok = Games.start_game(game.id)
      %{game: game, players: [player1, player2]}
    end

    test "processes valid guess", %{game: game} do
      game_summary = Games.get_game_summary(game.id)
      current_player_id = game_summary.current_player_id

      assert :ok = Games.guess(game.id, current_player_id, "a")

      updated_state = Games.get_game_summary(game.id)
      assert "a" in Enum.map(updated_state.guesses, & &1.letter)
    end

    test "returns error for invalid player turn", %{game: game, players: players} do
      game_summary = Games.get_game_summary(game.id)

      non_current_player =
        Enum.find(players, fn player ->
          player.id != game_summary.current_player_id
        end)

      assert {:error, :not_player_turn} = Games.guess(game.id, non_current_player.id, "a")
    end
  end

  describe "game completion scenarios" do
    setup do
      word = insert(:word)

      owner = insert(:player)

      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      :ok = Games.start_game(game.id)

      %{game: game, owner: owner, player1: player1, player2: player2, word: word}
    end

    test "game over when all players give up", %{
      game: game,
      owner: owner,
      player1: player1,
      player2: player2
    } do
      :ok = Games.give_up_game(game.id, owner.id)
      :ok = Games.give_up_game(game.id, player1.id)
      :ok = Games.give_up_game(game.id, player2.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :game_over
      assert game_summary.current_player_id == nil
    end

    test "game finishes when all words completed", %{game: game, word: word} do
      # Extract all unique letters from the word
      unique_letters =
        word.text
        |> String.downcase()
        |> String.graphemes()
        |> Enum.uniq()

      # Get the current game state
      game_summary = Games.get_game_summary(game.id)

      # Guess each letter in the word to complete it
      for letter <- unique_letters do
        assert :ok = Games.guess(game.id, game_summary.current_player_id, letter)
      end

      # Verify the game is finished after all letters are guessed
      finished_game_summary = Games.get_game_summary(game.id)
      assert finished_game_summary.game_status == :finished
    end
  end

  describe "game subscriptions" do
    setup do
      insert(:word)
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      :ok = Games.subscribe_to_game(game.id)
      %{game: game}
    end

    test "subscribers receive updates on game changes", %{game: game} do
      player = insert(:player)
      :ok = Games.join_game(game.id, player.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.players[1].player.id == player.id
    end

    test "subscribers receive game state changes", %{game: game} do
      :ok = Games.join_game(game.id, insert(:player).id)
      :ok = Games.join_game(game.id, insert(:player).id)

      flush_messages()

      :ok = Games.start_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing
    end

    test "subscribers can unsubscribe from game updates", %{game: game} do
      :ok = Games.unsubscribe_from_game(game.id)
      player = insert(:player)
      :ok = Games.join_game(game.id, player.id)

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
      :ok = Games.join_game(game.id, player.id)

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
      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      # Add a word so the game can start
      insert(:word)

      # Flush previous messages
      flush_messages()

      # Start the game
      :ok = Games.start_game(game.id)

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
      :ok = Games.archive_game(game.id)

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
        Games.update_settings(game.id, owner.id, %{
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
      assert :ok = Games.archive_game(game.id)
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
      insert(:word)
      assert {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p2), game.id)
      assert :ok = Games.start_game(game.id)

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
      insert(:word)
      {:ok, full_game} = Games.create_game(owner.id, %{name: "Cheia", max_players: 2})
      :ok = Games.join_game(full_game.id, p2.id)

      assert {:ok, %{availability_state: :full}} = Games.get_room_invite(full_game.id)

      :ok = Games.start_game(full_game.id)
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
end
