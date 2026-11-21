# ADR 0002 · Backpex admin boundary

Status: records the existing Backpex integration

Backpex resources behind the authenticated `/admin` LiveView session use `Forka.Repo` and the schema adapters Backpex requires. Keep those adapters and their helpers under `ForkaWeb.Admin`. Player-facing code uses the public Context APIs.

Backpex may render and manage basic admin resources. Operations that change domain invariants go through the owning Context. The current game resource is index-only with deletion allowed for archived games. Keep the remaining direct-access gaps visible in the [context map](../forka-architecture.md).
