defmodule Forka.Games.Schemas.GamePlayerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.Player

  import Ecto.Changeset, only: [get_field: 2]

  defp build_game_player(attrs \\ %{}) do
    player = %Player{id: UUID.uuid4(), username: "Lia"}
    Map.merge(GamePlayer.new(player), attrs)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "decrement_lives/1" do
    test "R-01: takes exactly six misses to eliminate a player and never leaves alive at zero" do
      gp = build_game_player()
      assert gp.lives == 6
      assert gp.status == :alive
      assert GamePlayer.alive?(gp)
      refute GamePlayer.died?(gp)

      {trace, after_five} =
        Enum.map_reduce(1..5, gp, fn _miss, acc ->
          next = GamePlayer.decrement_lives(acc)
          {{next.lives, next.status}, next}
        end)

      assert trace == [{5, :alive}, {4, :alive}, {3, :alive}, {2, :alive}, {1, :alive}]
      assert after_five.lives == 1
      assert after_five.status == :alive

      eliminated = GamePlayer.decrement_lives(after_five)
      assert eliminated.lives == 0
      assert eliminated.status == :dead
      assert GamePlayer.died?(eliminated)
      refute GamePlayer.alive?(eliminated)

      # Further misses while dead are a no-op
      assert GamePlayer.decrement_lives(eliminated) == eliminated
    end

    test "R-01: eliminates an alive player with non-positive lives instead of leaving alive" do
      at_zero = build_game_player(%{status: :alive, lives: 0})
      assert %{status: :dead, lives: 0} = GamePlayer.decrement_lives(at_zero)

      negative = build_game_player(%{status: :alive, lives: -1})
      assert %{status: :dead, lives: 0} = GamePlayer.decrement_lives(negative)
    end
  end

  describe "add_score/2, give_up/1, and reset_lives/1" do
    test "R-01: locks score once eliminated and restores 6 alive tries on reset_lives/1" do
      gp =
        build_game_player()
        |> GamePlayer.add_score(40)

      assert gp.score == 40

      eliminated = Enum.reduce(1..6, gp, fn _, acc -> GamePlayer.decrement_lives(acc) end)
      assert eliminated.status == :dead
      assert eliminated.lives == 0
      assert eliminated.score == 40

      assert GamePlayer.add_score(eliminated, 100).score == 40

      given_up = build_game_player(%{score: 30}) |> GamePlayer.give_up()
      assert given_up.status == :dead
      assert given_up.lives == 0
      assert GamePlayer.add_score(given_up, 50).score == 30

      healed = GamePlayer.reset_lives(eliminated)
      assert healed.status == :alive
      assert healed.lives == 6
      assert healed.score == 40
    end
  end

  describe "changeset/2" do
    test "R-01: accepts valid alive (1..6) and eliminated (0) rope states" do
      player_id = UUID.uuid4()

      for lives <- 1..6 do
        changeset =
          GamePlayer.changeset(%GamePlayer{}, %{
            player_id: player_id,
            status: :alive,
            lives: lives,
            score: 20
          })

        assert changeset.valid?, "expected alive with #{lives} lives to be valid"
        assert get_field(changeset, :lives) == lives
        assert get_field(changeset, :status) == :alive
      end

      dead_changeset =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :dead,
          lives: 0,
          score: 40
        })

      assert dead_changeset.valid?
      assert get_field(dead_changeset, :lives) == 0
      assert get_field(dead_changeset, :status) == :dead
    end

    test "R-01: rejects alive at 0 lives, dead with positive lives, out-of-range lives, and negative score" do
      player_id = UUID.uuid4()

      alive_zero =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :alive,
          lives: 0,
          score: 0
        })

      refute alive_zero.valid?
      assert errors_on(alive_zero) == %{lives: ["must be greater than 0 while player is alive"]}

      dead_positive =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :dead,
          lives: 2,
          score: 0
        })

      refute dead_positive.valid?
      assert errors_on(dead_positive) == %{lives: ["must be 0 when player is eliminated"]}

      too_many_lives =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :alive,
          lives: 7,
          score: 0
        })

      refute too_many_lives.valid?
      assert errors_on(too_many_lives) == %{lives: ["must be less than or equal to 6"]}

      negative_lives =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :dead,
          lives: -1,
          score: 0
        })

      refute negative_lives.valid?
      assert errors_on(negative_lives) == %{lives: ["must be greater than or equal to 0"]}

      negative_score =
        GamePlayer.changeset(%GamePlayer{}, %{
          player_id: player_id,
          status: :alive,
          lives: 6,
          score: -10
        })

      refute negative_score.valid?
      assert errors_on(negative_score) == %{score: ["must be greater than or equal to 0"]}
    end
  end

  describe "rope state invariants (property)" do
    property "R-01: any sequence of misses, scores, give_up, and reset keeps valid rope states and locked dead score" do
      op_gen =
        StreamData.one_of([
          StreamData.constant(:miss),
          StreamData.map(StreamData.integer(0..100), &{:score, &1}),
          StreamData.constant(:give_up),
          StreamData.constant(:reset)
        ])

      check all ops <- StreamData.list_of(op_gen, max_length: 25) do
        initial = build_game_player()

        final =
          Enum.reduce(ops, initial, fn op, gp ->
            next =
              case op do
                :miss -> GamePlayer.decrement_lives(gp)
                {:score, pts} -> GamePlayer.add_score(gp, pts)
                :give_up -> GamePlayer.give_up(gp)
                :reset -> GamePlayer.reset_lives(gp)
              end

            assert (next.status == :alive and next.lives in 1..6) or
                     (next.status == :dead and next.lives == 0)

            if gp.status == :dead and match?({:score, _}, op) do
              assert next.score == gp.score
            end

            next
          end)

        changeset =
          GamePlayer.changeset(%GamePlayer{}, %{
            player_id: final.player_id,
            status: final.status,
            lives: final.lives,
            score: final.score
          })

        assert changeset.valid?
      end
    end
  end
end
