defmodule ForkaWeb.Admin.PlayerLive do
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
end
