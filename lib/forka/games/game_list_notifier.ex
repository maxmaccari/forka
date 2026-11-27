defmodule Forka.Games.GameListNotifier do
  @moduledoc "Publishes game list changes to subscribed clients."

  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Words
  alias Phoenix.PubSub

  @pubsub Forka.PubSub
  @topic "game_list"

  @doc """
  Subscribe to game list updates.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Unsubscribe from game list updates.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    PubSub.unsubscribe(@pubsub, @topic)
  end

  @doc """
  Broadcast an update to the game list with a specific action.
  """
  @spec broadcast_update(GameState.t(), atom()) :: :ok
  def broadcast_update(game_state, action \\ :updated) do
    fields = list_fields(game_state)
    {language, category_ids} = extract_word_options(game_state.word_options)

    category_names =
      category_ids
      |> Words.list_categories_by_ids()
      |> Enum.map(& &1.name)

    data =
      Map.merge(fields, %{
        owner_username: owner_username(game_state.owner),
        language: language,
        category_names: category_names,
        updated_at: DateTime.utc_now(),
        action: action
      })

    PubSub.broadcast!(@pubsub, @topic, {:game_list_updated, data})
  end

  @doc false
  @spec broadcast_update_if_changed(GameState.t(), GameState.t()) :: :ok
  def broadcast_update_if_changed(%GameState{} = previous, %GameState{} = saved) do
    if list_fields(previous) != list_fields(saved), do: broadcast_update(saved)
    :ok
  end

  defp list_fields(game_state) do
    {language, category_ids} = extract_word_options(game_state.word_options)

    %{
      id: game_state.id,
      name: game_state.name,
      status: game_state.status,
      player_count: map_size(game_state.game_players || %{}),
      max_players: game_state.max_players,
      owner: game_state.owner,
      word_options: %{language: language, category_ids: Enum.sort(category_ids)}
    }
  end

  defp extract_word_options(%WordOptions{language: lang, category_ids: ids}) do
    {lang || "en", ids || []}
  end

  defp extract_word_options(opts) when is_list(opts) do
    {Keyword.get(opts, :language, "en") || "en", Keyword.get(opts, :category_ids, []) || []}
  end

  defp extract_word_options(opts) when is_map(opts) do
    lang = Map.get(opts, :language) || Map.get(opts, "language") || "en"
    ids = Map.get(opts, :category_ids) || Map.get(opts, "category_ids") || []
    {lang, ids}
  end

  defp extract_word_options(_), do: {"en", []}

  defp owner_username(%{username: username}) when is_binary(username), do: username
  defp owner_username(_), do: nil

  @doc """
  Broadcast a game creation event.
  """
  @spec broadcast_created(GameState.t()) :: :ok
  def broadcast_created(game_state) do
    broadcast_update(game_state, :created)
  end
end
