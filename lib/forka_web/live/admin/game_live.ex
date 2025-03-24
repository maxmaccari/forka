defmodule ForkaWeb.Admin.GameLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Games.Schemas.Game,
      repo: Forka.Repo,
      update_changeset: &Forka.Games.Schemas.Game.update_changeset/3,
      create_changeset: &Forka.Games.Schemas.Game.insert_changeset/3
    ],
    layout: {ForkaWeb.Layouts, :admin},
    pubsub: [
      name: Forka.PubSub,
      topic: "games",
      event_prefix: "game_"
    ]

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

  @impl Phoenix.LiveView
  def handle_info({"game_created", item}, socket) do
    item = Forka.Repo.preload(item, [{:game_players, :player}, :owner])
    socket = update(socket, :items, fn items -> [item | items] end)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({"game_updated", item}, socket) do
    item = Forka.Repo.preload(item, [{:game_players, :player}, :owner])

    socket =
      update(socket, :items, fn items ->
        Enum.map(items, fn existing_item ->
          if existing_item.id == item.id do
            item
          else
            existing_item
          end
        end)
      end)

    {:noreply, socket}
  end
end
