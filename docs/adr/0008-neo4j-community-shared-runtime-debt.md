# 0008: Neo4j Community Shared Runtime Credential Debt

Status: Accepted
Date: 2026-08-25
Decision owner: One Health Lyme Gap Atlas product and engineering leads

## Context

ADR 0007 selected self-hosted Neo4j Community for v1 while specifying separate
read-only API and graph-writer database users. Live DEV provisioning verified
that Community does not support roles or privilege grants. Separate usernames
would therefore not enforce a reader/writer boundary.

## Decision

For v1, retain the private Neo4j Community deployment and use one shared,
server-side `graph_runtime` identity for the API and governed pipeline. The
identity is stored only in protected runtime configuration; it never reaches
the browser, logs, source control, or test fixtures.

The system compensates with VPC-only Bolt, a Cloud Firewall, fixed retrieval
templates, no arbitrary Cypher endpoint or tool, API request validation and
rate limits, human-approved graph publication, and `KG_CHAT_ENABLED=false`
until the full live acceptance record is signed.

## Consequences

This is accepted security debt: Neo4j does not independently prevent a
compromised trusted API runtime from issuing graph writes. It does not change
Snowflake's procedure-only API writes or the browser-to-API boundary. It must
be reported as unmet database-level separation of duties, not as a passed
least-privilege control.

## Alternatives considered

Neo4j Enterprise or an eligible managed Enterprise offering would restore
database-enforced role-based access control but was deferred for v1 cost.
An internal retrieval gateway would reduce credential distribution but adds a
new service and still does not add native Community authorization.

## Acceptance criteria

- No public interface exposes a Neo4j credential or arbitrary Cypher.
- Bolt remains limited to the Atlas VPC and Browser/HTTP remains unpublished.
- The shared runtime credential exists only in protected server-side stores.
- Public chat remains disabled until backup/restore evidence and all ADR 0007
  acceptance criteria are recorded.
- Release evidence identifies this as accepted Community authorization debt.

## Rollout, observability, and rollback

Provision the identity only on the private Neo4j host, then install it as
encrypted API and data runtime configuration during their separately approved
deployments. Rotate it by disabling chat and extraction, replacing the host
credential and both runtime secrets, then verifying fixed retrieval and graph
publication. Revisit Enterprise RBAC before expanding public scope or adding
additional graph-consuming services.

## Links

- ADR 0007
- `infra/configure-neo4j.sh`
- API fixed Neo4j retriever and data graph publisher
