# Forka — Architecture Guide

How Forka is structured, and why. `AGENTS.md` holds the hard rules (§2 Context isolation, §4 bottom-up flow, §5 types and docs). This guide explains the architecture behind them: how to pick a structure for new work, where side effects go, when to use processes, and what reviews check (§13).

The short version:

1. **Contexts are flat, own their data, and are the public API of the domain.** Everything outside a Context, including the web layer and other Contexts, goes through its public functions. Contexts never link to each other's data, and their dependencies point one way (§7).
2. **Functional core, imperative shell.** Decisions are pure functions over data. I/O (database, PubSub, jobs, HTTP, clock, randomness) happens around them, in the Context.
3. **Structure grows with complexity, not by default.** Most Contexts stay plain Phoenix Contexts. Add layers only when a trigger from §2 appears.
4. **The database is the source of truth.** Processes are runtime machinery (concurrency, timers, caching). They never store data, and they are never a way to organize code.
5. **Every action runs on behalf of a `%Scope{}`.** Who may see and do what is decided in the domain, not only in the UI.
6. **Side effects happen in one fixed order:** validate → load → decide → persist (one transaction) → publish → respond.

---

## 1. Layers and Dependencies

```
Web: LiveViews, controllers, components
  │  calls public Context functions, passing @current_scope
  ▼
Context module — lib/forka/<context>.ex — the shell
  │  validates input, loads, calls the core, persists, publishes
  ├── Schemas + changesets ...... data shape and validation        (pure)
  ├── Rules / policies .......... domain decisions                 (pure)     Level 2+
  ├── Read models ............... what clients may see             (pure)     when needed
  ├── Store ..................... loading, saving, mapping                    Level 3–4
  └── Server .................... one process per live entity                 Level 4
  ▼
Infrastructure: Repo, PubSub, HTTP clients (Req), job queue if required
```

| Module kind | May use | Must not use |
| :--- | :--- | :--- |
| **Web** | Context public functions, read models, components | `Repo`, `Ecto.Query`, `Ecto.Multi`, a Context's internal modules |
| **Context (shell)** | Its own internal modules, `Repo`, `Ecto.Multi`, PubSub, job queues, adapters, the **public** functions of the Contexts it declares as dependencies (§7) | Web modules, other Contexts' schemas, tables or internal modules, Contexts that depend on it |
| **Core** (rules, policies, read models) | Structs, `Ecto.Changeset`, pure modules of the same Context | `Repo`, PubSub, `send`/`GenServer`/`Task`, `DateTime.utc_now/0`, `Enum.random/1`, `Enum.shuffle/1`, id generation, `Logger` |
| **Schemas** | `Ecto.Schema`, `Ecto.Changeset`, same-Context associations | Cross-Context associations, `Repo`, queries, side effects |
| **Server** (process) | The Context's core and Store, `Registry` | Business rules inside callbacks |

`Ecto.Changeset` and embedded schemas are pure, so the core may use them. `Repo` is not pure.

