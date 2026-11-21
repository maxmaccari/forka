defmodule ForkaWeb.Admin.GameLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Games.Schemas.Game,
      repo: Forka.Repo,
      update_changeset: &Forka.Games.Schemas.Game.update_changeset/3,
      create_changeset: &Forka.Games.Schemas.Game.insert_changeset/3
    ],
    pubsub: [
      server: Forka.PubSub,
      topic: "games"
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {ForkaWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Game"

  @impl Backpex.LiveResource
  def plural_name, do: "Games"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        options: [
          {"Lobby", :lobby},
          {"Playing", :playing},
          {"Finished", :finished},
          {"Game Over", :game_over},
          {"Archived", :archived}
        ],
        searchable: true
      },
      max_players: %{
        module: Backpex.Fields.Number,
        label: "Max Players"
      },
      owner: %{
        module: Backpex.Fields.BelongsTo,
        label: "Owner",
        display_field: :username,
        searchable: true
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At"
      },
      updated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Updated At"
      }
    ]
  end

  @impl Backpex.LiveResource
  def filters do
    [
      status: %{
        module: ForkaWeb.Filters.GameStatusSelect,
        label: "Status"
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(_assigns, action, _item) when action in [:index], do: true
  def can?(_assigns, :delete, %{status: :archived}), do: true
  def can?(_assigns, _action, _item), do: false
end
