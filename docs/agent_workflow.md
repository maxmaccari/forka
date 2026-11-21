# Forka development workflow

Start with [AGENTS.md](../AGENTS.md). Read the [shared architecture guide](architecture.md) for new Contexts, aggregates, or processes, and the [Forka context map](forka-architecture.md) for existing boundaries and gaps. For UI work, read the [UI directives](../.agents/rules/ui.md) and [Forka's UI profile](../.agents/rules/ui-profile.md). The [shared conventions](../.agents/shared/conventions.md) cover tests, reviews, and documentation.

1. Define the outcome, scope, edge cases, and acceptance criteria. Put durable specs in `docs/specs/` and research in `docs/researches/`.
2. Review the spec against the relevant Context, security, and UI rules before building.
3. Implement from migration and schema through the domain and interface as applicable. Test domain decisions and the affected user flow.
4. Review the diff against the [architecture checklist](architecture.md#13-review-checklist). Run `mix precommit`. Record decisions with lasting consequences in `docs/adrs/` and put temporary plans and reports in `docs/tmp/`.

Use the planning, implementation, and review skills installed in your environment. The current shared `/ship` workflow requires the project-local skills from the Phoenix kit.

## Updating shared guidance

[.agents/kit.json](../.agents/kit.json) records the revision in the local `maxmaccari-dev-tools` checkout. Use the library's `sync-skills` dry-run pull from the Forka root to review upstream changes. Use `--only` with the approved paths from the plan so new upstream skills and `CLAUDE.md` stay out. Keep Forka-specific decisions in the context map, ADRs, or the project section of `AGENTS.md`. Forka owns its UI profile and its development workflow.
