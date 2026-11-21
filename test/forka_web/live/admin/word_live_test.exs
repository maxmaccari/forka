defmodule ForkaWeb.Admin.WordLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Forka.Repo
  alias Forka.Words.Word
  alias ForkaWeb.Admin.WordLive

  setup :register_and_log_in_admin

  @tag audit_f03: true
  test "F-03 creates a word in the category selected in the admin form", %{conn: conn} do
    category = insert(:category, name: "Birds")
    {:ok, view, _html} = live(conn, ~p"/admin/words/new")

    view
    |> form("#resource-form", %{
      "change" => %{"text" => "Swallow", "category_id" => category.id}
    })
    |> render_submit(%{"save-type" => "save"})

    assert %Word{text: "swallow", category_id: category_id} =
             Repo.get_by(Word, text: "swallow")

    assert category_id == category.id
  end

  @tag audit_f03: true
  test "F-03 changes the category of an existing word", %{conn: conn} do
    original = insert(:category, name: "Birds")
    destination = insert(:category, name: "Animals")
    word = Repo.insert!(%Word{text: "swallow", category_id: original.id})
    {:ok, view, _html} = live(conn, ~p"/admin/words/#{word.id}/edit")

    view
    |> form("#resource-form", %{
      "change" => %{"text" => "swallow", "category_id" => destination.id}
    })
    |> render_submit(%{"save-type" => "save"})

    assert Repo.get!(Word, word.id).category_id == destination.id
  end

  @tag audit_f03: true
  test "F-03 the standalone admin changeset requires a selected category" do
    changeset_fun = WordLive.config(:adapter_config)[:create_changeset]
    changeset = changeset_fun.(%Word{}, %{"text" => "Swallow", "category_id" => ""}, [])

    refute changeset.valid?
    assert {"can't be blank", [validation: :required]} = changeset.errors[:category_id]
  end
end
