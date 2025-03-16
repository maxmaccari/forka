defmodule ForkaWeb.Filters.CategoryLanguageSelect do
  @moduledoc false

  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Language"

  @impl Backpex.Filters.Select
  def prompt, do: "Select language ..."

  @impl Backpex.Filters.Select
  def options do
    [
      {"English", "en"},
      {"Portuguese", "pt"}
    ]
  end
end
