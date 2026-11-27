defmodule ForkaWeb.Admin.PlayerLive do
  require Logger

  alias Forka.Backoffice.Admin
  alias Forka.Games
  alias Forka.Players.Player

  use Backpex.LiveResource,
    adapter_config: [
      schema: Player,
      repo: Forka.Repo,
      update_changeset: &Player.email_changeset/3,
      create_changeset: &Player.registration_changeset/3
    ],
    pubsub: [
      server: Forka.PubSub,
      topic: "players"
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {ForkaWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Player"

  @impl Backpex.LiveResource
  def plural_name, do: "Players"

  @impl Backpex.LiveResource
  def fields do
    [
      username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        searchable: true
      },
      email: %{
        module: Backpex.Fields.Text,
        label: "Email",
        searchable: true
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :show, _item), do: false
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, action, _item) when action in [:index, :edit, :delete], do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def on_item_deleting(%{assigns: %{current_admin: %Admin{}}}, %Player{id: player_id}) do
    case Games.remove_player_from_games(player_id) do
      :ok ->
        :ok

      {:error, {:removal_outcome_unknown, reason}} ->
        Logger.error(
          "Could not confirm removal of player #{player_id} from active games before deletion: #{inspect(reason)}"
        )

        {:error,
         "Account deletion stopped because room cleanup outcome could not be confirmed. Some rooms may already have changed."}

      {:error, reason} ->
        Logger.error(
          "Failed to remove player #{player_id} from active games before deletion: #{inspect(reason)}"
        )

        {:error,
         "Could not remove player from active rooms. Account deletion stopped. Some rooms may already have changed."}
    end
  end

  def on_item_deleting(_socket, _item) do
    {:error, "You are not authorized to delete players."}
  end
end
