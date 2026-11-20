defmodule ForkaWeb.Admin.AdminLiveResourcesTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Testing
  alias ForkaWeb.Admin.AdminLive
  alias ForkaWeb.Admin.CategoryLive
  alias ForkaWeb.Admin.GameLive
  alias ForkaWeb.Admin.PlayerLive
  alias ForkaWeb.Admin.WordLive
  alias ForkaWeb.Router

  setup :register_and_log_in_admin

  describe "AC-01: admin layout shell and Backpex 0.24 preferences wiring" do
    test "renders a single #backpex-app-shell with preferences manifest on LiveResources and settings",
         %{
           conn: conn
         } do
      for path <- [
            Testing.path(Router, CategoryLive, :index),
            Testing.path(Router, WordLive, :index),
            Testing.path(Router, PlayerLive, :index),
            Testing.path(Router, AdminLive, :index),
            Testing.path(Router, GameLive, :index),
            ~p"/admin/settings"
          ] do
        {:ok, view, html} = live(conn, path)

        document = LazyHTML.from_document(html)
        assert LazyHTML.query(document, "#backpex-app-shell") |> Enum.count() == 1
        assert LazyHTML.query(document, "#backpex-preferences") |> Enum.count() == 1
        assert LazyHTML.query(document, "#backpex-sidebar") |> Enum.count() == 1

        assert has_element?(
                 view,
                 "#backpex-preferences[data-preferences-path='/admin/backpex_preferences'][data-preferences-manifest]"
               )

        assert has_element?(view, "#backpex-app-shell[data-sidebar-open='true']")
      end
    end
  end

  describe "AC-02: CategoryLive new, show, and edit views" do
    test "mounts new, show, and edit views and creates/updates a category with inline words", %{
      conn: conn
    } do
      category = insert(:category, name: "Animals", language: "en")
      word = insert(:word, category: category, text: "tiger", hint: "striped cat")

      {:ok, _show_view, show_html} =
        live(conn, Testing.path(Router, CategoryLive, :show, category))

      assert show_html =~ "Animals"
      assert show_html =~ "tiger"
      assert show_html =~ "striped cat"

      {:ok, edit_view, _edit_html} =
        live(conn, Testing.path(Router, CategoryLive, :edit, category))

      Testing.submit_form(edit_view, %{
        name: "Wild Animals",
        language: "en",
        words: %{"0" => %{"id" => word.id, "text" => "lion", "hint" => "king"}}
      })

      {redirect_path, _flash} = assert_redirect(edit_view)
      assert redirect_path == Testing.path(Router, CategoryLive, :index)

      {:ok, _index_view, index_html} = live(conn, redirect_path)
      assert index_html =~ "Wild Animals"

      {:ok, new_view, _new_html} = live(conn, Testing.path(Router, CategoryLive, :new))

      Testing.submit_form(new_view, %{
        name: "Fruits",
        language: "pt"
      })

      {new_redirect_path, _flash} = assert_redirect(new_view)
      assert new_redirect_path == Testing.path(Router, CategoryLive, :index)
    end
  end

  describe "AC-03: WordLive, PlayerLive, AdminLive, and GameLive views" do
    test "WordLive new, show, and edit views work end to end", %{conn: conn} do
      category = insert(:category, name: "Science", language: "en")
      word = insert(:word, category: category, text: "atom", hint: "basic unit")

      {:ok, _show_view, show_html} = live(conn, Testing.path(Router, WordLive, :show, word))
      assert show_html =~ "atom"
      assert show_html =~ "Science"

      {:ok, edit_view, _html} = live(conn, Testing.path(Router, WordLive, :edit, word))

      Testing.submit_form(edit_view, %{
        text: "molecule",
        hint: "bonded atoms",
        category_id: category.id
      })

      {path, _flash} = assert_redirect(edit_view)
      assert path == Testing.path(Router, WordLive, :index)

      {:ok, new_view, _html} = live(conn, Testing.path(Router, WordLive, :new))
      Testing.submit_form(new_view, %{text: "proton", hint: "positive", category_id: category.id})
      {new_path, _flash} = assert_redirect(new_view)
      assert new_path == Testing.path(Router, WordLive, :index)
    end

    test "PlayerLive index and edit views and GameLive index view render items", %{conn: conn} do
      player = insert(:player, username: "alice", email: "alice@example.com")
      _game = insert(:game, name: "Room 101", owner: player, status: :lobby)

      {:ok, _player_index, player_html} = live(conn, Testing.path(Router, PlayerLive, :index))
      assert player_html =~ "alice"

      {:ok, player_edit, _html} = live(conn, Testing.path(Router, PlayerLive, :edit, player))
      Testing.submit_form(player_edit, %{email: "alice_new@example.com"})
      {path, _flash} = assert_redirect(player_edit)
      assert path == Testing.path(Router, PlayerLive, :index)

      {:ok, _game_index, game_html} = live(conn, Testing.path(Router, GameLive, :index))
      assert game_html =~ "Room 101"
    end

    test "AdminLive new view renders password validation errors and creates an admin", %{
      conn: conn
    } do
      {:ok, new_view, _html} = live(conn, Testing.path(Router, AdminLive, :new))

      html =
        new_view
        |> form("#resource-form", change: %{email: "newadmin@example.com", password: "short"})
        |> render_change(%{"_target" => ["change", "password"]})

      assert html =~ "should be at least 12 character(s)"

      Testing.submit_form(new_view, %{
        email: "newadmin@example.com",
        password: "ValidPassword123!"
      })

      {path, _flash} = assert_redirect(new_view)
      assert path == Testing.path(Router, AdminLive, :index)
    end
  end

  describe "AC-04: compiled app.css contains Heroicons rules for Backpex and admin layout" do
    test "priv/static/assets/app.css defines heroicons mask utilities" do
      css_path = Path.join([Application.app_dir(:forka, "priv"), "static", "assets", "app.css"])
      css = File.read!(css_path)

      assert css =~ "--hero-book-open:"
      assert css =~ "--hero-bars-3-solid:"
      assert css =~ "--hero-user:"
      assert css =~ "--hero-swatch:"
    end
  end
end
