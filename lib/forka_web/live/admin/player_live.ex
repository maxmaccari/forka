defmodule ForkaWeb.Admin.PlayerLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Players.Player,
      repo: Forka.Repo,
      update_changeset: &Forka.Players.Player.email_changeset/3,
      create_changeset: &Forka.Players.Player.registration_changeset/3
    ],
    layout: {ForkaWeb.Layouts, :admin},
    pubsub: [
      name: Forka.PubSub,
      topic: "players",
      event_prefix: "player_"
    ]

  @impl Backpex.LiveResource
  def singular_name, do: "Player"

  @impl Backpex.LiveResource
  def plural_name, do: "Players"

  @impl Backpex.LiveResource
  def fields do
    [
      username: %{
        module: Backpex.Fields.Text,
        label: "Text",
        searchable: true
      },
      email: %{
        module: Backpex.Fields.Text,
        label: "Text",
        searchable: true
      }
    ]
  end
end
