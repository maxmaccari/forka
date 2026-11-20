defmodule ForkaWeb.Admin.AdminLiveResourcesTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Testing
  alias Forka.Games.Repository
  alias Forka.Words.Word
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

      {:ok, show_view, _show_html} =
        live(conn, Testing.path(Router, CategoryLive, :show, category))

      assert has_element?(show_view, "#backpex-main", "Animals")
      assert has_element?(show_view, "#backpex-main", "tiger")
      assert has_element?(show_view, "#backpex-main", "striped cat")

      {:ok, edit_view, _edit_html} =
        live(conn, Testing.path(Router, CategoryLive, :edit, category))

      Testing.submit_form(edit_view, %{
        name: "Wild Animals",
        language: "en",
        words: %{"0" => %{"id" => word.id, "text" => "lion", "hint" => "king"}}
      })

      {redirect_path, _flash} = assert_redirect(edit_view)
      assert redirect_path == Testing.path(Router, CategoryLive, :index)

      {:ok, index_view, _index_html} = live(conn, redirect_path)
      assert has_element?(index_view, "#row-item-#{category.id}", "Wild Animals")

      inline_word = Forka.Repo.get_by!(Word, category_id: category.id, text: "lion")
      assert inline_word.hint == "king"

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
      other_category = insert(:category, name: "History", language: "en")
      word = insert(:word, category: category, text: "atom", hint: "basic unit")

      {:ok, show_view, _show_html} = live(conn, Testing.path(Router, WordLive, :show, word))
      assert has_element?(show_view, "#backpex-main", "atom")
      assert has_element?(show_view, "#backpex-main", "Science")

      {:ok, edit_view, _html} = live(conn, Testing.path(Router, WordLive, :edit, word))

      Testing.submit_form(edit_view, %{
        text: "molecule",
        hint: "bonded atoms",
        category_id: other_category.id
      })

      {path, _flash} = assert_redirect(edit_view)
      assert path == Testing.path(Router, WordLive, :index)

      updated_word = Forka.Repo.get!(Word, word.id)
      assert updated_word.text == "molecule"
      assert updated_word.hint == "bonded atoms"
      assert updated_word.category_id == other_category.id

      {:ok, new_view, _html} = live(conn, Testing.path(Router, WordLive, :new))
      Testing.submit_form(new_view, %{text: "proton", hint: "positive", category_id: category.id})
      {new_path, _flash} = assert_redirect(new_view)
      assert new_path == Testing.path(Router, WordLive, :index)

      created_word = Forka.Repo.get_by!(Word, text: "proton")
      assert created_word.category_id == category.id
      assert created_word.hint == "positive"
    end

    test "PlayerLive index and edit views and GameLive index view render items", %{conn: conn} do
      player = insert(:player, username: "alice", email: "alice@example.com")
      game = insert(:game, name: "Room 101", owner: player, status: :lobby)

      {:ok, player_index, _player_html} = live(conn, Testing.path(Router, PlayerLive, :index))
      assert has_element?(player_index, "#row-item-#{player.id}", "alice")

      {:ok, player_edit, _html} = live(conn, Testing.path(Router, PlayerLive, :edit, player))
      Testing.submit_form(player_edit, %{email: "alice_new@example.com"})
      {path, _flash} = assert_redirect(player_edit)
      assert path == Testing.path(Router, PlayerLive, :index)

      {:ok, game_index, _game_html} = live(conn, Testing.path(Router, GameLive, :index))
      assert has_element?(game_index, "#row-item-#{game.id}", "Room 101")
    end

    test "AdminLive new view renders password validation errors and creates an admin", %{
      conn: conn
    } do
      {:ok, new_view, _html} = live(conn, Testing.path(Router, AdminLive, :new))

      new_view
      |> form("#resource-form", change: %{email: "newadmin@example.com", password: "short"})
      |> render_change(%{"_target" => ["change", "password"]})

      assert has_element?(new_view, "#resource-form", "should be at least 12 character(s)")

      Testing.submit_form(new_view, %{
        email: "newadmin@example.com",
        password: "ValidPassword123!"
      })

      {path, _flash} = assert_redirect(new_view)
      assert path == Testing.path(Router, AdminLive, :index)
    end
  end

  describe "F-01: GameLive index receives gameplay broadcasts" do
    test "a game inserted by Repository appears on the open index without reload", %{
      conn: conn
    } do
      owner = insert(:player)

      {:ok, view, _html} = live(conn, Testing.path(Router, GameLive, :index))
      refute has_element?(view, "tr[id^='row-item-']", "Live Room")

      {:ok, game} = Repository.insert_game(owner.id, %{name: "Live Room", max_players: 4})

      assert has_element?(view, "#row-item-#{game.id}", "Live Room")
    end

    test "a game saved by Repository updates its row on the open index without reload", %{
      conn: conn
    } do
      game = insert(:game, name: "Room 202", status: :lobby)

      {:ok, view, _html} = live(conn, Testing.path(Router, GameLive, :index))
      assert has_element?(view, "#row-item-#{game.id}", "Room 202")

      {:ok, game_state} = Repository.get_game_state(game.id)
      {:ok, _saved} = Repository.save_game_state(%{game_state | name: "Room 303"})

      assert has_element?(view, "#row-item-#{game.id}", "Room 303")
    end
  end
end
