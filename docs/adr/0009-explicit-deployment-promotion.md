# 0009: Explicit Deployment Promotion After Continuous Integration

Status: Accepted
Date: 2026-08-25
Decision owner: One Health Lyme Gap Atlas product and engineering leads

## Context

The existing API, web, and governed-pipeline workflows deployed automatically
after a successful push to `main`. The Knowledge Graph v1 work includes
infrastructure and protected runtime configuration that must remain distinct
from a source-code quality result. A green CI run is necessary evidence, but
not authorization to change a live service.

## Decision

Pushes and pull requests continue to run their complete quality gates. API,
web production, and data DEV deployments run only from a manually dispatched
workflow with an affirmative deployment input and the existing GitHub
Environment protection.

This refines ADR 0004's delivery automation: merging to `main` produces a
verified release candidate, not an automatic deployment. A designated owner
must promote it after reviewing the CI result, target, configuration, rollback
state, and required live-acceptance gates.

## Consequences

The extra promotion action can delay routine releases, but prevents a quality
only commit from causing an unreviewed production or DEV deployment. It does
not authorize public chat, credential installation, Snowflake migrations, or
corpus processing by itself.

## Alternatives considered

Keeping automatic deployment was rejected because it conflates CI success with
operational authorization. Branch protection alone was rejected because an
approved merge still invokes automatic deployment.

## Acceptance criteria

- Push and pull-request quality checks remain automatic.
- A push to `main` cannot deploy API, web, or data without an explicit manual
  workflow input.
- The protected GitHub Environment remains part of every deployment job.
- Release evidence identifies CI, promotion, deployment state, and live checks
  separately.

## Rollout, observability, and rollback

Dispatch the target repository workflow with its deployment input only after
reviewing the exact commit and its successful quality run. Use the existing
DigitalOcean deployment history for rollback; disable feature flags before a
graph-related rollback. Review workflow run, App Platform phase, health check,
and live endpoint independently after every promotion.

## Links

- ADR 0004
- API, web, and data GitHub Actions workflows
- ADR 0007 and ADR 0008
