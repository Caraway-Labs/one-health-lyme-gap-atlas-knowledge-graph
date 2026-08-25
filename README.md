# One Health Lyme Gap Atlas Knowledge Graph

This repository is the canonical, language-neutral contract for the governed
literature knowledge graph and public evidence chatbot. Version `kg-v1.0.0`
contains the finite ontology, deterministic identity rules, JSON configuration,
public copy, graph schema, evaluation fixtures, and reviewed infrastructure
automation.

It does not contain credentials and its infrastructure commands default to a
non-mutating preview. Creating paid cloud resources, publishing the release tag,
or enabling public chat requires the project owner's recorded approval.

## Local verification

```powershell
uv sync --all-extras
uv run ruff check .
uv run ruff format --check .
uv run mypy src
uv run pytest
uv build
```

The Python wheel embeds `config/`, `schemas/`, and `cypher/`. The JSON files are
also exported by `package.json` for the web repository's pinned Git dependency.
