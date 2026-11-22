defmodule ForkaWeb.LayoutsTest do
  use ForkaWeb.ConnCase, async: false

  setup do
    previous = Application.fetch_env(:forka, :worktree)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:forka, :worktree, value)
        :error -> Application.delete_env(:forka, :worktree)
      end
    end)
  end

  test "the home page shows the configured worktree name and port", %{conn: conn} do
    Application.put_env(:forka, :worktree, %{name: "test-worktree", port: 4555})

    badge = conn |> home_document() |> LazyHTML.query("#worktree-badge")

    assert LazyHTML.text(badge) =~ "test-worktree"
    assert LazyHTML.text(badge) =~ ":4555"
  end

  test "the home page omits the badge without worktree configuration", %{conn: conn} do
    Application.delete_env(:forka, :worktree)

    assert Enum.empty?(LazyHTML.query(home_document(conn), "#worktree-badge"))
  end

  test "player root layout uses pt-BR, Forka title, theme toggle, and player header", %{
    conn: conn
  } do
    doc = home_document(conn)
    html_el = LazyHTML.query(doc, "html")

    assert LazyHTML.attribute(html_el, "lang") == ["pt-BR"]
    assert LazyHTML.attribute(html_el, "data-theme") == []
    refute LazyHTML.text(LazyHTML.query(doc, "title")) =~ "Phoenix Framework"
    assert Enum.count(LazyHTML.query(doc, "[data-theme-toggle]")) == 1
    assert LazyHTML.text(LazyHTML.query(doc, "header")) =~ "Forka"
  end

  test "admin routes use dedicated admin_root layout without player theme toggle", %{conn: conn} do
    login_doc = conn |> get(~p"/admin/log_in") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.attribute(LazyHTML.query(login_doc, "html"), "lang") == ["en"]
    assert LazyHTML.attribute(LazyHTML.query(login_doc, "html"), "data-theme") == ["light"]
    assert Enum.empty?(LazyHTML.query(login_doc, "[data-theme-toggle]"))

    %{conn: admin_conn} = register_and_log_in_admin(%{conn: conn})

    admin_doc =
      admin_conn |> get(~p"/admin/categories") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(admin_doc, "html"), "lang") == ["en"]
    assert Enum.count(LazyHTML.query(admin_doc, "#backpex-app-shell")) == 1
    assert Enum.empty?(LazyHTML.query(admin_doc, "[data-theme-toggle]"))
  end

  defp home_document(conn) do
    conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
  end
end
