# 0007: Knowledge Graph and Public Evidence Chat

Status: Accepted
Date: 2026-08-25
Decision owner: One Health Lyme Gap Atlas product and engineering leads

## Context

The Atlas needs a public literature-evidence chatbot backed by a governed
PubMed/PMC corpus. The feature adds a stateful graph, model providers, limited
conversation persistence, and a public POST endpoint. These change the current
read-only API, deployment topology, data classification, and operational model.

## Decision

- Keep the browser boundary unchanged: the Next.js application calls FastAPI;
  only server-side services access Snowflake, Neo4j, Spaces, or model providers.
- Host separate DEV and PROD Neo4j Community instances on private DigitalOcean
  Droplets and persistent volumes. API access is read-only; pipeline access can
  publish validated, provenance-complete graph contributions.
- Use the governed PROD Snowflake database for literature processing state,
  LLM usage, and 30-day conversations. The API runtime receives procedure-only
  write privileges, not general DML rights.
- Serve one non-streaming public endpoint, `POST /v1/knowledge-graph/chat`.
  Answers fail closed without Neo4j evidence and every substantive claim must
  resolve to a PubMed paper and permitted evidence passage.
- Use an opaque per-conversation capability token. Persist only its digest.
  Treat prompts as potentially sensitive user content: exclude them from logs,
  restrict access, and purge them after 30 days.
- Use Neo4j Community offline logical dumps daily. The API returns a typed
  evidence-unavailable response during the maintenance interval.
- Defer a custom outbound event-alert sink. Exhausted retries still create
  durable audit events and structured error logs; DigitalOcean infrastructure
  and uptime alerts remain enabled. This is an approved deviation from the
  earlier concept acceptance matrix.

## Consequences

The API service role is no longer literally read-only, although all new writes
are constrained to owner-rights procedures. Anonymous conversation tokens are
bearer capabilities and must never appear in logs or URLs. Community backups
cause a short scheduled evidence outage. Horizontal API scaling is prohibited
until the in-memory IP/concurrency limiter is replaced by a shared limiter.

## Alternatives considered

Neo4j Enterprise online backup was rejected for v1 cost. A direct browser graph
connection was rejected for security and contract reasons. Client-only
conversation persistence was rejected because 30-day server persistence was
selected. A custom Slack/email alert sink was explicitly deferred.

## Acceptance criteria

- Alpha `LANDING` and `PRESENTATION` objects remain unchanged.
- No public asset contains Snowflake, Neo4j, Spaces, or model credentials.
- Every returned claim has validated paper/passage citations.
- Missing, unavailable, or timed-out graph evidence never falls back to general
  model knowledge.
- API write access is executable-procedure-only and conversations are purged.
- Backup creation and a restore test are recorded before public enablement.
- The alerting deviation is visible in release evidence and is not reported as
  satisfying the original outbound-alert requirement.

## Rollout, observability, and rollback

Deploy contracts, DEV data objects, DEV Neo4j, pipeline, API, and web in that
order. Keep `KG_CHAT_ENABLED=false` until the live acceptance record is signed.
Rollback disables chat and extraction workers, restores the prior application
deployments, and retains all ledgers and artifacts. Restore Neo4j only from a
verified dump; never delete graph state as an application rollback.

## Links to affected contracts and tests

- `one-health-lyme-gap-atlas-knowledge-graph/config/kg-v1.0.0.json`
- API `openapi.json` and chat contract tests
- Data forward-only literature migrations and pipeline tests
- Web storage, accessibility, component, and Playwright tests
