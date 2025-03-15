defmodule ForkaWeb.CategoryLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Words.Category,
      repo: Forka.Repo,
      update_changeset: &Forka.Words.Category.changeset/3,
      create_changeset: &Forka.Words.Category.changeset/3
    ],
    layout: {ForkaWeb.Layouts, :admin},
    pubsub: [
      name: Forka.PubSub,
      topic: "categories",
      event_prefix: "category_"
    ]

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name"
      },
      language: %{
        module: Backpex.Fields.Select,
        label: "Language",
        options: [
          {"Portuguese", "pt"},
          {"English", "en"}
        ]
      }
    ]
  end
end
