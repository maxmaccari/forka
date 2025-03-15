defmodule ForkaWeb.Filters.WordLanguageSelect do
  @moduledoc false
  use Backpex.Filters.MultiSelect

  alias Forka.Words.Category
  alias Forka.Repo

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options do
    query =
      from c in Category,
        select: {fragment("? || ' (' || ? || ')'", c.name, c.language), c.id}

    Repo.all(query)
  end
end
