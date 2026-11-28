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
    assert LazyHTML.attribute(html_el, "data-forka-surface") == ["player"]
    assert LazyHTML.attribute(html_el, "data-theme") == []
    refute LazyHTML.text(LazyHTML.query(doc, "title")) =~ "Phoenix Framework"
    assert Enum.count(LazyHTML.query(doc, "[data-theme-toggle]")) == 1
    assert LazyHTML.text(LazyHTML.query(doc, "header")) =~ "Forka"
    refute Enum.empty?(LazyHTML.query(doc, ".text-ink"))
    assert Enum.empty?(LazyHTML.query(doc, ".text-zinc-900"))
    assert LazyHTML.text(LazyHTML.query(doc, "#client-error")) =~ "Sem conexão com a internet"

    assert LazyHTML.attribute(LazyHTML.query(doc, "#client-error button"), "aria-label") == [
             "fechar"
           ]
  end

  test "admin routes use dedicated admin_root layout without player theme toggle", %{conn: conn} do
    login_doc = conn |> get(~p"/admin/log_in") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.attribute(LazyHTML.query(login_doc, "html"), "lang") == ["en"]

    assert LazyHTML.attribute(LazyHTML.query(login_doc, "html"), "data-forka-surface") == [
             "admin"
           ]

    assert LazyHTML.attribute(LazyHTML.query(login_doc, "html"), "data-theme") == ["light"]
    assert Enum.empty?(LazyHTML.query(login_doc, "[data-theme-toggle]"))

    assert LazyHTML.text(LazyHTML.query(login_doc, "#client-error")) =~
             "We can't find the internet"

    assert LazyHTML.attribute(LazyHTML.query(login_doc, "#client-error button"), "aria-label") ==
             ["close"]

    %{conn: admin_conn} = register_and_log_in_admin(%{conn: conn})

    admin_doc =
      admin_conn |> get(~p"/admin/categories") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(admin_doc, "html"), "lang") == ["en"]

    assert LazyHTML.attribute(LazyHTML.query(admin_doc, "html"), "data-forka-surface") == [
             "admin"
           ]

    assert Enum.count(LazyHTML.query(admin_doc, "#backpex-app-shell")) == 1
    assert Enum.empty?(LazyHTML.query(admin_doc, "[data-theme-toggle]"))
  end

  test "REQ-03: player header renders pt-BR register and login links when logged out", %{
    conn: conn
  } do
    doc = home_document(conn)
    header = LazyHTML.query(doc, "header")

    assert LazyHTML.text(header) =~ "Criar conta"
    assert LazyHTML.text(header) =~ "Entrar"
    refute LazyHTML.text(header) =~ "Register"
    refute LazyHTML.text(header) =~ "Log in"
  end

  test "REQ-03: player header renders pt-BR account and logout links when logged in", %{
    conn: conn
  } do
    player = insert(:player)
    doc = conn |> log_in_player(player) |> home_document()
    header = LazyHTML.query(doc, "header")

    assert LazyHTML.text(header) =~ player.email
    assert LazyHTML.text(header) =~ "Minha conta"
    assert LazyHTML.text(header) =~ "Sair"
    refute LazyHTML.text(header) =~ "Settings"
    refute LazyHTML.text(header) =~ "Log out"
  end

  test "EDGE-02: app layout places sticky reserved #flash-group slot before main on player and headerless pages",
       %{conn: conn} do
    player_doc = home_document(conn)

    assert Enum.empty?(LazyHTML.query(player_doc, "main #flash-group"))
    assert Enum.count(LazyHTML.query(player_doc, "#flash-group + main")) == 1

    player_header = LazyHTML.query(player_doc, "header[data-player-header]")
    assert Enum.count(player_header) == 1

    header_class = List.first(LazyHTML.attribute(player_header, "class"), "")

    player_group_class =
      List.first(LazyHTML.attribute(LazyHTML.query(player_doc, "#flash-group"), "class"), "")

    assert header_class =~ "sticky"
    assert header_class =~ "top-0"
    assert header_class =~ "z-30"
    assert header_class =~ "h-16"

    assert player_group_class =~ "sticky"
    assert player_group_class =~ "top-[var(--flash-slot-top,0px)]"
    assert player_group_class =~ "pointer-events-none"
    assert player_group_class =~ "z-20"
    assert player_group_class =~ "h-24"
    assert player_group_class =~ "sm:h-16"

    admin_login_doc =
      conn |> get(~p"/admin/log_in") |> html_response(200) |> LazyHTML.from_document()

    assert Enum.empty?(LazyHTML.query(admin_login_doc, "header[data-player-header]"))
    assert Enum.empty?(LazyHTML.query(admin_login_doc, "main #flash-group"))
    assert Enum.count(LazyHTML.query(admin_login_doc, "#flash-group + main")) == 1

    admin_group_class =
      List.first(LazyHTML.attribute(LazyHTML.query(admin_login_doc, "#flash-group"), "class"), "")

    assert admin_group_class =~ "sticky"
    assert admin_group_class =~ "top-[var(--flash-slot-top,0px)]"
    assert admin_group_class =~ "pointer-events-none"
    refute admin_group_class =~ "top-16"
  end

  defp home_document(conn) do
    conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
  end
end
