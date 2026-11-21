<!-- kit:setup-phoenix-app begin -->
# Forka - AI Assistant Master Guidelines

You are the artificial intelligence assistant responsible for helping develop **Forka**, a multiplayer word-guessing game. The backend is built with Elixir, Phoenix (with LiveView), and PostgreSQL (using UUIDs).

Strictly follow the rules below in all interactions, code generation, and refactoring tasks.

## 1. Generator-First Programming (STRICTLY ENFORCED)
- **Do not write boilerplate code from scratch.** When a new feature, context, schema, or interface is requested, you MUST first evaluate if a Phoenix generator can be used (`mix phx.gen.context`, `mix phx.gen.live`, `mix phx.gen.auth`, etc.).
- **Execution Flow:**
  1. Formulate the exact `mix` command needed.
  2. **Execute the command directly** using your terminal/shell execution tools.
  3. Verify the execution success and read the generated files.
  4. ONLY THEN proceed to apply modifications, refinements, or business logic injections into those generated files.

## 2. Architecture and Contexts (Phoenix Contexts)
- **Domain-Driven Design (DDD):** The application must be strictly divided into Phoenix Contexts (e.g., `Accounts`, `Catalog`, `Orders`).
- **Context Isolation (Golden Rule):** Contexts never link their data. It is strictly forbidden to create Ecto relationships (e.g., `belongs_to`, `has_many`) between Schemas that belong to different contexts, or to map a schema onto another Context's table.
  - *How to do it:* Use only the ID as a reference (e.g., `field :author_id, :binary_id` with an index, instead of `belongs_to :author`). Data crossing must happen at the Context function level, never at the structural Schema level.
  - *Database level:* A foreign key constraint (`references/2` in a migration) to another Context's table is allowed only with `on_delete: :restrict`, so a delete never cascades into, or nullifies, another Context's rows.
- **Flat Contexts:** Contexts are peers at the top of `lib/forka/`. Never nest a Context inside another; split a large Context into peers. Shared code is limited to pure value modules and `%Scope{}`.
- **Cross-Context Calls:** Only through public functions, and only to the Contexts listed in the caller's `@moduledoc` ("Depends on: ..."). Dependencies are one-way with no cycles. Never call another Context inside a transaction. Use a persistent queue for reactions that must survive a restart. A workflow repeated across LiveViews is a Context function, never a "service" module.
- **UUIDs Everywhere:** Always use `binary_id` (UUIDs) for primary and foreign keys.
- **Architecture Guide:** `docs/architecture.md` covers how much structure a Context needs (the complexity ladder), the pure core and the side-effect pipeline around it, crossing Context boundaries, processes, testing, and the review checklist. Read it before designing a Context, an aggregate, or a process.

## 3. Interface and Components
- **Native Components Only:** Strictly use Phoenix Core Components (`core_components.ex`) for the UI.
- **Stack:** Use Phoenix LiveView and TailwindCSS.
- **UI Directives:** Design, components, tokens, and UI behaviour follow `.agents/rules/ui.md` and the `ui-*.md` files it lists. This app's choices are in `.agents/rules/ui-profile.md`, which wins over the defaults.
- **No External JS:** Do NOT suggest React, Vue, Alpine.js, or custom JavaScript unless strictly necessary for Phoenix Hooks.

## 4. Development Flow (Bottom-Up)
When modifying or extending generated code, follow the exact implementation order:
1. **Migration:** Database tables, indexes, and constraints.
2. **Schema:** Ecto module, struct, types (`@type t()`), and the `changeset/2` function with strict validations.
3. **Context (Business Logic):** Implement the domain logic, CRUD operations, and external API calls (e.g., LLM communication) here.
4. **Interface (Web/LiveView):** Only after the previous steps pass, create or modify the presentation layer.

## 5. Testing, Typing, and Documentation
- **Test-Enforced:** No business rule or new feature can be created without accompanying tests. Write both unit tests and integration tests (for Context flows and LiveView) using `ExUnit`, and StreamData properties (`use ExUnitProperties`) for core invariants.
- **Regression tests:** Every bug fix must add or extend an automated test. Verify that the test fails on the original code for the reported bug and passes with the fix.
- **Test Data:** Build test data with ExMachina factories (`Forka.Factory`, one `test/support/factories/<context>_factory.ex` per Context). Replace the fixtures that Phoenix generators create in `test/support/fixtures/` right after running a generator.
- **Mandatory Typespecs (Domain Layer):** Every Schema must define its own `@type t()`. All public functions within the core domain (`lib/forka/`, such as Contexts and Schemas) must be typed using `@spec`. Web-layer modules (`lib/forka_web/`) and infrastructure boilerplate (`Mailer`, `Repo`, `Router`, etc.) do not require `@spec`.
- **Documentation (Domain Layer):** Core domain modules and public functions in `lib/forka/` must be documented using `@moduledoc` and `@doc`. Framework boilerplate (`Mailer`, `Router`, etc.) and web-layer callbacks do not require `@moduledoc` or `@doc`.
- **Enforcement:** `mix precommit` runs `mix doctor` (docs and typespecs, configured in `.doctor.exs`), `mix dialyzer`, `mix credo --strict`, `mix sobelow`, `mix deps.audit`, and `mix coveralls` (coverage minimum in `coveralls.json`).

