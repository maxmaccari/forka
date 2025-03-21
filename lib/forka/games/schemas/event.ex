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
    :game_started,
    :player_guessed,
    :player_gave_up,
    :player_lost_life,
    :player_died,
    :player_scored,
    :next_player_turn,
    :ownership_transferred_to,
    :settings_updated,
    :game_finished,
    :game_over,
    :game_archived,
    :game_restarted
  ]

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
    |> cast(attrs, [:type, :payload, :tick])
    |> validate_required([:type, :tick])
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

  # @doc """
  # Converts the last_event tuple into a human-readable description.

  # ## Parameters
  #   - game_state: The current GameState struct

  # ## Returns
  #   - A string with a friendly description of the last event
  #   - nil if there's no last event
  # """
  # def last_event_description(%GameState{last_event: nil}), do: nil

  # def last_event_description(%GameState{last_event: {:player_joined, player}}) do
  #   "#{player.username} joined the game"
  # end

  # def last_event_description(%GameState{last_event: {:player_left, player}}) do
  #   "#{player.username} left the game"
  # end

  # def last_event_description(%GameState{last_event: {:game_started, _owner}}) do
  #   "Game started"
  # end

  # def last_event_description(%GameState{
  #       last_event: {:player_guessed, %Guess{letter: letter, correct?: true}}
  #     }) do
  #   "Player correctly guessed the letter '#{letter}'"
  # end

  # def last_event_description(%GameState{
  #       last_event: {:player_guessed, %Guess{letter: letter, correct?: false}}
  #     }) do
  #   "Player incorrectly guessed the letter '#{letter}'"
  # end

  # def last_event_description(%GameState{last_event: {:player_gave_up, player}}) do
  #   "#{player.username} gave up"
  # end

  # def last_event_description(%GameState{last_event: {:ownership_transferred_to, player}}) do
  #   "Game ownership transferred to #{player.username}"
  # end

  # def last_event_description(%GameState{last_event: :game_archived}) do
  #   "Game was archived"
  # end

  # def last_event_description(%GameState{last_event: :game_restarted}) do
  #   "Game was restarted"
  # end

  # def last_event_description(%GameState{last_event: {:settings_updated, settings}}) do
  #   settings_description =
  #     Enum.map_join(settings, ", ", fn {key, value} ->
  #       case key do
  #         :max_players ->
  #           "maximum players set to #{value}"

  #         :word_options ->
  #           options =
  #             Enum.map_join(value, ", ", fn {opt_key, opt_val} ->
  #               case opt_key do
  #                 :language -> "language changed to #{opt_val}"
  #                 :category_ids -> "categories updated"
  #                 _ -> "#{opt_key} changed"
  #               end
  #             end)

  #           options

  #         _ ->
  #           "#{key} updated"
  #       end
  #     end)

  #   "Game settings were updated: #{settings_description}"
  # end

  # # Fallback for any unhandled event types
  # def last_event_description(%GameState{last_event: event}) do
  #   "Unknown event: #{inspect(event)}"
  # end
end
