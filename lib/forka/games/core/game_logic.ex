defmodule Forka.Games.Core.GameLogic do
  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Guess
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.Word

  import Forka.Games.Core.Helpers

  @moduledoc "Handles turn order, guesses, and concessions once a game starts."

  # This module handles the logic after the game is initialized

  @doc false
  @spec get_current_player(GameState.t()) :: Player.t() | Ecto.Association.NotLoaded.t() | nil
  def get_current_player(%GameState{status: :playing} = game) do
    case Map.get(game.game_players, game.current_game_player_index) do
      %GamePlayer{player: player, status: :alive} ->
        player

      %GamePlayer{status: :dead} ->
        case find_next_alive_game_player_index(game, game.current_game_player_index) do
          nil -> nil
          index -> game.game_players[index].player
        end

      nil ->
        nil
    end
  end

  @doc false
  def get_current_player(%GameState{game_players: players, current_game_player_index: index}) do
    case Map.get(players, index) do
      %GamePlayer{player: player} -> player
      nil -> nil
    end
  end

  @doc false
  @spec give_up_game(GameState.t(), Ecto.UUID.t()) ::
          {:ok, GameState.t()}
          | {:error, :not_a_participant | :game_archived | :game_not_playing}
  def give_up_game(%GameState{status: :archived}, player_id) when is_binary(player_id),
    do: {:error, :game_archived}

  def give_up_game(%GameState{} = game_state, player_id) when is_binary(player_id) do
    case find_game_player_by_id(game_state, player_id) do
      nil ->
        {:error, :not_a_participant}

      {idx, game_player} ->
        if game_state.status == :playing do
          updated_player = GamePlayer.give_up(game_player)

          new_game_state =
            %{
              game_state
              | game_players: Map.put(game_state.game_players, idx, updated_player)
            }
            |> increment_tick()
            |> push_event(:player_gave_up, updated_player.player)

          {:ok, ensure_current_or_next_alive_player(new_game_state)}
        else
          {:error, :game_not_playing}
        end
    end
  end

  @doc false
  @spec guess(GameState.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, GameState.t()}
          | {:error,
             :not_a_participant
             | :not_player_turn
             | :game_archived
             | :game_not_playing
             | :letter_already_guessed}
  def guess(%GameState{status: :archived}, player_id, letter)
      when is_binary(player_id) and is_binary(letter),
      do: {:error, :game_archived}

  def guess(%GameState{} = game_state, player_id, letter)
      when is_binary(player_id) and is_binary(letter) do
    cond do
      not participant?(game_state, player_id) ->
        {:error, :not_a_participant}

      game_state.status != :playing ->
        {:error, :game_not_playing}

      not current_player?(game_state, player_id) ->
        {:error, :not_player_turn}

      true ->
        process_guess(game_state, player_id, letter)
    end
  end

  defp current_player?(game, player_id) do
    case get_current_player(game) do
      %Player{id: ^player_id} -> true
      _ -> false
    end
  end

  defp ensure_current_or_next_alive_player(game) do
    case Map.get(game.game_players, game.current_game_player_index) do
      %GamePlayer{status: :alive} -> game
      _ -> handle_next_player(game)
    end
  end

  defp find_next_alive_game_player_index(%GameState{game_players: players}, current_index)
       when map_size(players) > 0 and is_integer(current_index) do
    player_count = map_size(players)

    Enum.find_value(1..player_count, fn offset ->
      index = Integer.mod(current_index + offset, player_count)

      case Map.get(players, index) do
        %GamePlayer{status: :alive} -> index
        _ -> nil
      end
    end)
  end

  defp find_next_alive_game_player_index(_game, _current_index), do: nil

  defp game_over(game_state) do
    %{
      game_state
      | current_game_word_index: nil,
        current_game_player_index: nil,
        status: :game_over
    }
    |> push_event(:game_over)
  end

  defp process_guess(game_state, player_id, letter) do
    game_word = current_word(game_state)

    case GameWord.guess(game_word, letter, player_id) do
      {:ok, new_game_word, guess} ->
        updated_game_state =
          game_state
          |> increment_tick()
          |> ensure_current_or_next_alive_player()
          |> push_event(:player_guessed, guess)
          |> handle_guess_result(new_game_word, guess)

        {:ok, updated_game_state}

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
      game_state
      |> push_event(:word_completed, game_word)
      |> handle_word_completion()
    else
      game_state
    end
  end

  defp handle_player_score(
         %GameState{game_players: game_players, current_game_player_index: player_index} =
           game_state,
         %GameWord{word: word} = game_word,
         %Guess{letter: letter}
       ) do
    %GamePlayer{} = game_player = Map.get(game_players, player_index)
    base_score = Word.letters_count_in_word(word, letter) * 10

    {updated_player, score} =
      if GameWord.finished?(game_word) do
        score = base_score + Word.letters_count(word) * 10

        updated_game_player =
          game_player
          |> GamePlayer.add_score(score)
          |> GamePlayer.reset_lives()

        {updated_game_player, score}
      else
        {GamePlayer.add_score(game_player, base_score), base_score}
      end

    game_state
    |> update_game_player(player_index, updated_player)
    |> push_event(:player_scored, %{player_id: game_player.player.id, score: score})
  end

  defp reduce_player_lives(
         %GameState{game_players: game_players, current_game_player_index: player_index} =
           game_state
       ) do
    %GamePlayer{} = player = Map.get(game_players, player_index)
    updated_player = GamePlayer.decrement_lives(player)

    %{game_state | game_players: Map.put(game_players, player_index, updated_player)}
    |> process_reduce_player_lives_event(updated_player)
  end

  defp process_reduce_player_lives_event(
         %GameState{} = game_state,
         %GamePlayer{status: :dead, player: player}
       ) do
    # Player has died (ran out of lives)
    push_event(game_state, :player_died, player)
  end

  defp process_reduce_player_lives_event(
         %GameState{} = game_state,
         %GamePlayer{player: player}
       ) do
    # Player lost a life but is still alive
    push_event(game_state, :player_lost_life, player)
  end

  defp handle_word_completion(game_state) do
    if all_words_completed?(game_state) do
      finish_game(game_state)
    else
      assign_next_word(game_state)
    end
  end

  defp handle_next_player(%GameState{} = game_state) do
    case find_next_alive_game_player_index(game_state, game_state.current_game_player_index) do
      nil ->
        game_over(game_state)

      index ->
        %{game_state | current_game_player_index: index}
        |> push_event(:next_player_turn, game_state.game_players[index].player)
    end
  end

  defp update_game_state_with_guess(game_state, new_game_word) do
    %{
      game_state
      | game_words:
          Map.put(game_state.game_words, game_state.current_game_word_index, new_game_word)
    }
  end

  defp update_game_player(game_state, player_index, updated_player) do
    %{game_state | game_players: Map.put(game_state.game_players, player_index, updated_player)}
  end

  defp current_word(%GameState{game_words: game_words, current_game_word_index: word_index}) do
    Map.get(game_words, word_index)
  end

  defp all_words_completed?(%GameState{game_words: game_words}) do
    Enum.all?(game_words, fn {_index, word} -> GameWord.finished?(word) end)
  end

  defp finish_game(game_state) do
    %{game_state | status: :finished}
    |> push_event(:game_finished)
  end

  defp assign_next_word(game_state) do
    if all_words_completed?(game_state) do
      finish_game(game_state)
    else
      %{
        game_state
        | current_game_word_index: game_state.current_game_word_index + 1
      }
      |> push_event(:moved_to_next_word)
    end
  end
end
