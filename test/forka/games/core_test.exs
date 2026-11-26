defmodule Forka.Games.CoreTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Forka.Games.Core
  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.WordOptions

  import Forka.TestHelpers

  setup do
    owner = build_games_player("Owner")

    %{owner: owner}
  end

  describe "new/2" do
    test "creates a new game with valid parameters", %{owner: owner} do
      name = "Test Game"
      max_players = 4
      game = Core.new(owner, name, max_players)

      assert game.owner == owner
      assert game.name == name
      assert game.max_players == max_players
      assert game.status == :lobby
      assert game.game_words == %{}
      assert game.game_players == %{}
      assert game.current_game_word_index == nil
      assert game.current_game_player_index == nil
      assert game.tick == 0
      assert game.events == []
    end
  end

  describe "join_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game: game, player: player}
    end

    test "adds player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Core.join_game(game, player)

      assert map_size(updated_game.game_players) == 1

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [%{type: :player_joined, payload: %{player_id: player.id}}])

      assert %{0 => game_player} = updated_game.game_players

      assert game_player.player.id == player.id
      assert game_player.player.username == player.username
      assert game_player.status == :alive
      assert game_player.lives == 6
      assert game_player.score == 0
    end

    test "adds players in sequential order", %{game: game} do
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_player2} = Core.join_game(game_with_player1, player2)
      {:ok, game_with_player3} = Core.join_game(game_with_player2, player3)

      assert map_size(game_with_player3.game_players) == 3
      assert %{0 => %{player: %{username: "Player 1"}}} = game_with_player3.game_players
      assert %{1 => %{player: %{username: "Player 2"}}} = game_with_player3.game_players
      assert %{2 => %{player: %{username: "Player 3"}}} = game_with_player3.game_players
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Core.join_game(game_started, player)
    end

    test "returns error when max players reached", %{game: game, player: player} do
      game = %{game | max_players: 1}
      {:ok, game_with_player} = Core.join_game(game, player)

      player2 = build_games_player("Player 2")
      assert {:error, :maximum_players} = Core.join_game(game_with_player, player2)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.join_game(game_archived, player)
    end
  end

  describe "leave_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game_with_player} = Core.join_game(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "removes non-last player successfully when in lobby", %{
      owner: owner,
      game: game,
      player: player
    } do
      {:ok, game_with_two} = Core.join_game(game, owner)

      {:ok, updated_game} = Core.leave_game(game_with_two, player.id)
      assert updated_game.status == :lobby
      assert updated_game.owner.id == owner.id
      assert map_size(updated_game.game_players) == 1
      assert %{0 => %{player: %{id: owner_id}}} = updated_game.game_players
      assert owner_id == owner.id
      assert updated_game.tick == game_with_two.tick + 1

      assert assert_last_events(updated_game, [
               %{type: :player_left, payload: %{player_id: player.id}}
             ])
    end

    test "reindexes players after removal", %{game: game_with_player1} do
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")

      {:ok, game_with_player2} = Core.join_game(game_with_player1, player2)
      {:ok, game_with_player3} = Core.join_game(game_with_player2, player3)

      {:ok, updated_game} = Core.leave_game(game_with_player3, player2.id)

      # Check that player3 is now at index 1 (second position)
      assert map_size(updated_game.game_players) == 2
      assert %{0 => %{player: %{username: "Player 1"}}} = updated_game.game_players
      assert %{1 => %{player: %{username: "Player 3"}}} = updated_game.game_players
    end

    test "REQ-04 & EDGE-01: transfers ownership automatically to lowest remaining seat when owner leaves in lobby",
         %{owner: owner} do
      p1 = build_games_player("Bruno")
      p2 = build_games_player("Caio")

      # Case 1: owner at seat 0 -> seat 1 (Bruno) becomes owner
      game_owner_first =
        Core.new(owner, "Sala da Lia", 4)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, owner)
          g
        end)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, p1)
          g
        end)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, p2)
          g
        end)

      assert {:ok, after_first} = Core.leave_game(game_owner_first, owner.id)
      assert after_first.status == :lobby
      assert after_first.owner.id == p1.id
      assert after_first.owner.username == "Bruno"
      assert after_first.tick == game_owner_first.tick + 1
      assert map_size(after_first.game_players) == 2
      assert %{0 => %{player: %{id: id0}}, 1 => %{player: %{id: id1}}} = after_first.game_players
      assert {id0, id1} == {p1.id, p2.id}

      assert assert_last_events(after_first, [
               %{
                 type: :ownership_transferred_to,
                 payload: %{from_player_id: owner.id, to_player_id: p1.id}
               },
               %{type: :player_left, payload: %{player_id: owner.id}}
             ])

      # Case 2: owner at seat 1 (non-zero) -> seat 0 (Bruno) becomes owner, seat 2 (Caio) shifts to 1
      game_owner_middle =
        Core.new(owner, "Sala Meio", 4)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, p1)
          g
        end)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, owner)
          g
        end)
        |> then(fn g ->
          {:ok, g} = Core.join_game(g, p2)
          g
        end)

      assert {:ok, after_middle} = Core.leave_game(game_owner_middle, owner.id)
      assert after_middle.status == :lobby
      assert after_middle.owner.id == p1.id
      assert %{0 => %{player: %{id: m0}}, 1 => %{player: %{id: m1}}} = after_middle.game_players
      assert {m0, m1} == {p1.id, p2.id}
    end

    test "REQ-05: archives room when last player leaves in lobby", %{owner: owner} do
      {:ok, solo_owner_game} = Core.new(owner, "Sala Solo", 4) |> Core.join_game(owner)

      assert {:ok, archived} = Core.leave_game(solo_owner_game, owner.id)
      assert archived.status == :archived
      assert archived.owner.id == owner.id
      assert map_size(archived.game_players) == 0
      assert archived.tick == solo_owner_game.tick + 1

      assert assert_last_events(archived, [
               %{type: :game_archived, payload: nil},
               %{type: :player_left, payload: %{player_id: owner.id}}
             ])
    end

    property "EDGE-01: owner leaving a 2..6 player lobby always transfers ownership to lowest remaining seat and preserves order" do
      check all(
              roster_size <- integer(2..6),
              owner_seat <- integer(0..(roster_size - 1))
            ) do
        players = for idx <- 0..(roster_size - 1), do: build_games_player("Player#{idx}")
        owner = Enum.at(players, owner_seat)

        game =
          Enum.reduce(players, Core.new(owner, "Prop Room", 6), fn p, acc ->
            {:ok, next} = Core.join_game(acc, p)
            next
          end)

        expected_remaining = List.delete_at(players, owner_seat)
        expected_owner = hd(expected_remaining)

        assert {:ok, updated} = Core.leave_game(game, owner.id)
        assert updated.status == :lobby
        assert updated.owner.id == expected_owner.id

        actual_ids =
          updated.game_players
          |> Enum.sort_by(fn {pos, _gp} -> pos end)
          |> Enum.map(fn {_pos, gp} -> gp.player.id end)

        assert actual_ids == Enum.map(expected_remaining, & &1.id)
      end
    end

    test "REQ-01: returns {:error, :not_a_participant} when non-member tries to leave in lobby or playing",
         %{game: game} do
      unknown_player = build_games_player("Unknown")
      assert {:error, :not_a_participant} = Core.leave_game(game, unknown_player.id)

      playing_game = %{game | status: :playing}
      assert {:error, :not_a_participant} = Core.leave_game(playing_game, unknown_player.id)
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Core.leave_game(game_started, player.id)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.leave_game(game_archived, player.id)
    end

    test "REQ-04: leave_game/3 verifies confirmed consequence for current owner while allowing non-owner leave",
         %{owner: owner, game: game, player: player} do
      {:ok, game_with_two} = Core.join_game(game, owner)

      assert {:error, :confirmation_required} =
               Core.leave_game(game_with_two, owner.id, confirm: false)

      assert {:error, :confirmation_required} =
               Core.leave_game(game_with_two, owner.id, confirmed?: true)

      assert {:error, :confirmation_required} =
               Core.leave_game(game_with_two, owner.id, confirm: :archive)

      assert {:error, :confirmation_required} =
               Core.leave_game(game_with_two, owner.id, confirm: {:handoff, Ecto.UUID.generate()})

      assert {:ok, updated_game} =
               Core.leave_game(game_with_two, player.id, confirm: false)

      assert map_size(updated_game.game_players) == 1
      assert updated_game.owner.id == owner.id

      assert {:error, :confirmation_required} =
               Core.leave_game(updated_game, owner.id, confirm: false)

      assert {:error, :confirmation_required} =
               Core.leave_game(updated_game, owner.id, confirm: {:handoff, player.id})

      assert {:ok, archived_game} =
               Core.leave_game(updated_game, owner.id, confirm: :archive)

      assert archived_game.status == :archived

      # Handoff with matching target succeeds
      other = build_games_player("Other")
      {:ok, handoff_game} = Core.join_game(game_with_two, other)
      # Seat 0 is player, seat 1 is owner, seat 2 is other -> remaining lowest seat is player
      assert {:error, :confirmation_required} =
               Core.leave_game(handoff_game, owner.id, confirm: {:handoff, other.id})

      assert {:ok, handed_off} =
               Core.leave_game(handoff_game, owner.id, confirm: {:handoff, player.id})

      assert handed_off.owner.id == player.id

      playing_game = %{game_with_two | status: :playing}

      assert {:error, :game_already_started} =
               Core.leave_game(playing_game, owner.id, confirm: false)
    end
  end

  describe "set_words/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)

      words = [
        Word.new("cat", "animals", "Meows"),
        Word.new("dog", "animals", "Barks")
      ]

      {:ok, game: game, words: words}
    end

    test "sets words successfully", %{game: game, words: words} do
      assert updated_game = Core.set_words(game, words)
      assert map_size(updated_game.game_words) == 2

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [%{type: :words_set, payload: %{count: 2}}])

      Enum.each(updated_game.game_words, fn {_idx, game_word} ->
        assert %GameWord{} = game_word
        assert game_word.guesses == []
        assert game_word.finished_by_id == nil
      end)
    end

    test "removes duplicate words", %{game: game, words: words} do
      duplicate_words = words ++ [List.first(words)]
      updated_game = Core.set_words(game, duplicate_words)
      assert map_size(updated_game.game_words) == 2
    end

    test "does not set words when game is not in lobby state", %{game: game, words: words} do
      game_playing = %{game | status: :playing}
      assert ^game_playing = Core.set_words(game_playing, words)

      game_archived = %{game | status: :archived}
      assert ^game_archived = Core.set_words(game_archived, words)
    end

    test "REQ-02 & EDGE-01: deduplicates case/accent variants across categories and drops unplayable words",
         %{game: game} do
      words = [
        Word.new("Café", "Bebidas", "Quente"),
        Word.new("cafe", "Comida", "Preto"),
        Word.new("CAFÉ", "Outros", nil),
        Word.new("", "Bebidas"),
        Word.new("   ", "Bebidas"),
        Word.new("1234", "Bebidas"),
        Word.new("---", "Bebidas"),
        Word.new("straße", "Bebidas"),
        Word.new("øl", "Bebidas"),
        Word.new("Gato", "Animais")
      ]

      updated_game = Core.set_words(game, words)
      assert map_size(updated_game.game_words) == 2

      keys =
        updated_game.game_words
        |> Map.values()
        |> Enum.map(&Word.normalized_key(&1.word))
        |> MapSet.new()

      assert keys == MapSet.new(["cafe", "gato"])
    end
  end

  describe "shuffle_players/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 10)

      # Add multiple players to ensure we have enough for shuffling
      players = for i <- 1..10, do: build_games_player("Player #{i}")

      # Add all players to the game
      game_with_players =
        Enum.reduce(players, game, fn player, acc_game ->
          {:ok, updated_game} = Core.join_game(acc_game, player)
          updated_game
        end)

      {:ok, game: game_with_players, players: players}
    end

    test "shuffles players only in lobby state", %{game: game} do
      # Test in lobby state
      shuffled_game = Core.shuffle_players(game)
      assert shuffled_game.status == :lobby

      assert shuffled_game.tick == game.tick + 1
      assert_last_events(shuffled_game, [%{type: :players_shuffled}])

      # The player IDs should be the same, but potentially in different order
      original_player_ids =
        game.game_players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      shuffled_player_ids =
        shuffled_game.game_players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      assert original_player_ids == shuffled_player_ids

      # Verify player indices are sequential and start from 0
      player_indices = shuffled_game.game_players |> Map.keys() |> Enum.sort()
      assert player_indices == Enum.to_list(0..(map_size(shuffled_game.game_players) - 1))

      # Test in playing state - should not shuffle
      game_playing = %{game | status: :playing}
      assert ^game_playing = Core.shuffle_players(game_playing)

      # Test in archived state - should not shuffle
      game_archived = %{game | status: :archived}
      assert ^game_archived = Core.shuffle_players(game_archived)
    end

    test "maintains consistent state after shuffle", %{game: game} do
      shuffled_game = Core.shuffle_players(game)

      # Player count should remain the same
      assert map_size(game.game_players) == map_size(shuffled_game.game_players)

      # Each player should maintain their properties
      Enum.each(shuffled_game.game_players, fn {_idx, game_player} ->
        assert game_player.status == :alive
        assert game_player.lives == 6
        assert game_player.score == 0
      end)
    end
  end

  describe "start_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")

      words = [
        Word.new("cat", "Animals", "Meows"),
        Word.new("dog", "Animals", "Barks"),
        Word.new("fox", "Animals", "Clever"),
        Word.new("owl", "Animals", "Hoots")
      ]

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, words)

      {:ok, game: game_with_words}
    end

    test "initializes game successfully when ready", %{game: game} do
      {:ok, initialized_game} = Core.start_game(game, game.owner.id)

      assert initialized_game.status == :playing
      assert initialized_game.current_game_word_index == 0
      assert initialized_game.current_game_player_index == 0
      assert map_size(initialized_game.game_players) == 2
      assert map_size(initialized_game.game_words) == 4

      assert initialized_game.tick == game.tick + 1
      assert_last_events(initialized_game, [%{type: :game_started}])
    end

    test "returns error when game not in lobby", %{game: game} do
      game_started = %{game | status: :playing}

      assert {:error, :game_already_initialized} =
               Core.start_game(game_started, game_started.owner.id)
    end

    test "returns error when not enough players", %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game_with_player} = Core.join_game(game, player)

      assert {:error, :game_not_ready} = Core.start_game(game_with_player, owner.id)
    end

    test "returns error when game is archived", %{game: game} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.start_game(game_archived, game_archived.owner.id)
    end

    test "REQ-02: requires two distinct playable words per player for 2-player and 6-player matches",
         %{owner: owner} do
      # 2 players need 4 distinct playable words
      game_2 = Core.new(owner, "Sala 2", 2)
      {:ok, game_2} = Core.join_game(game_2, build_games_player("P1"))
      {:ok, game_2} = Core.join_game(game_2, build_games_player("P2"))

      three_words = [
        Word.new("gato", "Animais"),
        Word.new("pato", "Animais"),
        Word.new("lobo", "Animais"),
        Word.new("GATO", "Pets")
      ]

      assert {:error, {:insufficient_words, %{available: 3, required: 4}}} =
               game_2 |> Core.set_words(three_words) |> Core.start_game(owner.id)

      four_words = [
        Word.new("gato", "Animais"),
        Word.new("pato", "Animais"),
        Word.new("lobo", "Animais"),
        Word.new("urso", "Animais")
      ]

      assert {:ok, started_2} = game_2 |> Core.set_words(four_words) |> Core.start_game(owner.id)
      assert started_2.status == :playing
      assert map_size(started_2.game_words) == 4

      # 6 players need 12 distinct playable words
      game_6 =
        Enum.reduce(1..6, Core.new(owner, "Sala 6", 6), fn i, acc ->
          {:ok, next} = Core.join_game(acc, build_games_player("P#{i}"))
          next
        end)

      eleven_words =
        ~w(alfa bravo charlie delta eco foxtrot golfe hotel india juliet kilo)
        |> Enum.map(&Word.new(&1, "Alfabeto"))

      assert {:error, {:insufficient_words, %{available: 11, required: 12}}} =
               game_6 |> Core.set_words(eleven_words) |> Core.start_game(owner.id)

      twelve_words = eleven_words ++ [Word.new("lima", "Alfabeto")]

      assert {:ok, started_6} =
               game_6 |> Core.set_words(twelve_words) |> Core.start_game(owner.id)

      assert started_6.status == :playing
      assert map_size(started_6.game_words) == 12
    end

    test "REQ-03: rejects starting when roster exceeds 6-player limit or room max_players", %{
      owner: owner
    } do
      game_7 =
        Enum.reduce(1..7, Core.new(owner, "Sala 7", 10), fn i, acc ->
          {:ok, next} = Core.join_game(acc, build_games_player("P#{i}"))
          next
        end)

      words_14 =
        ~w(um dois tres quatro cinco seis sete oito nove dez onze doze treze quatorze)
        |> Enum.map(&Word.new(&1, "Numeros"))

      assert {:error, :too_many_players} = Core.validate_start_roster(game_7)

      assert {:error, :too_many_players} =
               game_7 |> Core.set_words(words_14) |> Core.start_game(owner.id)
    end

    test "REQ-02: required_words_for_players/1 and words_per_player/0 enforce 2 words per player" do
      assert Core.words_per_player() == 2
      assert Core.required_words_for_players(0) == 4
      assert Core.required_words_for_players(1) == 4
      assert Core.required_words_for_players(2) == 4
      assert Core.required_words_for_players(3) == 6
      assert Core.required_words_for_players(6) == 12
    end
  end

  describe "restart_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")

      words = [
        Word.new("cat", "Animals", "Meows"),
        Word.new("dog", "Animals", "Barks"),
        Word.new("fox", "Animals", "Clever"),
        Word.new("owl", "Animals", "Hoots")
      ]

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, words)

      {:ok, initialized_game} = Core.start_game(game_with_words, owner.id)

      # Create a finished game with some player state changes
      finished_game = %{initialized_game | status: :finished}

      # Simulate a player with reduced lives and dead status
      updated_players =
        Map.update!(
          finished_game.game_players,
          0,
          fn player -> %{player | lives: 0, status: :dead} end
        )

      finished_game_with_player_changes = %{finished_game | game_players: updated_players}

      {:ok,
       game_lobby: game_with_words,
       game_playing: initialized_game,
       game_finished: finished_game_with_player_changes}
    end

    test "restarts game successfully when in finished status", %{game_finished: game} do
      assert {:ok, restarted_game} = Core.restart_game(game, game.owner.id)

      # Check that game is back in lobby state
      assert restarted_game.status == :lobby

      # Check that player lives and status are reset
      Enum.each(restarted_game.game_players, fn {_idx, player} ->
        assert player.lives == 6
        assert player.status == :alive
      end)

      # Check that game state is properly reset
      assert restarted_game.current_game_player_index == nil
      assert restarted_game.current_game_word_index == nil
      assert restarted_game.game_words == %{}

      assert restarted_game.tick == game.tick + 1
      assert_last_events(restarted_game, [%{type: :game_restarted}])
    end

    @tag audit_f08: true
    test "F-08 restarting a finished round resets all player scores", %{game_finished: game} do
      game = %{
        game
        | game_players:
            game.game_players
            |> Map.update!(0, &%{&1 | score: 70})
            |> Map.update!(1, &%{&1 | score: 30})
      }

      assert {:ok, restarted} = Core.restart_game(game, game.owner.id)
      assert restarted.status == :lobby
      assert %{score: 0, lives: 6, status: :alive} = restarted.game_players[0]
      assert %{score: 0, lives: 6, status: :alive} = restarted.game_players[1]
    end

    test "restarts game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, restarted_game} = Core.restart_game(game, game.owner.id)
      assert restarted_game.status == :lobby
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Core.restart_game(game, game.owner.id)
    end

    test "returns error when game is archived", %{game_finished: game} do
      # First archive the game
      {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      # Then try to restart it
      assert {:error, :game_archived} = Core.restart_game(archived_game, archived_game.owner.id)
    end
  end

  describe "archive_game/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")

      words = [
        Word.new("cat", "Animals", "Meows"),
        Word.new("dog", "Animals", "Barks"),
        Word.new("fox", "Animals", "Clever"),
        Word.new("owl", "Animals", "Hoots")
      ]

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, words)

      {:ok, initialized_game} = Core.start_game(game_with_words, owner.id)

      # Create a finished game
      finished_game = %{initialized_game | status: :finished}

      {:ok,
       game_lobby: game_with_words, game_playing: initialized_game, game_finished: finished_game}
    end

    test "archives game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      assert archived_game.tick == game.tick + 1
      assert_last_events(archived_game, [%{type: :game_archived}])
    end

    test "archives game successfully when in finished status", %{game_finished: game} do
      assert {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Core.archive_game(game)
    end

    test "cannot modify an archived game", %{game_lobby: game} do
      # First archive the game
      {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      # Verify that archived games cannot be modified
      player = build_games_player("New Player")
      word = Word.new("dog", "Animals", "Barks")

      # Test various operations on archived game
      assert {:error, :game_archived} = Core.join_game(archived_game, player)
      assert {:error, :game_archived} = Core.leave_game(archived_game, "any_player_id")
      assert archived_game == Core.set_words(archived_game, [word])
      assert archived_game == Core.shuffle_players(archived_game)
      assert {:error, :game_archived} = Core.start_game(archived_game, archived_game.owner.id)
      assert {:error, :game_archived} = Core.guess(archived_game, "any_player_id", "a")
      assert {:error, :game_archived} = Core.give_up_game(archived_game, "any_player_id")
    end
  end

  describe "transfer_ownership_to_player/3" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)

      {:ok, game: game_with_players, player1: player1, player2: player2, owner: owner}
    end

    test "transfers ownership successfully", %{game: game, player1: player1} do
      {:ok, updated_game} = Core.transfer_ownership_to_player(game, game.owner.id, player1.id)

      assert updated_game.owner.id == player1.id
      assert updated_game.owner.username == player1.username

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [
        %{
          type: :ownership_transferred_to,
          payload: %{from_player_id: game.owner.id, to_player_id: player1.id}
        }
      ])
    end

    test "returns error when player is not in the game", %{game: game} do
      non_player = build_games_player("Non Player")

      assert {:error, :player_not_found} =
               Core.transfer_ownership_to_player(game, game.owner.id, non_player.id)
    end

    test "returns error when player is already the owner", %{game: game, owner: owner} do
      assert {:error, :already_owner} =
               Core.transfer_ownership_to_player(game, owner.id, owner.id)
    end

    test "works in any game state but archived", %{game: game, player2: player2} do
      # Test in playing state
      game_playing = %{game | status: :playing}

      {:ok, updated_game} =
        Core.transfer_ownership_to_player(game_playing, game_playing.owner.id, player2.id)

      assert updated_game.owner.id == player2.id

      # Test in finished state
      game_finished = %{game | status: :finished}

      {:ok, updated_game} =
        Core.transfer_ownership_to_player(game_finished, game_finished.owner.id, player2.id)

      assert updated_game.owner.id == player2.id

      # Test in archived state
      game_archived = %{game | status: :archived}

      {:error, :game_archived} =
        Core.transfer_ownership_to_player(game_archived, game_archived.owner.id, player2.id)
    end

    test "STALE-01: transfer_ownership_to_player/4 with lobby_only: true rejects non-lobby phases while preserving archive and owner precedence",
         %{game: game, owner: owner, player1: player1, player2: player2} do
      assert {:ok, transferred} =
               Core.transfer_ownership_to_player(game, owner.id, player1.id, lobby_only: true)

      assert transferred.owner.id == player1.id

      for status <- [:playing, :finished, :game_over] do
        state = %{game | status: status}

        assert {:error, :game_not_in_lobby} =
                 Core.transfer_ownership_to_player(state, owner.id, player2.id, lobby_only: true)

        assert {:error, :unauthorized} =
                 Core.transfer_ownership_to_player(state, player1.id, player2.id,
                   lobby_only: true
                 )
      end

      assert {:error, :game_archived} =
               Core.transfer_ownership_to_player(
                 %{game | status: :archived},
                 owner.id,
                 player1.id,
                 lobby_only: true
               )
    end
  end

  describe "authorize_settings_update/2 and update_settings/3" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      {:ok, game: game}
    end

    test "AC-04: authorize_settings_update/2 enforces owner and lobby state", %{
      game: game,
      owner: owner
    } do
      other = build_games_player("Other")

      assert :ok = Core.authorize_settings_update(game, owner.id)
      assert {:error, :unauthorized} = Core.authorize_settings_update(game, other.id)

      assert {:error, :unauthorized} =
               Core.authorize_settings_update(%{game | owner: nil}, owner.id)

      assert {:error, :game_not_in_lobby} =
               Core.authorize_settings_update(%{game | status: :playing}, owner.id)

      assert {:error, :game_not_in_lobby} =
               Core.authorize_settings_update(%{game | status: :archived}, owner.id)
    end

    test "AC-04: updates settings when called by owner in lobby with validated RoomSettings",
         %{game: game, owner: owner} do
      cat_1 = Ecto.UUID.generate()
      cat_2 = Ecto.UUID.generate()

      settings = %RoomSettings{
        name: "  New Game Name  ",
        max_players: 6,
        word_options: %WordOptions{language: "pt", category_ids: [cat_1, cat_2]}
      }

      assert {:ok, updated_game} = Core.update_settings(game, owner.id, settings)

      assert updated_game.name == "New Game Name"
      assert updated_game.max_players == 6
      assert updated_game.word_options.language == "pt"
      assert updated_game.word_options.category_ids == [cat_1, cat_2]
      assert updated_game.tick == game.tick + 1
      assert_last_events(updated_game, [%{type: :settings_updated}])
    end

    test "AC-04: returns {:error, :unauthorized} when called by a non-owner", %{game: game} do
      other = build_games_player("Other")
      settings = %RoomSettings{name: "Hijacked", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :unauthorized} = Core.update_settings(game, other.id, settings)
    end

    test "AC-04: returns {:error, :invalid_name} for blank, whitespace-only, or over-60-char name",
         %{game: game, owner: owner} do
      base = %RoomSettings{name: "Sala", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :invalid_name} = Core.update_settings(game, owner.id, %{base | name: "   "})

      assert {:error, :invalid_name} =
               Core.update_settings(game, owner.id, %{base | name: String.duplicate("a", 61)})
    end

    test "AC-04: returns {:error, :invalid_max_players} for max_players outside 2..6", %{
      game: game,
      owner: owner
    } do
      base = %RoomSettings{name: "Sala", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :invalid_max_players} =
               Core.update_settings(game, owner.id, %{base | max_players: 1})

      assert {:error, :invalid_max_players} =
               Core.update_settings(game, owner.id, %{base | max_players: 10})
    end

    test "EDGE-01: returns {:error, :invalid_max_players} when max_players is below current occupancy",
         %{game: game, owner: owner} do
      p1 = build_games_player("P1")
      p2 = build_games_player("P2")
      p3 = build_games_player("P3")

      {:ok, game} = Core.join_game(game, owner)
      {:ok, game} = Core.join_game(game, p1)
      {:ok, game} = Core.join_game(game, p2)
      {:ok, game} = Core.join_game(game, p3)

      settings = %RoomSettings{name: "Sala", max_players: 3, word_options: %WordOptions{}}
      assert {:error, :invalid_max_players} = Core.update_settings(game, owner.id, settings)
    end

    test "EDGE-02: rejects nil word_options or unsupported language", %{
      game: game,
      owner: owner
    } do
      nil_wo = %RoomSettings{name: "Sala", max_players: 4, word_options: nil}
      assert {:error, :invalid_word_options} = Core.update_settings(game, owner.id, nil_wo)

      bad_lang = %RoomSettings{
        name: "Sala",
        max_players: 4,
        word_options: %WordOptions{language: "es", category_ids: []}
      }

      assert {:error, :invalid_word_options} = Core.update_settings(game, owner.id, bad_lang)
    end

    test "AC-04: returns {:error, :game_not_in_lobby} when not in lobby state", %{
      game: game,
      owner: owner
    } do
      settings = %RoomSettings{name: "New Name", max_players: 6, word_options: %WordOptions{}}

      assert {:error, :game_not_in_lobby} =
               Core.update_settings(%{game | status: :playing}, owner.id, settings)

      assert {:error, :game_not_in_lobby} =
               Core.update_settings(%{game | status: :archived}, owner.id, settings)
    end
  end

  describe "to_game_summary/1" do
    setup %{owner: owner} do
      # Create a new game
      game = Core.new(owner, "Test Game", 4)

      {:ok, game: game}
    end

    test "returns a GameSummary struct", %{game: game} do
      summary = Core.to_game_summary(game)

      assert %Forka.Games.GameSummary{} = summary
    end
  end

  describe "join_room/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Sala de Teste", 2)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")
      {:ok, game: game, player1: player1, player2: player2, player3: player3}
    end

    test "REQ-05: returns {:ok, :joined, state} for new player in lobby with open seat", %{
      game: game,
      player1: player1
    } do
      assert {:ok, :joined, updated} = Core.join_room(game, player1)
      assert map_size(updated.game_players) == 1
      assert updated.tick == game.tick + 1
      assert_last_events(updated, [%{type: :player_joined, payload: %{player_id: player1.id}}])
    end

    test "REQ-05: returns {:ok, :already_joined, state} without duplicate event for existing lobby participant",
         %{
           game: game,
           player1: player1
         } do
      {:ok, :joined, joined_game} = Core.join_room(game, player1)
      joined_game = %{joined_game | events: []}

      assert {:ok, :already_joined, returned} = Core.join_room(joined_game, player1)
      assert returned.tick == joined_game.tick
      assert returned.events == []
      assert map_size(returned.game_players) == 1
    end

    test "REQ-04: returns {:error, :maximum_players} when lobby is full for a new player", %{
      game: game,
      player1: player1,
      player2: player2,
      player3: player3
    } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      assert {:error, :maximum_players} = Core.join_room(g2, player3)
    end

    test "REQ-05: returns {:ok, :returning_participant, state} for existing participant in playing or ended match",
         %{
           game: game,
           player1: player1,
           player2: player2
         } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      for status <- [:playing, :finished, :game_over] do
        in_match = %{g2 | status: status, events: []}
        assert {:ok, :returning_participant, returned} = Core.join_room(in_match, player1)
        assert returned.tick == in_match.tick
        assert returned.events == []
      end
    end

    test "REQ-04: returns {:error, :game_already_started} or {:error, :game_ended} for non-participant",
         %{
           game: game,
           player1: player1,
           player2: player2,
           player3: player3
         } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      assert {:error, :game_already_started} = Core.join_room(%{g2 | status: :playing}, player3)
      assert {:error, :game_ended} = Core.join_room(%{g2 | status: :finished}, player3)
      assert {:error, :game_ended} = Core.join_room(%{g2 | status: :game_over}, player3)
    end

    test "REQ-04: returns {:error, :game_archived} when game is archived", %{
      game: game,
      player1: player1
    } do
      assert {:error, :game_archived} = Core.join_room(%{game | status: :archived}, player1)
    end

    property "REQ-05: repeat join_room/2 leaves existing participant membership, events, and tick unchanged" do
      check all(
              max_players <- StreamData.integer(2..6),
              roster_size <- StreamData.integer(1..max_players),
              status <- StreamData.member_of([:lobby, :playing, :finished, :game_over]),
              pick_index <- StreamData.integer(0..(roster_size - 1))
            ) do
        owner = build_games_player("Owner")
        base = Core.new(owner, "Sala Propriedade", max_players)
        players = Enum.map(1..roster_size, &build_games_player("P#{&1}"))

        populated =
          Enum.reduce(players, base, fn player, acc ->
            {:ok, :joined, next} = Core.join_room(acc, player)
            next
          end)

        state = %{populated | status: status, events: []}
        existing = Enum.at(players, pick_index)
        expected_outcome = if status == :lobby, do: :already_joined, else: :returning_participant

        assert {:ok, ^expected_outcome, returned} = Core.join_room(state, existing)
        assert returned.game_players == state.game_players
        assert returned.tick == state.tick
        assert returned.events == []
      end
    end
  end

  describe "REQ-02: owner and phase authorization" do
    setup %{owner: owner} do
      game = Core.new(owner, "Sala Segura", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      outsider = build_games_player("Outsider")
      words = Enum.map(~w(cat dog cow pig hen fox), &Word.new(&1, "Animals"))

      {:ok, g1} = Core.join_game(game, owner)
      {:ok, g2} = Core.join_game(g1, player1)
      {:ok, g3} = Core.join_game(g2, player2)
      lobby_ready = Core.set_words(g3, words)

      %{
        owner: owner,
        player1: player1,
        player2: player2,
        outsider: outsider,
        lobby_ready: lobby_ready
      }
    end

    test "REQ-02: authorize_start/2 and start_game/2 enforce owner, lobby phase, and readiness",
         %{
           owner: owner,
           player1: player1,
           outsider: outsider,
           lobby_ready: lobby_ready
         } do
      assert :ok = Core.authorize_start(lobby_ready, owner.id)
      assert {:error, :unauthorized} = Core.authorize_start(lobby_ready, player1.id)
      assert {:error, :unauthorized} = Core.authorize_start(lobby_ready, outsider.id)
      assert {:error, :unauthorized} = Core.authorize_start(%{lobby_ready | owner: nil}, owner.id)

      assert {:error, :game_already_initialized} =
               Core.authorize_start(%{lobby_ready | status: :playing}, owner.id)

      assert {:error, :unauthorized} =
               Core.authorize_start(%{lobby_ready | status: :playing}, player1.id)

      assert {:error, :game_archived} =
               Core.authorize_start(%{lobby_ready | status: :archived}, owner.id)

      assert {:error, :unauthorized} = Core.start_game(lobby_ready, player1.id)
      assert {:error, :unauthorized} = Core.start_game(lobby_ready, outsider.id)

      assert {:ok, playing} = Core.start_game(lobby_ready, owner.id)
      assert playing.status == :playing
      assert playing.current_game_word_index == 0
      assert playing.current_game_player_index == 0

      assert {:error, :game_already_initialized} = Core.start_game(playing, owner.id)
      assert {:error, :unauthorized} = Core.start_game(playing, player1.id)
      assert {:error, :game_archived} = Core.start_game(%{playing | status: :archived}, owner.id)

      not_ready = Core.new(owner, "Sozinho", 4)
      {:ok, one_player} = Core.join_game(not_ready, owner)
      assert {:error, :game_not_ready} = Core.start_game(one_player, owner.id)
    end

    test "REQ-02: restart_game/2 enforces owner only and allows any non-playing, non-archived phase",
         %{
           owner: owner,
           player1: player1,
           outsider: outsider,
           lobby_ready: lobby_ready
         } do
      {:ok, playing} = Core.start_game(lobby_ready, owner.id)

      for status <- [:lobby, :playing, :finished, :game_over] do
        state = %{playing | status: status}
        assert {:error, :unauthorized} = Core.restart_game(state, player1.id)
        assert {:error, :unauthorized} = Core.restart_game(state, outsider.id)
        assert {:error, :unauthorized} = Core.restart_game(%{state | owner: nil}, owner.id)
      end

      assert {:error, :game_in_progress} = Core.restart_game(playing, owner.id)

      assert {:error, :game_archived} =
               Core.restart_game(%{playing | status: :archived}, owner.id)

      for status <- [:lobby, :finished, :game_over] do
        state = %{playing | status: status}
        assert {:ok, restarted} = Core.restart_game(state, owner.id)
        assert restarted.status == :lobby
        assert restarted.game_words == %{}
        assert restarted.current_game_player_index == nil
        assert restarted.current_game_word_index == nil
      end
    end

    test "REQ-02: transfer_ownership_to_player/3 enforces owner in any non-archived phase and participant target",
         %{
           owner: owner,
           player1: player1,
           player2: player2,
           outsider: outsider,
           lobby_ready: lobby_ready
         } do
      for status <- [:lobby, :playing, :finished, :game_over] do
        state = %{lobby_ready | status: status}

        assert {:error, :unauthorized} =
                 Core.transfer_ownership_to_player(state, player1.id, player2.id)

        assert {:error, :unauthorized} =
                 Core.transfer_ownership_to_player(state, outsider.id, player1.id)

        assert {:error, :unauthorized} =
                 Core.transfer_ownership_to_player(%{state | owner: nil}, owner.id, player1.id)

        assert {:ok, transferred} = Core.transfer_ownership_to_player(state, owner.id, player1.id)
        assert transferred.owner.id == player1.id
      end

      assert {:error, :already_owner} =
               Core.transfer_ownership_to_player(lobby_ready, owner.id, owner.id)

      assert {:error, :player_not_found} =
               Core.transfer_ownership_to_player(lobby_ready, owner.id, outsider.id)

      assert {:error, :game_archived} =
               Core.transfer_ownership_to_player(
                 %{lobby_ready | status: :archived},
                 owner.id,
                 player1.id
               )
    end

    test "REQ-02: archive_game/2 enforces owner and non-playing while archive_game/1 remains for system timeout",
         %{
           owner: owner,
           player1: player1,
           lobby_ready: lobby_ready
         } do
      assert {:error, :unauthorized} = Core.archive_game(lobby_ready, player1.id)
      assert {:error, :unauthorized} = Core.archive_game(%{lobby_ready | owner: nil}, owner.id)

      {:ok, playing} = Core.start_game(lobby_ready, owner.id)
      assert {:error, :unauthorized} = Core.archive_game(playing, player1.id)
      assert {:error, :game_in_progress} = Core.archive_game(playing, owner.id)

      assert {:ok, archived} = Core.archive_game(lobby_ready, owner.id)
      assert archived.status == :archived
      assert {:error, :game_archived} = Core.archive_game(archived, owner.id)

      assert {:ok, sys_archived} = Core.archive_game(%{playing | status: :finished})
      assert sys_archived.status == :archived
    end

    property "REQ-02: non-owners are always rejected with {:error, :unauthorized} on all owner commands in any non-archived phase" do
      check all(status <- StreamData.member_of([:lobby, :playing, :finished, :game_over])) do
        owner = build_games_player("Owner")
        seated = build_games_player("Seated")
        outsider = build_games_player("Outsider")
        word = Word.new("cat", "Animals", "Meows")

        game = Core.new(owner, "Prop Room", 4)
        {:ok, g1} = Core.join_game(game, owner)
        {:ok, g2} = Core.join_game(g1, seated)
        state = %{Core.set_words(g2, [word]) | status: status}
        settings = %RoomSettings{name: "Hijack", max_players: 4, word_options: %WordOptions{}}

        for actor <- [seated, outsider] do
          assert {:error, :unauthorized} = Core.start_game(state, actor.id)
          assert {:error, :unauthorized} = Core.restart_game(state, actor.id)

          assert {:error, :unauthorized} =
                   Core.transfer_ownership_to_player(state, actor.id, seated.id)

          assert {:error, :unauthorized} = Core.archive_game(state, actor.id)
          assert {:error, :unauthorized} = Core.update_settings(state, actor.id, settings)
        end
      end
    end
  end

  describe "reconcile_missing_players/2" do
    test "OWN-02: cold ownerless lobby promotes lowest seat and emits ownership_transferred_to" do
      owner = build_games_player("lia")
      p2 = build_games_player("bruno")
      p3 = build_games_player("caio")

      {:ok, g1} = Core.new(owner, "Sala", 4) |> Core.join_game(p2)
      {:ok, g2} = Core.join_game(g1, p3)
      ownerless = %{g2 | owner: nil}

      assert {:changed, reconciled} =
               Core.reconcile_missing_players(ownerless, [p2.id, p3.id])

      assert reconciled.status == :lobby
      assert reconciled.owner.id == p2.id
      assert reconciled.tick == ownerless.tick + 1
      assert Map.keys(reconciled.game_players) |> Enum.sort() == [0, 1]
      assert reconciled.game_players[0].player.id == p2.id
      assert reconciled.game_players[1].player.id == p3.id

      tick_events =
        reconciled.events
        |> Enum.filter(&(&1.tick == reconciled.tick))
        |> Enum.map(&{&1.type, &1.payload})

      assert tick_events == [
               {:ownership_transferred_to, %{from_player_id: nil, to_player_id: p2.id}}
             ]
    end

    test "OWN-02: cold ownerless empty room archives with nil owner" do
      owner = build_games_player("lia")
      ownerless_empty = %{Core.new(owner, "Vazia", 4) | owner: nil}

      assert {:changed, archived} = Core.reconcile_missing_players(ownerless_empty, [])

      assert archived.status == :archived
      assert archived.owner == nil
      assert archived.game_players == %{}
      assert archived.tick == ownerless_empty.tick + 1

      tick_events =
        archived.events
        |> Enum.filter(&(&1.tick == archived.tick))
        |> Enum.map(& &1.type)

      assert tick_events == [:game_archived]
    end

    test "OWN-02: running state with deleted owner drops owner, compacts seats, and promotes next seat" do
      owner = build_games_player("lia")
      p2 = build_games_player("bruno")
      p3 = build_games_player("caio")

      {:ok, g1} = Core.new(owner, "Ativa", 4) |> Core.join_game(owner)
      {:ok, g2} = Core.join_game(g1, p2)
      {:ok, g3} = Core.join_game(g2, p3)

      assert {:changed, reconciled} = Core.reconcile_missing_players(g3, [p2.id, p3.id])

      assert reconciled.status == :lobby
      assert reconciled.owner.id == p2.id
      assert Map.keys(reconciled.game_players) |> Enum.sort() == [0, 1]
      assert reconciled.game_players[0].player.id == p2.id
      assert reconciled.game_players[1].player.id == p3.id

      tick_types =
        reconciled.events
        |> Enum.filter(&(&1.tick == reconciled.tick))
        |> Enum.map(&{&1.type, &1.payload})

      assert {:player_left, %{player_id: owner.id}} in tick_types

      assert {:ownership_transferred_to, %{from_player_id: owner.id, to_player_id: p2.id}} in tick_types
    end

    test "OWN-02: running state with deleted solo owner drops owner and archives room" do
      owner = build_games_player("lia")
      {:ok, g1} = Core.new(owner, "Solo", 4) |> Core.join_game(owner)

      assert {:changed, archived} = Core.reconcile_missing_players(g1, [])

      assert archived.status == :archived
      assert archived.owner == nil
      assert archived.game_players == %{}

      tick_types =
        archived.events
        |> Enum.filter(&(&1.tick == archived.tick))
        |> Enum.map(& &1.type)

      assert :player_left in tick_types
      assert :game_archived in tick_types
    end

    test "OWN-02: running playing state with deleted owner compacts seats, promotes owner, and preserves or advances turn index" do
      owner = build_games_player("lia")
      p2 = build_games_player("bruno")
      p3 = build_games_player("caio")

      words =
        for text <- ~w(alfa bravo charlie delta echo foxtrot),
            do: Word.new(text, "Geral")

      {:ok, g1} = Core.new(owner, "Em Jogo", 4) |> Core.join_game(owner)
      {:ok, g2} = Core.join_game(g1, p2)
      {:ok, g3} = Core.join_game(g2, p3)
      {:ok, playing} = g3 |> Core.set_words(words) |> Core.start_game(owner.id)

      # Case A: deleted owner was current turn (index 0) -> p2 becomes owner and turn moves to seat 0 (p2)
      assert {:changed, reconciled_a} = Core.reconcile_missing_players(playing, [p2.id, p3.id])
      assert reconciled_a.status == :playing
      assert reconciled_a.owner.id == p2.id
      assert reconciled_a.current_game_player_index == 0
      assert Core.get_current_player(reconciled_a).id == p2.id

      # Case B: p3 (index 2) was current turn when owner (index 0) was deleted -> p3 stays current turn at new index 1
      playing_p3_turn = %{playing | current_game_player_index: 2}

      assert {:changed, reconciled_b} =
               Core.reconcile_missing_players(playing_p3_turn, [p2.id, p3.id])

      assert reconciled_b.status == :playing
      assert reconciled_b.owner.id == p2.id
      assert reconciled_b.current_game_player_index == 1
      assert Core.get_current_player(reconciled_b).id == p3.id

      # Case C: all players deleted while playing -> archived with nil indices
      assert {:changed, archived} = Core.reconcile_missing_players(playing, [])
      assert archived.status == :archived
      assert archived.owner == nil
      assert archived.current_game_player_index == nil
      assert archived.current_game_word_index == nil

      # Case D: a word finished by the deleted owner loses its finisher (FK to players);
      # a word finished by a kept player keeps it
      word0 = %{playing.game_words[0] | finished_by_id: owner.id}
      word1 = %{playing.game_words[1] | finished_by_id: p2.id}

      with_finishers = %{
        playing
        | game_words: playing.game_words |> Map.put(0, word0) |> Map.put(1, word1)
      }

      assert {:changed, healed} = Core.reconcile_missing_players(with_finishers, [p2.id, p3.id])
      assert healed.game_words[0].finished_by_id == nil
      assert healed.game_words[1].finished_by_id == p2.id
    end

    test "OWN-02: running state with deleted non-owner drops only that player and keeps owner; healthy or archived state is unchanged" do
      owner = build_games_player("lia")
      p2 = build_games_player("bruno")

      {:ok, g1} = Core.new(owner, "Ativa", 4) |> Core.join_game(owner)
      {:ok, g2} = Core.join_game(g1, p2)

      assert :unchanged = Core.reconcile_missing_players(g2, [owner.id, p2.id])

      assert :unchanged =
               Core.reconcile_missing_players(%{g2 | status: :archived, owner: nil}, [])

      # Healthy game with empty game_players (e.g. insert(:game)) stays unchanged when owner exists
      assert :unchanged = Core.reconcile_missing_players(Core.new(owner, "Nova", 4), [owner.id])

      assert {:changed, reconciled} = Core.reconcile_missing_players(g2, [owner.id])
      assert reconciled.owner.id == owner.id
      assert Map.keys(reconciled.game_players) == [0]
      assert reconciled.game_players[0].player.id == owner.id
    end

    property "OWN-02: after reconcile_missing_players/2, non-archived games always have an existing owner and only existing seated players" do
      check all(
              status <- StreamData.member_of([:lobby, :playing, :finished, :game_over]),
              player_count <- StreamData.integer(1..4),
              keep_mask <- StreamData.list_of(StreamData.boolean(), length: player_count),
              owner_nil? <- StreamData.boolean()
            ) do
        players = for idx <- 1..player_count, do: build_games_player("P#{idx}")
        [owner | _] = players

        state =
          Enum.reduce(players, Core.new(owner, "Prop", 4), fn p, acc ->
            {:ok, next} = Core.join_game(acc, p)
            next
          end)

        state = %{
          state
          | status: status,
            owner: if(owner_nil?, do: nil, else: owner),
            current_game_player_index: if(status == :playing, do: 0, else: nil),
            current_game_word_index: if(status == :playing, do: 0, else: nil)
        }

        existing_ids =
          players
          |> Enum.zip(keep_mask)
          |> Enum.filter(fn {_p, keep?} -> keep? end)
          |> Enum.map(fn {p, _} -> p.id end)

        existing_set = MapSet.new(existing_ids)

        final =
          case Core.reconcile_missing_players(state, existing_ids) do
            :unchanged -> state
            {:changed, updated} -> updated
          end

        seated_ids = final.game_players |> Map.values() |> Enum.map(& &1.player.id)
        assert Enum.all?(seated_ids, &MapSet.member?(existing_set, &1))

        if final.status == :archived do
          assert final.game_players == %{}
        else
          assert final.owner != nil
          assert MapSet.member?(existing_set, final.owner.id)
        end
      end
    end
  end
end
