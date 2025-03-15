defmodule Forka.Games.Game.GameLogic do
  alias Forka.Games.Word
  alias Forka.Games.Game.{GameState, GameWord, GamePlayer, Guess}

  import Forka.Games.Game.Helpers

  @moduledoc false

  # This module handles the logic after the game is initialized

  @finished_statuses ~w(finished game_over)a

  @doc false
  def get_current_player(%GameState{
        status: :playing,
        players: players,
        current_game_player_index: index
      }) do
    case Map.get(players, index) do
      %GamePlayer{player: player, status: :alive} ->
        player

      %GamePlayer{status: :dead} ->
        next_alive_player_index =
          find_next_alive_game_player_index(%GameState{players: players}, index - 1)

        case Map.get(players, next_alive_player_index) do
          %GamePlayer{player: player, status: :alive} -> player
          _ -> nil
        end

      nil ->
        nil
    end
  end

  def get_current_player(%GameState{players: players, current_game_player_index: index}) do
    case Map.get(players, index) do
      %GamePlayer{player: player} -> player
      nil -> nil
    end
  end

  @doc false
  def give_up_player(%GameState{status: :playing} = game_state, player_id)
      when is_binary(player_id) do
    case find_game_player_by_id(game_state, player_id) do
      {idx, game_player} ->
        updated_player = GamePlayer.give_up(game_player)
        new_game_state = %{game_state | players: Map.put(game_state.players, idx, updated_player)}

        {:ok, ensure_current_or_next_alive_player(new_game_state)}

      nil ->
        {:error, :player_not_found}
    end
  end

  def give_up_player(%GameState{status: :archived}, _player_id),
    do: {:error, :game_archived}

  def give_up_player(%GameState{}, player_id) when is_binary(player_id),
    do: {:error, :game_not_playing}

  def guess(%GameState{status: :playing} = game_state, player_id, letter)
      when is_binary(letter) and is_binary(player_id) do
    if current_player?(game_state, player_id) do
      game_state
      |> ensure_current_or_next_alive_player()
      |> process_guess(player_id, letter)
    else
      {:error, :not_player_turn}
    end
  end

  def guess(%GameState{status: :archived}, _player_id, _letter),
    do: {:error, :game_archived}

  def guess(%GameState{}, player_id, letter) when is_binary(letter) and is_binary(player_id),
    do: {:error, :game_not_playing}

  defp current_player?(game_state, player_id) do
    %GameState{players: players, current_game_player_index: player_index} = game_state
    %GamePlayer{player: player, status: status} = Map.get(players, player_index)

    if status == :alive do
      player.id == player_id
    else
      next_alive_player_index = find_next_alive_game_player_index(game_state, player_index)
      %GamePlayer{player: next_player} = Map.get(players, next_alive_player_index)

      next_player.id == player_id
    end
  end

  defp ensure_current_or_next_alive_player(
         %GameState{players: players, current_game_player_index: player_index} = game_state
       ) do
    %GamePlayer{status: status} = Map.get(players, player_index)

    cond do
      status == :alive ->
        game_state

      next_player_index = find_next_alive_game_player_index(game_state, player_index) ->
        %{game_state | current_game_player_index: next_player_index}

      # No player alive? It's game over.
      true ->
        game_over(game_state)
    end
  end

  defp find_next_alive_game_player_index(%GameState{players: players}, current_index) do
    player_count = map_size(players)

    Stream.iterate(current_index + 1, &(&1 + 1))
    |> Stream.map(&rem(&1, player_count))
    |> Enum.find(fn index ->
      %GamePlayer{status: status} = Map.get(players, index)
      status == :alive
    end)
  end

  defp game_over(game_state) do
    %{
      game_state
      | current_game_word_index: nil,
        current_game_player_index: nil,
        status: :game_over
    }
  end

  defp process_guess(%GameState{status: status} = game_state, _player_id, _letter)
       when status in @finished_statuses,
       do: {:ok, game_state}

  defp process_guess(game_state, player_id, letter) do
    game_word = current_word(game_state)

    case GameWord.guess(game_word, letter, player_id) do
      {:ok, new_game_word, guess} ->
        {:ok, handle_guess_result(game_state, new_game_word, guess)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_guess_result(game_state, new_game_word, %Guess{correct?: true} = guess) do
    game_state
    |> handle_player_score(new_game_word, guess)
    |> update_game_state_with_guess(new_game_word)
    |> maybe_handle_word_completion(new_game_word)
  end

  defp handle_guess_result(game_state, new_game_word, %Guess{correct?: false}) do
    game_state
    |> update_game_state_with_guess(new_game_word)
    |> reduce_player_lives()
    |> handle_next_player()
  end

  defp maybe_handle_word_completion(game_state, game_word) do
    if GameWord.finished?(game_word) do
      handle_word_completion(game_state)
    else
      game_state
    end
  end

  defp handle_player_score(
         %GameState{players: players, current_game_player_index: player_index} = game_state,
         %GameWord{word: word} = game_word,
         %Guess{letter: letter}
       ) do
    %GamePlayer{} = player = Map.get(players, player_index)
    base_score = Word.letters_count_in_word(word, letter) * 10

    updated_player =
      if GameWord.finished?(game_word) do
        score = base_score + 50 + Word.letters_count(word) * 10

        player
        |> GamePlayer.add_score(score)
        |> GamePlayer.reset_lives()
      else
        GamePlayer.add_score(player, base_score)
      end

    update_game_player(game_state, player_index, updated_player)
  end

  defp reduce_player_lives(
         %GameState{players: players, current_game_player_index: player_index} = game_state
       ) do
    %GamePlayer{} = player = Map.get(players, player_index)
    updated_player = GamePlayer.decrement_lives(player)

    %{game_state | players: Map.put(players, player_index, updated_player)}
  end

  defp handle_word_completion(game_state) do
    if all_words_completed?(game_state) do
      finish_game(game_state)
    else
      assign_next_word(game_state)
    end
  end

  defp handle_next_player(%GameState{} = game_state) do
    if all_players_died?(game_state) do
      game_over(game_state)
    else
      next_alive_player(game_state)
    end
  end

  defp all_players_died?(%GameState{players: players}) do
    players
    |> Map.values()
    |> Enum.all?(&GamePlayer.died?/1)
  end

  defp next_alive_player(
         %GameState{players: players, current_game_player_index: player_index} = game_state
       ) do
    player_count = map_size(players)
    next_index = rem(player_index + 1, player_count)
    new_game_state = %{game_state | current_game_player_index: next_index}

    case Map.get(players, next_index) do
      %GamePlayer{status: :alive} ->
        new_game_state

      %GamePlayer{status: :dead} when next_index < player_count ->
        next_alive_player(new_game_state)

      _ ->
        # As a fallback, unless this it can make it stuck in an infinite loop
        game_over(new_game_state)
    end
  end

  defp update_game_state_with_guess(game_state, new_game_word) do
    %{
      game_state
      | words: Map.put(game_state.words, game_state.current_game_word_index, new_game_word)
    }
  end

  defp update_game_player(game_state, player_index, updated_player) do
    %{game_state | players: Map.put(game_state.players, player_index, updated_player)}
  end

  defp current_word(%GameState{words: words, current_game_word_index: word_index}) do
    Map.get(words, word_index)
  end

  defp all_words_completed?(%GameState{words: words}) do
    Enum.all?(words, fn {_index, word} -> GameWord.finished?(word) end)
  end

  defp finish_game(game_state) do
    %{game_state | status: :finished}
  end

  defp assign_next_word(game_state) do
    if all_words_completed?(game_state) do
      finish_game(game_state)
    else
      %{
        game_state
        | current_game_word_index: game_state.current_game_word_index + 1
      }
    end
  end
end