Internal modules (rules, stores, servers, read-model builders) start their `@moduledoc` with "Internal to `Forka.<Context>`; call the Context instead." `mix xref graph --format cycles --label compile-connected` must stay empty. To enforce boundaries and declared dependencies at compile time, consider the [`boundary`](https://hex.pm/packages/boundary) library.

---

## 2. The Complexity Ladder

Start every Context at Level 1 (generator-first, AGENTS.md §1). Move up only when a trigger appears, and state the level in the Context's `@moduledoc`. Moving a Context to Level 3 or 4 is a design decision: record it in an ADR (`document` skill).

| Level | Use it when | Shape |
| :--- | :--- | :--- |
| **1. CRUD Context** | Data with validation, no lifecycle | Generated Context + schemas. Changesets hold the validation. |
| **2. Context + pure rules** | A decision doesn't need the database: pricing, eligibility, permissions, scheduling | Level 1 + pure `Rules`/`Policy` modules that the Context calls with loaded data |
| **3. Aggregate** | An entity has a lifecycle or state machine, invariants span several rows, concurrent writers can conflict, or you need an event history | Pure rules return the decision (a changeset or new state, plus events). The Context persists it in one transaction with optimistic locking, then publishes. |
| **4. Live process** | Per-entity timers, many users writing to the same entity many times a second, in-memory state too expensive to rebuild per request, presence or coordination | Level 3 + one supervised `Server` per live entity, running the same pipeline in its callbacks |

Typical files at Levels 3–4, for an `Auctions` Context:

```
lib/forka/auctions.ex                  # public API + shell
lib/forka/auctions/auction.ex          # schema = aggregate, changesets
lib/forka/auctions/bidding.ex          # pure rules
lib/forka/auctions/bid_params.ex       # command input (embedded schema)
lib/forka/auctions/auction_event.ex    # event schema, only if history is stored
lib/forka/auctions/auction_summary.ex  # read model, only if clients must not see the schema
lib/forka/auctions/store.ex            # Level 4: loading/saving shared by Context and Server
lib/forka/auctions/room_server.ex      # Level 4 only
```

The bottom-up flow (AGENTS.md §4) still applies. At Level 3 it becomes: migration → schema → **pure rules and their tests** → Context shell → interface.

---

## 3. Context API Conventions

- **Name Contexts after business capabilities** (`Accounts`, `Catalog`, `Auctions`), not tables. A Context owns its tables. Split a Context when two groups of schemas share no invariants and change for different reasons, into peer Contexts, never nested ones (§7). Never create one Context per schema.
- **Declare dependencies** at the top of the Context's `@moduledoc` ("Depends on: `Accounts`, `Catalog`."), along with its level (§2).
- **`%Scope{}` comes first** in every function that acts for someone, as the Phoenix 1.8 generators do.
  - *Visibility* is a scoped query (`where: a.user_id == ^scope.user.id`).
  - *Permission to act* is a pure rule that takes the actor's id and returns `{:error, :forbidden}` (or a more specific atom).
  - Background jobs act through dedicated functions (`close_ended_auctions(now)`), not a fake user scope.
- **Return contract:** `{:ok, value} | {:error, %Ecto.Changeset{}}` for invalid input, `{:error, atom}` for a broken domain rule. Declare the atoms as a type in the rules module (`@type error :: :auction_closed | :bid_too_low`).
  - **No silent no-ops.** If a command doesn't apply, return an error instead of `{:ok, unchanged}`.
  - Use `!` functions only where failure means a bug or a 404 (`get_auction!/2`).
- **Validate and normalize input once, at the Context boundary.** Cast command params with a changeset (embedded or schemaless). From there on, the core receives typed, normalized values. Normalize incoming data with the same function used on stored data (trim, downcase, Unicode normalization), so the two can be compared.
- **Return what callers need.** The Context decides preloads and returns structs or read models, never queries. LiveView forms come from the Context's `change_*` functions.
- **Subscriptions are Context functions** (`subscribe_auctions(scope)`), as generated in Phoenix 1.8. Callers never build topic strings.
- When a Context module grows, move private machinery into internal modules and keep the public function list in the Context, using `defdelegate` where it is a plain pass-through.

---

## 4. The Functional Core

Pure modules hold every decision.

- **Signature:** `decide(state, input..., now) :: {:ok, decision, [event]} | {:error, reason}`.
  - The decision is a changeset (schema as aggregate, the default) or a new struct (Option B, §6).
  - Events are optional. Emit them only when something must react, or the UI must explain what happened.
- **No hidden inputs.** The shell passes in the current time, generated ids, and random choices (shuffled order, picked items). The core is then deterministic and property-testable.
- **State machines in function heads.** Match the status first, check specific errors next, and put a catch-all clause last:

```elixir
def place_bid(%Auction{status: :open} = auction, bidder_id, amount, now) do
  cond do
    DateTime.compare(now, auction.ends_at) != :lt -> {:error, :auction_closed}
    bidder_id == auction.seller_id -> {:error, :own_auction}
    amount < minimum_bid(auction) -> {:error, :bid_too_low}
    true -> {:ok, accept_bid(auction, bidder_id, amount), [bid_placed(auction, bidder_id, amount, now)]}
  end
end

def place_bid(%Auction{}, _bidder_id, _amount, _now), do: {:error, :auction_closed}

# The decision is a changeset: pure data that the shell applies with Repo.
defp accept_bid(auction, bidder_id, amount) do
  auction
  |> Ecto.Changeset.change(current_bid: amount, leader_id: bidder_id)
  |> Ecto.Changeset.optimistic_lock(:version)
end
```

- **Total functions.** Decide explicitly what happens with unknown ids, empty collections, and out-of-order events. A `nil` from a map lookup must never reach a function clause.
- **One implementation per rule.** When two functions both answer "who plays next?", they drift apart and one of them becomes a bug. The "three strikes" tolerance for duplicated queries does not apply to domain rules; there the limit is one.
- **Invariants are properties.** Write them as StreamData properties (§11). For example: "for any sequence of valid commands, a game in progress has exactly one current player, and that player is still in the game."

---

## 5. The Shell Pipeline

Every command, in a Context function or (at Level 4) in a `Server` callback, follows the same order:

```elixir
@spec place_bid(%Scope{}, Ecto.UUID.t(), map()) ::
        {:ok, Auction.t()} | {:error, Ecto.Changeset.t() | Bidding.error() | :not_found}
def place_bid(%Scope{} = scope, auction_id, params) do
  now = DateTime.utc_now()

  # validate → load → decide (pure) → persist (one transaction)
  with {:ok, %{amount: amount}} <- BidParams.cast(params),
       {:ok, auction} <- fetch_auction(auction_id),
       {:ok, changeset, events} <- Bidding.place_bid(auction, scope.user.id, amount, now),
       {:ok, auction} <- persist(changeset, events) do
    # publish after commit → respond
    broadcast_auction(auction, {:updated, AuctionSummary.new(auction)})
    {:ok, auction}
  end
end

defp persist(changeset, events) do
  Repo.transact(fn ->
    with {:ok, auction} <- Repo.update(changeset, stale_error_field: :version) do
      Repo.insert_all(AuctionEvent, Enum.map(events, &AuctionEvent.row(auction, &1)))
      {:ok, auction}
    end
  end)
end
```

- **One transaction per command, inside one Context.** Use `Repo.transact/2`, or `Ecto.Multi` when the steps are dynamic. Nothing slow or external runs inside it: no HTTP calls, no broadcasts, and no calls into other Contexts (§7).
- **Optimistic locking at Level 3.** Add a `version` column and use `Ecto.Changeset.optimistic_lock/2` in the decision. A concurrent writer then gets `{:error, changeset}` instead of silently overwriting another write. The version also groups the events of one command.
- **Each kind of side effect has one place:**

| Effect | Where | When |
| :--- | :--- | :--- |
| Database writes | Context (or Store) | Inside the command's transaction |
| PubSub broadcasts | Context, through its `broadcast_*` function | After commit; best-effort |
| Email, webhooks, external API writes that must survive restarts | Persistent worker | Record the job in the same transaction as the change |
| External reads needed to decide | Context, before `decide` | Outside transactions; the result goes into the core as data |
| Time, ids, randomness | Context | Computed before calling the core |
| Logging, telemetry | Shell | Anywhere in the shell |

- **Append-only data stays append-only.** Insert event or history rows (`insert_all`). Never re-save the whole history together with its parent on every command.
- **Broadcast read models, not internals.** A broadcast must not leak hidden data (a secret word, other bidders' maximum bids). Send the read model meant for that topic's audience: a detail topic gets the full summary, a list topic gets a small list item, and only when something shown in the list changed.

---

## 6. Data Shapes

There are three shapes. Keep them as one until they actually differ:

1. **Schema:** how data is stored. The default for everything, and the aggregate at Level 3 (Option A).
2. **Domain struct (Option B):** a plain `defstruct` with `@type t`, for Levels 3–4 when the in-memory shape differs a lot from the tables (turn order, derived indexes), lives a long time in a process, or goes through many transitions before being saved.
3. **Read model:** what a client may see (`AuctionSummary`, `AuctionListItem`). Add one only when the schema holds data a client must not see, or a view needs a different shape.

When you choose Option B:
- **Map in one place.** The Store converts between the domain struct and the schemas. No hand-written `Map.from_struct/1 |> Map.drop([:__meta__])` scattered around.
- **Round-trip test every field:** save a state, load it back, and compare. A field dropped by the mapping fails silently: the next load resets it, and nothing raises.
- **Never mix the two options**, for example a plain-struct aggregate holding Ecto schemas that it converts by hand.

**Snapshots.** When data must not change after the fact (the price on an order line, the word used in a game), copy it into the owning Context (an embedded schema or columns). Keep the source id only as a reference.

**Secrets in structs.** Use `@derive {Inspect, except: [...]}` on fields that must never reach logs or error reports.

---

## 7. Crossing Context Boundaries

### Flat Contexts

Contexts are the top-level modules under `lib/forka/`, next to infrastructure (`Repo`, `Mailer`, `Application`) and the shared kernel. Modules below a Context are its internals, never sub-Contexts with their own API. A Context that grows too big splits into peer Contexts.

The only modules every Context may use form a small **shared kernel**: pure modules with no tables, no `Repo` and no state (value types such as `Forka.Money`), plus the `%Scope{}` struct that `phx.gen.auth` generates (`Forka.Accounts.Scope`).

### No linked data

The Phoenix guide's cart example couples Contexts with `belongs_to` on purpose. This project doesn't (AGENTS.md §2), so each Context can change its schemas without breaking another.

- **No associations or shared tables.** No Ecto associations to another Context's schemas, and no schemas of your own mapped onto another Context's tables.
- **References are ids.** A cross-Context reference is a plain `:binary_id` field with an index.
- **Foreign keys only restrict.** A migration may add a foreign key to another Context's table only with `on_delete: :restrict`. A delete in one Context can then never cascade into, or nullify, another Context's rows. Deleting a row another Context still references fails, so design that deletion explicitly, usually as a soft delete or anonymization, and record it in an ADR.
  - Generators don't do this for you. A scoped `phx.gen.*` writes `on_delete: :delete_all` on the scope's `user_id`, and a `:references` field writes `on_delete: :nothing`. Change both to `:restrict` when the referenced table belongs to another Context.
- **Using another Context's data.** Call its public API with ids, batched to avoid N+1 queries (`Accounts.list_users_by_ids(ids)`), or keep a snapshot of the fields you need (§6). Structs that another Context returns are read-only values. Read only the fields its functions document. Never persist those structs, put them in your changesets, or pass them to `Repo`.

### Calls between Contexts

- **Public functions only**, passing the scope when acting for a user.
- **Declared and one-way.** Each Context lists the Contexts it calls in its `@moduledoc` (§3). Calls follow only those declarations, and the dependency graph has no cycles. A cycle means the two Contexts should merge, or one direction should become events.
- **Reads any time; writes outside your transaction.** Never call another Context inside `Repo.transact/2` or an `Ecto.Multi`. Its broadcasts and jobs would fire before your commit, and a transaction must never span Contexts. If two Contexts must always change atomically, they are one Context.
- **Reactions.** When "X happens in A" must cause "B does Y":
  - Best-effort (UI updates, caches): B subscribes to A's PubSub topic.
  - Must not be lost: inside its own transaction, A records a persistent job that calls B's public function after commit. Declare the resulting dependency on B.
  - If B already depends on A, A must not know about B. Use a durable event dispatch instead (an event job whose handlers each Context registers), and record it in an ADR.

### Where orchestration lives

When the same sequence of Context calls appears in more than one place (two LiveViews, or a LiveView and a job), it is a missing Context function. Callers make **one Context call per user intent**.

- **The owning Context**, when the use case reads as part of one Context's language. "Place an order" is `Orders.place_order/3`, which calls `Catalog` and `Accounts` and declares them as dependencies.
- **A use-case Context**, when no existing Context owns the workflow, e.g. `Onboarding.complete/2` across `Accounts`, `Billing` and `Notifications`.
  - It is a normal peer Context: flat, with its own public API and declared dependencies, and its own tables if it must track progress. Nothing depends on it.
  - Its steps run one after another, outside any shared transaction. Make each step idempotent, so a retried job or request is safe.
- **A large use case stays behind its Context.** Move its body into an internal module (`Orders.PlaceOrder`) and keep the public function in `Orders`, delegating to it. Callers never call the internal module.
- **No `Services` layer, and no orchestration in the top-level `Forka` module.**
  - Contexts already are Phoenix's service layer. A second one blurs ownership and becomes the place where rules leak out of the core.
  - The top-level module would turn into a god module that depends on everything.
- **UI-only repetition is not orchestration.** Loading the same assigns, subscribing, or handling the same events in several LiveViews belongs in the web layer. Use an `on_mount` hook, `attach_hook/4`, a function or live component, or a small helper module in `ForkaWeb`. These may call Context functions, but never make domain decisions.

---

## 8. Processes (Level 4)

Use a process for a runtime need. Never use one to organize code, or to "hold an entity".

- **Structure:** a thin `Server` whose callbacks run the §5 pipeline (the state is already loaded). Move loading and saving into the Context's `Store` so the Context and the Server share them. If runtime-only state (timers, monitors) has logic of its own, give it a small pure `State` struct.
- **Choose `restart:` on purpose.** Per-entity servers use `use GenServer, restart: :transient`. A `:permanent` server (the `use GenServer` default) that stops with `:normal` gets restarted anyway. If the restart then fails, the `DynamicSupervisor` exceeds its restart intensity and terminates, taking every sibling with it.
- **No I/O in `start_link/1` or `init/1`.** Both run while the supervisor waits, which blocks every other start. Pass the id, load in `handle_continue/2`, and stop with `:normal` if the entity is gone. Check in the Context that the entity can be served before starting the process. Never pass loaded state as the start argument: a restart would replay that stale snapshot.
- **Start without checking first.** A "does it exist?" check followed by a start is a race. Just start, and treat `{:error, {:already_started, pid}}` as success:

```elixir
defmodule Forka.Auctions.RoomServer do
  @moduledoc "Internal to `Forka.Auctions`: the live process of one auction room."
  use GenServer, restart: :transient

  alias Forka.Auctions.Store

  @idle_timeout :timer.minutes(30)

  def start_link(auction_id),
    do: GenServer.start_link(__MODULE__, auction_id, name: via(auction_id))

  @impl true
  def init(auction_id), do: {:ok, auction_id, {:continue, :load}}

  @impl true
  def handle_continue(:load, auction_id) do
    case Store.fetch(auction_id) do
      {:ok, auction} -> {:noreply, auction, @idle_timeout}
      {:error, :not_found} -> {:stop, :normal, auction_id}
    end
  end

  # Idle: free memory only. Never change domain state here.
  @impl true
  def handle_info(:timeout, auction), do: {:stop, :normal, auction}

  defp via(id), do: {:via, Registry, {Forka.Auctions.Registry, id}}
end

# In the Context:
defp ensure_room(auction_id) do
  case DynamicSupervisor.start_child(Forka.Auctions.RoomSupervisor, {RoomServer, auction_id}) do
    {:ok, pid} -> {:ok, pid}
    {:error, {:already_started, pid}} -> {:ok, pid}
    other -> other
  end
end
```

- **Names:** `Registry` on a single node, started before the `DynamicSupervisor`. Use `:global` or a distributed registry only when the process must be unique across a cluster. Keep optimistic locking even then: two processes can still exist during a netsplit.
- **Process lifetime is not entity lifetime.** An idle timeout only frees memory. Domain transitions such as "close auctions that have ended" or "archive abandoned games" are scheduled jobs that read persisted timestamps, so they still happen after deploys and restarts.
- **Persist before replying.** If persisting raises, let the server crash: it reloads from the database when restarted.
- **Whoever starts a process stops it.** Put related processes under one per-entity supervisor (`:one_for_all`), or link them. Subscribers are PubSub subscriptions, or `Process.monitor/1` when you must track them yourself. Never poll `Process.alive?/1`.
- **One command path in the server.** Every `handle_call` goes through one function (decide → persist → publish), and notifications are derived from what changed (a status change also updates the list topic). Copy-pasted handlers drift apart.

---

## 9. Web Layer

- LiveViews and controllers call Context functions with `@current_scope` and render structs or read models. They make no domain decisions: "can this user do X?" is a Context function.
- **One Context call per user intent.** A sequence of Context calls repeated in several LiveViews becomes a Context function. Repeated UI wiring becomes an `on_mount` hook or a component (§7, "Where orchestration lives").
- Composing a page from several Contexts' **reads** is fine. A **write** that involves more than one Context is a use case, so it lives in a Context.
- Subscribe in `mount/3` when `connected?(socket)`, through the Context's `subscribe_*`. In `handle_info/2`, apply the read model you received or re-fetch through the Context.
- Use `stream/3` for collections. Build forms with the Context's `change_*` functions and `to_form/2`.
- **Presentation follows the UI directives** (`.agents/rules/ui.md` and the `ui-*.md` files it lists, with this app's `ui-profile.md`). Their layers continue this one: LiveView → domain components (`<Domain>Components`, which map Context structs to props and never call Repo or PubSub) → primitives in `core_components.ex` → tokens in `app.css` (`ui-components.md` §5).
- **Admin exception:** admin frameworks that need `Repo` and schemas directly (e.g. Backpex) live under `ForkaWeb.Admin`, recorded in an ADR. Actions that touch domain invariants (archive, cancel, refund) still go through Context functions.

---

## 10. External Services

- One adapter module per service (e.g. `Forka.Payments.StripeClient`), built on `Req` and called only by its Context.
- Tests stub HTTP with `Req.Test`. Use a behaviour with Mox only for boundaries that aren't HTTP.
- Choose adapters one way (application config). Keep test-only adapters in `test/support`, never in `lib/`, and keep test hooks out of public function signatures.
- Use persistent workers with retries and idempotency keys when external writes must survive a restart.

---

## 11. Testing Strategy

| Tier | Covers | How |
| :--- | :--- | :--- |
| **Core** | Rules, policies, read models, `State` structs | `ExUnit.Case, async: true`, no database; `build/2` factories or plain structs; StreamData properties for invariants. Deterministic, because time and randomness are arguments. |
| **Context** | Each public function: success, each error atom, invalid params, **another scope can't see or act**, broadcast sent on success and not on failure, round-trip for Option B mappings | `DataCase, async: true`, ExMachina `insert/2` |
| **Process** | Lifecycle: a stopped server stays stopped, a crash reloads from the database, siblings survive, idle stop leaves the domain unchanged | Start **through the real supervisor** (via the Context); `Ecto.Adapters.SQL.Sandbox.allow/3`; monitors and `assert_receive {:DOWN, ...}`, never `Process.sleep/1` |
| **Web** | User flows and live updates | `Phoenix.LiveViewTest`: change things through the Context and assert on `render/1` |
| **External** | Adapters | `Req.Test` stubs |

```elixir
use ExUnitProperties

property "the leader always holds the highest accepted bid" do
  check all bids <- list_of(tuple({member_of(bidder_ids()), integer(1..10_000)})) do
    auction = Enum.reduce(bids, open_auction(), &apply_bid/2)
    assert auction.current_bid == highest_accepted(bids)
  end
end
```

- **Test helpers must assert.** A helper that returns a boolean nobody checks lets every mismatch pass.
- **Test data uses production types:** UUID strings rather than integers, `DateTime` rather than `{:ok, time}`. Dialyzer doesn't check tests.
- **Prefer properties for invariants.** One property finds the cases a dozen examples miss: turn order wrapping around, unknown ids, sequences nobody thought of.

---

## 12. Types, Docs, and Static Checks

- `@type t` on every struct and `@spec` on every public function in `lib/forka/` (AGENTS.md §5). Error atoms are a named type.
- **Code examples in docs are doctests**, or they don't exist. After a rename, search docs and comments for the old name.
- By default, Dialyzer only reports a spec that cannot match at all, so a spec that merely overlaps the real return type passes. The `dialyzer:` config in `mix.exs` adds `flags: [:missing_return, :extra_return, :error_handling]`, so a return type missing from the spec, or listed in it but never returned, is also a warning.
- `mix precommit` runs the rest (AGENTS.md §5).

---

## 13. Review Checklist

Applied by `review-spec`, `local-review`, and `audit-architecture`:

- [ ] Web code calls only Context functions, passing `@current_scope`.
- [ ] Every Context function that acts for a user takes `%Scope{}` first; queries are scoped; permission to act is a domain rule.
- [ ] Core modules don't use `Repo`, PubSub, processes, the clock, randomness, or id generation.
- [ ] Commands return `{:ok, _}` or `{:error, _}` with declared error atoms; there are no silent no-ops.
- [ ] Input is cast, validated, and normalized once, at the Context boundary.
- [ ] Each domain rule has exactly one implementation.
- [ ] Multi-step writes and durable job records use the same transaction. Aggregates use optimistic locking. Broadcasts and HTTP calls run outside transactions.
- [ ] Broadcasts and replies carry read models that don't leak hidden data.
- [ ] Every domain↔schema mapping has a round-trip test covering every field.
- [ ] Contexts are flat. Each declares its dependencies in its `@moduledoc`; calls follow them one way, with no cycles and never inside a transaction.
- [ ] No cross-Context associations or schemas over another Context's tables; cross-Context foreign keys use `on_delete: :restrict`; cross-Context data comes through public APIs or snapshots.
- [ ] Each user intent is one Context call; repeated orchestration lives in the owning Context or a use-case Context, never in LiveViews, a services layer, or the top-level module.
- [ ] Each process exists for a runtime need: `restart:` chosen on purpose, no I/O in `start_link`/`init`, started without a prior existence check, stopping never changes domain state, lifecycle tested through the supervisor.
- [ ] Properties cover core invariants; test helpers assert; test data uses production types.
- [ ] Doc examples are doctests; specs match what the functions return.
