# ADR 0001 · Game process ownership and recovery

Status: proposed pending [MAX-18](https://linear.app/maxmaccari/issue/MAX-18/choose-a-production-hosting-and-scaling-model-for-forka)

Games needs to serialize concurrent commands for each active match. It currently runs a transient `GameServer` per game under `Forka.GamesSupervisor`, with `:global` naming and PostgreSQL persistence.

Keep the process owned by Games. For a single-node deployment, use a unique Registry and a DynamicSupervisor. Start by game ID and load the last committed aggregate in the child. Terminate idle children without a domain transition. Reopen from PostgreSQL after an idle stop or deploy. If the product requires abandoned games to archive, use a separate rule based on persisted activity timestamps.

Before enabling multiple writers, decide routing and supervisor placement in MAX-18. Use a database-level concurrency check even with distributed registration. A stale process must reload before another attempt. Publish updates only after commit and let reconnecting clients resubscribe and fetch a fresh projection.
