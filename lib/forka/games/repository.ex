defmodule Forka.Games.Repository do
  @moduledoc "Loads and persists game state, players, and dictionary words for the Games context."

  import Ecto.Query

  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Repo
  alias Forka.Words
  alias Phoenix.PubSub

  @pubsub Forka.PubSub
  @topic "games"

  @doc """
  Returns a list of random words from the database.

  ## Parameters

    * `count` - The number of words to return (default: 5)
    * `opts` - Additional options:
      * `:language` - Filter words by category language (e.g., "en", "pt")
      * `:category_ids` - Filter words by specific category IDs (list)

  ## Examples

      iex> get_random_words(3)
      [%{text: "dog", hint: "Barks", category: "Animals", language: "en"}, ...]

      iex> get_random_words(5, language: "en")
      [%{text: "blue", hint: "Color of the sky", category: "Colors", language: "en"}, ...]

      iex> get_random_words(2, category_ids: ["uuid1", "uuid2"])
      [%{text: "cat", hint: "Meows", category: "Animals", language: "en"}, ...]

  ## Returns

  A list of Word structs with text, hint, category, and language fields.
  Returns fewer words than requested if not enough words match the filters.
  """
  @spec get_random_words(non_neg_integer(), WordOptions.t() | keyword() | map() | nil) :: [
          Word.t()
        ]
  def get_random_words(count \\ 5, word_options \\ %WordOptions{}) do
    %WordOptions{language: language, category_ids: category_ids} =
      WordOptions.normalize(word_options)

    Words.sample_distinct_playable_words(count,
      language: language,
      category_ids: category_ids
    )
    |> Enum.map(&Word.from_map/1)
  end

  @doc """
  Counts distinct playable dictionary words available for the given `word_options`.
  """
  @spec count_available_words(WordOptions.t() | keyword() | map() | nil) :: non_neg_integer()
  def count_available_words(word_options \\ %WordOptions{}) do
    %WordOptions{language: language, category_ids: category_ids} =
      WordOptions.normalize(word_options)

    Words.count_distinct_playable_words(
      language: language,
      category_ids: category_ids
    )
  end

  @doc """
  Gets a player by ID.

  ## Parameters

    * `id` - The UUID of the player to retrieve

  ## Examples

      iex> get_player("123e4567-e89b-12d3-a456-426614174000")
      %Player{}

      iex> get_player("nonexistent-uuid")
      nil

  ## Returns

  The Player struct if found, nil otherwise.
  """
  @spec get_player(Ecto.UUID.t()) :: Player.t() | nil
  def get_player(id) do
    Repo.get(Player, id)
  end

  @doc "Returns the subset of `player_ids` that still exist in persistence."
  @spec existing_player_ids([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def existing_player_ids([]), do: []

  def existing_player_ids(player_ids) when is_list(player_ids) do
    ids = Enum.uniq(player_ids)

    from(p in Player, where: p.id in ^ids, select: p.id)
    |> Repo.all()
  end

  @doc """
  Inserts a new game into the database with the given owner ID and parameters.

  ## Parameters

    * `owner_id` - The UUID of the player who will own the game
    * `params` - A map of parameters for the game (name, max_players, etc.)

  ## Examples

      iex> insert_game("123e4567-e89b-12d3-a456-426614174000", %{name: "My Game", max_players: 4})
      {:ok, %Game{}}

      iex> insert_game("123e4567-e89b-12d3-a456-426614174000", %{name: ""})
      {:error, changeset}

  ## Returns

  A tuple containing either:
  - `{:ok, game}` with the inserted game if successful
  - `{:error, changeset}` with the changeset containing errors if unsuccessful
  """
  @spec insert_game(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Game.t()} | {:error, Ecto.Changeset.t(Game.t())}
  def insert_game(owner_id, params, opts \\ []) when is_binary(owner_id) and is_map(params) do
    opts = Keyword.put_new(opts, :auto_join_owner, true)

    %Game{owner_id: owner_id}
    |> Game.insert_changeset(params, opts)
    |> Repo.insert()
    |> case do
      {:ok, game} ->
        broadcast_backoffice!(game, "backpex:created")

        {:ok, game}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns up to `limit` non-archived, ownerless game IDs matching `statuses`,
  prioritizing rooms with remaining players before empty rooms, newest first.
  """
  @spec list_ownerless_visible_game_ids([GameState.status()], pos_integer()) :: [Ecto.UUID.t()]
  def list_ownerless_visible_game_ids(statuses, limit)
      when is_list(statuses) and is_integer(limit) and limit > 0 do
    from(g in Game,
      left_join: gp in assoc(g, :game_players),
      where: g.status in ^statuses and is_nil(g.owner_id),
      group_by: [g.id, g.inserted_at],
      order_by: [desc: fragment("COUNT(?) > 0", gp.id), desc: g.inserted_at, desc: g.id],
      limit: ^limit,
      select: g.id
    )
    |> Repo.all()
  end

  @doc """
  Gets a game state from the database by its ID.

  This function retrieves a game by ID, preloads its associations,
  and converts it to a GameState struct.

  ## Parameters

    * `id` - The UUID of the game to retrieve

  ## Examples

      iex> get_game_state("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %GameState{}}

      iex> get_game_state("nonexistent-uuid")
      {:error, :not_found}

  ## Returns

  A tuple containing either:
  - `{:ok, game_state}` with the game state if found
  - `{:error, :not_found}` if the game does not exist
  """
  @game_preloads [{:game_players, :player}, :game_words, :owner, :events]
  @spec get_game_state(Ecto.UUID.t()) :: {:ok, GameState.t()} | {:error, :not_found}
  def get_game_state(id) when is_binary(id) do
    Repo.get(Game, id)
    |> Repo.preload(@game_preloads)
    |> case do
      nil -> {:error, :not_found}
      game -> {:ok, Game.to_game_state(game)}
    end
  end

  @doc "Persists the game state and broadcasts the saved game to the back office."
  @spec save_game_state(GameState.t()) ::
          {:ok, GameState.t()} | {:error, Ecto.Changeset.t(Game.t())}
  def save_game_state(%GameState{id: id} = game_state) do
    Repo.get(Game, id)
    |> Repo.preload(@game_preloads)
    |> Game.state_changeset(game_state)
    |> Repo.update()
    |> case do
      {:ok, game} ->
        broadcast_backoffice!(game, "backpex:updated")

        new_game_state =
          game
          |> Repo.preload(@game_preloads)
          |> Game.to_game_state()

        {:ok, new_game_state}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Atomically locks `id` in persistence, loads its state, evaluates `reconcile_fun`
  against the currently existing player IDs, and persists the reconciled state when changed.
  """
  @spec reconcile_game_state(
          Ecto.UUID.t(),
          (GameState.t(), [Ecto.UUID.t()] -> :unchanged | {:changed, GameState.t()})
        ) ::
          {:ok, :unchanged, GameState.t()}
          | {:ok, :reconciled, GameState.t(), GameState.t()}
          | {:error, :not_found | Ecto.Changeset.t(Game.t())}
  def reconcile_game_state(id, reconcile_fun)
      when is_binary(id) and is_function(reconcile_fun, 2) do
    Repo.transaction(fn -> reconcile_locked_game(id, reconcile_fun) end)
    |> handle_reconcile_result()
  end

  defp reconcile_locked_game(id, reconcile_fun) do
    case fetch_locked_game(id) do
      nil -> Repo.rollback(:not_found)
      %Game{status: :archived} = archived -> {:unchanged, Game.to_game_state(archived)}
      %Game{} = game -> apply_reconcile_fun(game, reconcile_fun)
    end
  end

  defp apply_reconcile_fun(%Game{} = game, reconcile_fun) do
    loaded_state = Game.to_game_state(game)
    existing_ids = loaded_state |> referenced_player_ids() |> existing_player_ids()

    case reconcile_fun.(loaded_state, existing_ids) do
      :unchanged -> {:unchanged, loaded_state}
      {:changed, updated_state} -> persist_reconciled_game(game, loaded_state, updated_state)
    end
  end

  defp persist_reconciled_game(game, loaded_state, updated_state) do
    case game |> Game.state_changeset(updated_state) |> Repo.update() do
      {:ok, saved_game} ->
        saved_state = saved_game |> Repo.preload(@game_preloads) |> Game.to_game_state()
        {:reconciled, saved_game, loaded_state, saved_state}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp handle_reconcile_result({:ok, {:unchanged, state}}), do: {:ok, :unchanged, state}

  defp handle_reconcile_result({:ok, {:reconciled, saved_game, previous_state, saved_state}}) do
    broadcast_backoffice!(saved_game, "backpex:updated")
    {:ok, :reconciled, previous_state, saved_state}
  end

  defp handle_reconcile_result({:error, reason}), do: {:error, reason}

  defp fetch_locked_game(id) do
    from(g in Game, where: g.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
    |> Repo.preload(@game_preloads)
  end

  defp referenced_player_ids(%GameState{owner: owner, game_players: game_players}) do
    seated_ids = Enum.map(game_players, fn {_idx, gp} -> gp.player.id end)

    case owner do
      %{id: owner_id} when is_binary(owner_id) -> [owner_id | seated_ids]
      _ -> seated_ids
    end
  end

  @doc """
  Similar to `save_game_state/1`, but raises an exception if the game state cannot be saved.

  ## Parameters

    * `game_state` - The GameState struct to save

  ## Examples

      iex> save_game_state!(%GameState{})
      %GameState{}

      iex> save_game_state!(%GameState{id: "invalid"})
      ** (Ecto.InvalidChangesetError)

  ## Returns

  The updated GameState if successful, otherwise raises an exception.
  """
  @spec save_game_state!(GameState.t()) :: GameState.t()
  def save_game_state!(%GameState{} = game_state) do
    case save_game_state(game_state) do
      {:ok, new_game_state} ->
        new_game_state

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
    end
  end

  defp broadcast_backoffice!(game, tagger) do
    PubSub.broadcast!(@pubsub, @topic, {tagger, game})
  end
end