## 6. Elixir Code Standards
- Prefer *Pattern Matching* and *Guard Clauses* over `if/else` blocks.
- Use the pipe operator (`|>`) to keep data transformation flows clean.
- Handle function returns using standard ok/error tuples (`{:ok, result}` and `{:error, reason}`).

## 7. Development Workflow

- Follow [the project workflow](docs/agent_workflow.md) and [shared conventions](.agents/shared/conventions.md).
- Use the skills available in your environment. Start each plan, implementation, or review by reading this file and the applicable rules in §8.
- Use [`commit`](.agents/skills/commit/SKILL.md) for commits and [`pull-request`](.agents/skills/pull-request/SKILL.md) for GitHub PRs. Use Conventional Commits for both subjects and titles: `type(scope): summary`, with an optional scope. Reuse the commit subject for a one-commit PR. For several commits, describe the overall change.
- Keep specs and architecture decisions under `docs/specs/` and `docs/adrs/`. Put temporary plans and reports under `docs/tmp/`.

## 8. Framework Rules (`.agents/rules/`)
Read the applicable rules before planning, changing, or reviewing code. They are as binding as this file.

- Backend and web framework: [Elixir](.agents/rules/elixir.md), [Phoenix](.agents/rules/phoenix.md), [Ecto](.agents/rules/ecto.md), [HEEx](.agents/rules/html.md), and [LiveView](.agents/rules/liveview.md).
- Security: [secure coding rules](.agents/rules/security.md) apply to all changes. Rust code also follows [the Rust directives](.agents/shared/security-rust.md).
- UI: read the [UI directives](.agents/rules/ui.md), the companion rules they list, and [Forka's UI profile](.agents/rules/ui-profile.md).

Antigravity loads the rule files as always-on rules, Claude Code uses the `.claude/rules` symlink, and OpenCode loads them through `opencode.json`.

- **Size limit:** Antigravity truncates a rule file past 24,000 bytes and silently drops its tail. Keep `AGENTS.md` and each file in `.agents/rules/` under that limit. Put a new set of rules in its own `.agents/rules/<topic>.md` with `trigger: always_on` frontmatter instead of growing this file.

## Code Review Rules
For every reviewer, human or bot (Codex reads this heading). Flag only a traceable failure or a broken rule below; formatting, style, and missing web-layer typespecs are CI's. The full checklist is `docs/architecture.md` §13.

### Architecture
- Core modules decide; they never call `Repo`, PubSub, processes, the clock, randomness, or id generation. Safe path: the Context passes `now`, ids, and random choices in, and applies the returned changeset or events.
- Web code (LiveViews, controllers, components) calls only public Context functions, passing `@current_scope`; never `Repo`, `Ecto.Query`, or another Context's schemas. Safe path: add or extend a Context function.
- Contexts never link data: no cross-Context associations, references are `:binary_id` fields, and cross-Context calls follow the declared one-way dependencies, never inside a transaction. Safe path: a public function call, or a snapshot of the data.

### Security
The full rules and checklist are `.agents/rules/security.md`; these are the ones a reviewer flags most.
- Every Context function that acts for a user takes `%Scope{}` first and scopes its query by it; permission is a domain rule with a test for the wrong scope. Safe path: return `{:error, :not_found}` or `{:error, :unauthorized}` from the Context, never filter in the LiveView.
- Outside input (params, files, webhooks, model output) is cast and validated at the Context boundary before use; never turned into an atom or a module without a whitelist.
<!-- kit:setup-phoenix-app end -->

---

## Forka-specific guidance

- Read the [context map and architecture audit](docs/forka-architecture.md) before working on rooms or matches. It records the current code, known gaps, and how the shared guide applies to Forka.
- Player-facing screens use the UI profile. The Backpex exception is scoped to the authenticated `/admin` area. See the [Backpex ADR](docs/adrs/0002-backpex-admin-boundary.md).
- [Kit provenance and updates](docs/agent_workflow.md#updating-shared-guidance) are documented alongside the workflow.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Domain modules in `lib/forka/` require `@moduledoc`, `@doc` and `@spec` for public functions, and a `t()` type for structs. Doctor checks these in `mix precommit`. The web layer, test support, application supervisor, mailer, and repo are exempt.
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- `ForkaWeb.Layouts` provides the app layout configured in `lib/forka_web.ex`
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/forka_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design. Exception: daisyUI stays for the Backpex back office (`/admin`) only; see `.agents/rules/ui-profile.md` §2
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions
