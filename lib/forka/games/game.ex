defmodule Forka.Games.Game do
  alias Forka.Games.Player

  defstruct id: nil,
            name: nil,
            words: %{},
            max_players: 0,
            players: %{},
            status: :lobby,
            current_player_id: nil,
            current_word_index: nil,
            current_guesses: nil,
            history: []

  # TODO: Add GameWord struct that hold the word status and guesses;
  # TODO: Add GamePlayer that hold the player score;

  def new(name, max_players) when is_binary(name) and is_integer(max_players) do
    %__MODULE__{
      id: UUID.uuid4(),
      name: name,
      max_players: max_players
    }
  end

  def add_player(%__MODULE__{players: players} = game, %Player{} = player) do
    new_players = add_player_to_map(players, player)

    if map_size(new_players) <= game.max_players do
      {:ok, %{game | players: new_players}}
    else
      {:error, :maximum_players}
    end
  end

  defp add_player_to_map(%{} = players, %Player{} = player) do
    [player_with_zero_score(player) | Map.values(players)]
    |> Enum.uniq_by(& &1.id)
    |> Enum.shuffle()
    |> Enum.with_index()
    |> Enum.map(fn {value, key} -> {key, value} end)
    |> Enum.into(%{})
  end

  defp player_with_zero_score(%Player{} = player), do: %{player | score: 0}

  def set_words(%__MODULE__{} = game, words) when is_list(words) do
    new_words =
      words
      |> Enum.uniq_by(& &1.word)
      |> Enum.shuffle()
      |> Enum.with_index()
      |> Enum.map(fn {value, key} -> {key, value} end)
      |> Enum.into(%{})

    {:ok, %{game | words: new_words}}
  end

  def init_game(%__MODULE__{status: :lobby} = game) do
    if can_start?(game) do
      {:ok, %{game | status: :playing}}
    else
      {:error, :game_not_ready}
    end
  end

  def init_game(%__MODULE__{}), do: {:error, :game_already_initialized}

  defp can_start?(%__MODULE__{} = game),
    do: map_size(game.players) >= 2 && map_size(game.words) >= 1
end
