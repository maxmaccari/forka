defmodule Forka.Games.Schemas.Event do
  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Guess
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.Game

  @event_types [
    :player_joined,
    :player_left,
    :players_shuffled,
    :words_set,
    :game_started,
    :player_guessed,
    :player_gave_up,
    :player_lost_life,
    :player_died,
    :player_scored,
    :next_player_turn,
    :word_completed,
    :moved_to_next_word,
    :ownership_transferred_to,
    :settings_updated,
    :game_finished,
    :game_over,
    :game_archived,
    :game_restarted
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :type, Ecto.Enum, values: @event_types
    field :payload, :map
    field :tick, :integer
    field :at, :utc_datetime

    belongs_to :game, Game

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :payload, :tick, :at])
    |> validate_required([:type, :tick, :at])
    |> validate_number(:tick, greater_than_or_equal_to: 0)
  end

  @doc false
  def new(type, tick, data \\ nil) do
    %__MODULE__{
      type: type,
      payload: to_payload(data),
      tick: tick,
      at: DateTime.utc_now()
    }
  end

  defp to_payload(nil), do: nil
  defp to_payload(%Player{id: id}), do: %{player_id: id}

  defp to_payload(%GameWord{word: word, finished_by_id: player_id}),
    do: %{player_id: player_id, word: word.text, category: word.category}

  defp to_payload(%Guess{guessed_by_player_id: player_id, letter: letter, correct?: correct?}),
    do: %{player_id: player_id, letter: letter, correct?: correct?}

  defp to_payload(map) when is_map(map), do: map

  @doc false
  def to_map(%__MODULE__{} = event) do
    %{
      id: event.id,
      type: event.type,
      payload: event.payload,
      tick: event.tick,
      at: event.at
    }
  end
end
