defmodule Forka.Players do
  @moduledoc """
  The Players context.
  """

  import Ecto.Query, warn: false
  alias Forka.Repo

  alias Forka.Players.{Player, PlayerNotifier, PlayerToken}

  # Ecto.Multi.new/0 embeds an empty MapSet that Dialyzer sees as a literal on OTP 29.
  @dialyzer {:no_opaque,
             [
               player_email_multi: 3,
               confirm_player_multi: 1,
               update_player_password: 3
             ]}

  ## Database getters

  @doc """
  Gets a player by email.

  ## Examples

      iex> get_player_by_email("foo@example.com")
      %Player{}

      iex> get_player_by_email("unknown@example.com")
      nil

  """
  @spec get_player_by_email(String.t()) :: Player.t() | nil
  def get_player_by_email(email) when is_binary(email) do
    Repo.get_by(Player, email: email)
  end

  @doc """
  Gets a player by email and password.

  ## Examples

      iex> get_player_by_email_and_password("foo@example.com", "correct_password")
      %Player{}

      iex> get_player_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_player_by_email_and_password(String.t(), String.t()) :: Player.t() | nil
  def get_player_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    player = Repo.get_by(Player, email: email)
    if Player.valid_password?(player, password), do: player
  end

  @doc """
  Gets a player by email or username, and by password.

  ## Examples

      iex> get_player_by_credentials("foo@example.com", "correct_password")
      %Player{}

      iex> get_player_by_credentials("foo", "correct_password")
      %Player{}

      iex> get_player_by_credentials("foo@example.com", "invalid_password")
      nil

  """
  @spec get_player_by_credentials(String.t(), String.t()) :: Player.t() | nil
  def get_player_by_credentials(email_or_username, password)
      when is_binary(email_or_username) and is_binary(password) do
    query =
      from(p in Player, where: p.username == ^email_or_username or p.email == ^email_or_username)

    player = Repo.one(query)
    if Player.valid_password?(player, password), do: player
  end

  @doc """
  Gets a single player.

  Raises `Ecto.NoResultsError` if the Player does not exist.

  ## Examples

      iex> get_player!(123)
      %Player{}

      iex> get_player!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_player!(Ecto.UUID.t()) :: Player.t()
  def get_player!(id), do: Repo.get!(Player, id)

  ## Player registration

  @doc """
  Registers a player.

  ## Examples

      iex> register_player(%{field: value})
      {:ok, %Player{}}

      iex> register_player(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_player(map()) :: {:ok, Player.t()} | {:error, Ecto.Changeset.t(Player.t())}
  def register_player(attrs) do
    %Player{}
    |> Player.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking player changes.

  ## Examples

      iex> change_player_registration(player)
      %Ecto.Changeset{data: %Player{}}

  """
  @spec change_player_registration(Player.t(), map()) :: Ecto.Changeset.t(Player.t())
  def change_player_registration(%Player{} = player, attrs \\ %{}) do
    Player.registration_changeset(player, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the player email.

  ## Examples

      iex> change_player_email(player)
      %Ecto.Changeset{data: %Player{}}

  """
  @spec change_player_email(Player.t(), map()) :: Ecto.Changeset.t(Player.t())
  def change_player_email(player, attrs \\ %{}) do
    Player.email_changeset(player, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_player_email(player, "valid password", %{email: ...})
      {:ok, %Player{}}

      iex> apply_player_email(player, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  @spec apply_player_email(Player.t(), String.t(), map()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t(Player.t())}
  def apply_player_email(player, password, attrs) do
    player
    |> Player.email_changeset(attrs)
    |> Player.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the player email using the given token.

  If the token matches, the player email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  @spec update_player_email(Player.t(), String.t()) :: :ok | :error
  def update_player_email(player, token) do
    context = "change:#{player.email}"

    with {:ok, query} <- PlayerToken.verify_change_email_token_query(token, context),
         %PlayerToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(player_email_multi(player, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp player_email_multi(player, email, context) do
    changeset =
      player
      |> Player.email_changeset(%{email: email})
      |> Player.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:player, changeset)
    |> Ecto.Multi.delete_all(:tokens, PlayerToken.by_player_and_contexts_query(player, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given player.

  ## Examples

      iex> deliver_player_update_email_instructions(player, current_email, &url(~p"/players/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_player_update_email_instructions(Player.t(), String.t(), (String.t() ->
                                                                            String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_player_update_email_instructions(
        %Player{} = player,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, player_token} =
      PlayerToken.build_email_token(player, "change:#{current_email}")

    Repo.insert!(player_token)
    PlayerNotifier.deliver_update_email_instructions(player, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the player password.

  ## Examples

      iex> change_player_password(player)
      %Ecto.Changeset{data: %Player{}}

  """
  @spec change_player_password(Player.t(), map()) :: Ecto.Changeset.t(Player.t())
  def change_player_password(player, attrs \\ %{}) do
    Player.password_changeset(player, attrs, hash_password: false)
  end

  @doc """
  Updates the player password.

  ## Examples

      iex> update_player_password(player, "valid password", %{password: ...})
      {:ok, %Player{}}

      iex> update_player_password(player, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_player_password(Player.t(), String.t(), map()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t(Player.t())}
  def update_player_password(player, password, attrs) do
    changeset =
      player
      |> Player.password_changeset(attrs)
      |> Player.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:player, changeset)
    |> Ecto.Multi.delete_all(:tokens, PlayerToken.by_player_and_contexts_query(player, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, :player, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_player_session_token(Player.t()) :: binary()
  def generate_player_session_token(player) do
    {token, player_token} = PlayerToken.build_session_token(player)
    Repo.insert!(player_token)
    token
  end

  @doc """
  Gets the player with the given signed token.
  """
  @spec get_player_by_session_token(binary()) :: Player.t() | nil
  def get_player_by_session_token(token) do
    {:ok, query} = PlayerToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_player_session_token(binary()) :: :ok
  def delete_player_session_token(token) do
    Repo.delete_all(PlayerToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given player.

  ## Examples

      iex> deliver_player_confirmation_instructions(player, &url(~p"/players/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_player_confirmation_instructions(confirmed_player, &url(~p"/players/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  @spec deliver_player_confirmation_instructions(Player.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_player_confirmation_instructions(%Player{} = player, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if player.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, player_token} = PlayerToken.build_email_token(player, "confirm")
      Repo.insert!(player_token)

      PlayerNotifier.deliver_confirmation_instructions(
        player,
        confirmation_url_fun.(encoded_token)
      )
    end
  end

  @doc """
  Confirms a player by the given token.

  If the token matches, the player account is marked as confirmed
  and the token is deleted.
  """
  @spec confirm_player(String.t()) :: {:ok, Player.t()} | :error
  def confirm_player(token) do
    with {:ok, query} <- PlayerToken.verify_email_token_query(token, "confirm"),
         %Player{} = player <- Repo.one(query),
         {:ok, %{player: player}} <- Repo.transaction(confirm_player_multi(player)) do
      {:ok, player}
    else
      _ -> :error
    end
  end

  defp confirm_player_multi(player) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:player, Player.confirm_changeset(player))
    |> Ecto.Multi.delete_all(
      :tokens,
      PlayerToken.by_player_and_contexts_query(player, ["confirm"])
    )
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given player.

  ## Examples

      iex> deliver_player_reset_password_instructions(player, &url(~p"/players/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_player_reset_password_instructions(Player.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_player_reset_password_instructions(%Player{} = player, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, player_token} = PlayerToken.build_email_token(player, "reset_password")
    Repo.insert!(player_token)

    PlayerNotifier.deliver_reset_password_instructions(
      player,
      reset_password_url_fun.(encoded_token)
    )
  end

  @doc """
  Gets the player by reset password token.

  ## Examples

      iex> get_player_by_reset_password_token("validtoken")
      %Player{}

      iex> get_player_by_reset_password_token("invalidtoken")
      nil

  """
  @spec get_player_by_reset_password_token(String.t()) :: Player.t() | nil
  def get_player_by_reset_password_token(token) do
    with {:ok, query} <- PlayerToken.verify_email_token_query(token, "reset_password"),
         %Player{} = player <- Repo.one(query) do
      player
    else
      _ -> nil
    end
  end

  @doc """
  Resets the player password using the given reset token.

  Locks the player row first, then rebuilds and re-runs token verification
  inside the same transaction as the password update before deleting all tokens
  for the player. Returns `{:error, :invalid_token}` when the token is
  malformed, unknown, expired, already used, or invalidated by an email change.

  ## Examples

      iex> reset_player_password(token, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %Player{}}

      iex> reset_player_password(token, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

      iex> reset_player_password("invalid", %{password: "new long password", password_confirmation: "new long password"})
      {:error, :invalid_token}

  """
  @spec reset_player_password(String.t(), map()) ::
          {:ok, Player.t()} | {:error, :invalid_token | Ecto.Changeset.t(Player.t())}
  def reset_player_password(token, attrs) when is_binary(token) and is_map(attrs) do
    case PlayerToken.verify_email_token_query(token, "reset_password") do
      {:ok, discovery_query} ->
        Repo.transaction(fn -> reset_verified_player_password(token, discovery_query, attrs) end)

      :error ->
        {:error, :invalid_token}
    end
  end

  defp reset_verified_player_password(token, discovery_query, attrs) do
    # Lock the player row first (matching update_player_password/3 lock order),
    # then rebuild and run the verification query so expiry and sent_to are
    # evaluated after any lock wait.
    with %Player{id: player_id} <- Repo.one(discovery_query),
         %Player{} = _locked_player <- lock_player_for_update(player_id),
         {:ok, verified_query} <- PlayerToken.verify_email_token_query(token, "reset_password"),
         %Player{} = player <- Repo.one(verified_query) do
      apply_password_reset(player, attrs)
    else
      _ ->
        Repo.rollback(:invalid_token)
    end
  end

  defp lock_player_for_update(player_id) do
    from(p in Player, where: p.id == ^player_id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp apply_password_reset(player, attrs) do
    case player |> Player.password_changeset(attrs) |> Repo.update() do
      {:ok, updated_player} ->
        Repo.delete_all(PlayerToken.by_player_and_contexts_query(updated_player, :all))
        updated_player

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end
end
