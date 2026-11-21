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
    ],
    on_mount: [{__MODULE__, :refresh_index}]

  alias Backpex.LiveResource.Index

  def on_mount(:refresh_index, _params, _session, %{view: __MODULE__.Index} = socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :refresh_game_index, :handle_info, &refresh_index/2)}
  end

  def on_mount(:refresh_index, _params, _session, socket), do: {:cont, socket}

  defp refresh_index({event, game}, socket)
       when event in ["backpex:created", "backpex:updated"] do
    # Backpex's create handler reruns the active query. Its update handler replaces visible rows in place.
    {:noreply, refreshed} = Index.handle_info({"backpex:created", game}, socket)

    {:halt, refreshed |> reconcile_selection() |> LiveResource.put_context()}
  end

  defp refresh_index(_message, socket), do: {:cont, socket}

  defp reconcile_selection(%{assigns: assigns} = socket) do
    selected_ids = MapSet.new(assigns.selected_items, & &1.id)
    selectable = Enum.filter(assigns.items, &can?(assigns, :delete, &1))
    selected = Enum.filter(selectable, &MapSet.member?(selected_ids, &1.id))

    socket =
      Phoenix.Component.assign(socket,
        selected_items: selected,
        select_all: selected != [] and length(selected) == length(selectable)
      )

    if length(selected) < MapSet.size(selected_ids) and
         not is_nil(assigns.action_to_confirm) and is_nil(assigns.row_action_items) do
      {:noreply, socket} = Index.handle_event("cancel-action-confirm", %{}, socket)
      socket
    else
      socket
    end
  end

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
