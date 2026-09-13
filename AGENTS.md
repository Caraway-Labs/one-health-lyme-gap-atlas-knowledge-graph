# Atlas knowledge-graph instructions

Read the workspace [AGENTS.md](../AGENTS.md), [technology and governance
baseline](../TECHNOLOGY_AND_GOVERNANCE.md), this repository's `README.md`, and
[ADR 0007](docs/adr/0007-knowledge-graph-and-public-evidence-chat.md),
[ADR 0008](docs/adr/0008-neo4j-community-shared-runtime-debt.md), and
[ADR 0009](docs/adr/0009-explicit-deployment-promotion.md) before material
work.

- This repository owns the versioned, language-neutral ontology, identity
  rules, schemas, configuration, Cypher templates, public copy, evaluation
  fixtures, and reviewed infrastructure automation. Preserve immutable
  identifiers and schema/version compatibility; update fixtures and downstream
  package consumers for contract changes.
- Every substantive public-chat claim must resolve to permitted, validated
  PubMed evidence. Fail closed when evidence is missing or unavailable. Never
  add arbitrary Cypher, graph credentials, capability tokens, or prompts to
  public assets, URLs, logs, fixtures, or source control.
- Infrastructure previews are non-mutating by default. Creating paid resources,
  publishing a release tag, enabling public chat, or promoting a deployment
  requires the recorded project-owner approval and ADR acceptance evidence;
  `KG_CHAT_ENABLED` remains false until then.

Run the CI-equivalent checks before handoff:

```powershell
uv sync --all-extras --locked
uv run ruff check .
uv run ruff format --check .
uv run mypy src
uv run pytest -q
uv build
docker run --rm -v "${PWD}:/work:ro" -w /work alpine:3.21 sh -c 'apk add --no-cache bash >/dev/null && bash -n infra/configure-neo4j.sh infra/configure-neo4j-runtime.sh infra/backup-neo4j.sh infra/install-neo4j-backup.sh infra/install-neo4j-backup-runtime.sh'
```

Also parse the PowerShell infrastructure scripts with the same check in
`.github/workflows/quality.yml` when any `.ps1` file changes.
