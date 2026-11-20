defmodule ForkaWeb.Admin.WordLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Words.Word,
      repo: Forka.Repo,
      update_changeset: &Forka.Words.Word.changeset/3,
      create_changeset: &Forka.Words.Word.changeset/3
    ],
    layout: {ForkaWeb.Layouts, :admin},
    pubsub: [
      server: Forka.PubSub,
      topic: "words"
    ]

  @impl Backpex.LiveResource
  def singular_name, do: "Word"

  @impl Backpex.LiveResource
  def plural_name, do: "Words"

  @impl Backpex.LiveResource
  def fields do
    [
      text: %{
        module: Backpex.Fields.Text,
        label: "Text",
        searchable: true
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: ForkaWeb.Admin.CategoryLive
      },
      hint: %{
        module: Backpex.Fields.Text,
        label: "Hint",
        searchable: true
      }
    ]
  end

  @impl Backpex.LiveResource
  def filters do
    [
      category_id: %{
        module: ForkaWeb.Filters.WordLanguageSelect,
        label: "Category"
      }
    ]
  end
end
