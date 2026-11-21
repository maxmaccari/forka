defmodule ForkaWeb.Admin.CategoryLive do
  alias Forka.Words.Category

  use Backpex.LiveResource,
    adapter_config: [
      schema: Category,
      repo: Forka.Repo,
      update_changeset: &Category.changeset/3,
      create_changeset: &Category.changeset/3
    ],
    pubsub: [
      server: Forka.PubSub,
      topic: "categories"
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {ForkaWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      language: %{
        module: Backpex.Fields.Select,
        label: "Language",
        options: [
          {"Portuguese", "pt"},
          {"English", "en"}
        ]
      },
      words: %{
        module: Backpex.Fields.InlineCRUD,
        type: :assoc,
        label: "Words",
        child_fields: [
          text: %{
            module: Backpex.Fields.Text,
            label: "Text"
          },
          hint: %{
            module: Backpex.Fields.Text,
            label: "Hint"
          }
        ]
      }
    ]
  end

  @impl Backpex.LiveResource
  def filters do
    [
      language: %{
        module: ForkaWeb.Filters.CategoryLanguageSelect,
        label: "Language"
      }
    ]
  end
end
