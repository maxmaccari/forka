defmodule ForkaWeb.Filters.GameStatusSelect do
  @moduledoc false

  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Status"

  @impl Backpex.Filters.Select
  def prompt, do: "Select a status ..."

  @impl Backpex.Filters.Select
  def options do
    [
      {"Lobby", :lobby},
      {"Playing", :playing},
      {"Finished", :finished},
      {"Game Over", :game_over},
      {"Archived", :archived}
    ]
  end
end
