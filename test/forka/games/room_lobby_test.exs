defmodule Forka.Games.RoomLobbyTest do
  use ExUnit.Case, async: true

  alias Forka.Games.Core
  alias Forka.Games.RoomLobby
  alias Forka.Games.Schemas.Word
  alias Forka.Players.Player, as: AuthPlayer
  alias Forka.Scope

  import Forka.TestHelpers

  defp scope_for(games_player) do
    Scope.for_player(%AuthPlayer{id: games_player.id, username: games_player.username})
  end

  describe "from_game_summary/5 and from_payload/2" do
    test "REQ-01 & REQ-04: projects owner_id, is_owner?, participant?, can_leave?, and empty_seats for owner, player, and outsider" do
      owner = build_games_player("lia")
      guest = build_games_player("bruno")
      outsider = build_games_player("caio")

      {:ok, state} =
        Core.new(owner, "Noite de palavras", 6, word_options: [language: "pt", category_ids: []])
        |> Core.join_game(owner)

      {:ok, state} = Core.join_game(state, guest)
      summary = Core.to_game_summary(state)
      payload = RoomLobby.payload(state, ["Música"], 10)

      # Keep payload.players exact shape (no extra keys leaked)
      assert payload.players == [
               %{id: owner.id, username: "lia"},
               %{id: guest.id, username: "bruno"}
             ]

      for lobby <- [
            RoomLobby.from_game_summary(scope_for(owner), state.id, summary, ["Música"], 10),
            RoomLobby.from_payload(scope_for(owner), payload)
          ] do
        assert lobby.owner_id == owner.id
        assert lobby.is_owner? == true
        assert lobby.participant? == true
        assert lobby.can_edit_settings? == true
        assert lobby.can_leave? == true
        assert lobby.empty_seats == 4
      end

      for lobby <- [
            RoomLobby.from_game_summary(scope_for(guest), state.id, summary, ["Música"], 10),
            RoomLobby.from_payload(scope_for(guest), payload)
          ] do
        assert lobby.owner_id == owner.id
        assert lobby.is_owner? == false
        assert lobby.participant? == true
        assert lobby.can_edit_settings? == false
        assert lobby.can_leave? == true
        assert lobby.empty_seats == 4
      end

      for lobby <- [
            RoomLobby.from_game_summary(scope_for(outsider), state.id, summary, ["Música"], 10),
            RoomLobby.from_payload(scope_for(outsider), payload)
          ] do
        assert lobby.owner_id == owner.id
        assert lobby.is_owner? == false
        assert lobby.participant? == false
        assert lobby.can_edit_settings? == false
        assert lobby.can_leave? == false
        assert lobby.empty_seats == 4
      end
    end

    test "EDGE-04 & REQ-08: reports zero empty_seats when full and disables leave/edit once playing" do
      owner = build_games_player("lia")
      guest = build_games_player("bruno")

      {:ok, state} =
        Core.new(owner, "Sala Cheia", 2, word_options: [language: "pt", category_ids: []])
        |> Core.join_game(owner)

      {:ok, full_state} = Core.join_game(state, guest)
      full_lobby = RoomLobby.from_payload(scope_for(owner), RoomLobby.payload(full_state, [], 4))
      assert full_lobby.empty_seats == 0
      assert full_lobby.can_leave? == true

      words =
        for word <- ~w(samba bossa frevo choro),
            do: Word.new(word, "Música", "Ritmo")

      {:ok, playing_state} =
        full_state
        |> Core.set_words(words)
        |> Core.start_game(owner.id)

      playing_payload = RoomLobby.payload(playing_state, [], nil)
      playing_summary = Core.to_game_summary(playing_state)

      for lobby <- [
            RoomLobby.from_game_summary(scope_for(owner), state.id, playing_summary, [], nil),
            RoomLobby.from_payload(scope_for(owner), playing_payload)
          ] do
        assert lobby.participant? == true
        assert lobby.is_owner? == true
        assert lobby.can_edit_settings? == false
        assert lobby.can_leave? == false
        assert lobby.empty_seats == 0
      end
    end
  end
end
