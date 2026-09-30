import json
from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from lyme_gap_atlas_kg import (
    CONFIGURATION_VERSION,
    AssertionBasis,
    NodeType,
    RelationshipType,
    SemanticEdge,
    asset_path,
    deterministic_id,
    relationship_allowed,
)


def test_packaged_configuration_is_versioned() -> None:
    configuration = json.loads(asset_path("config", "kg-v1.0.0.json").read_text())
    assert configuration["configuration_version"] == CONFIGURATION_VERSION


def test_evaluation_corpus_meets_v1_minimum() -> None:
    corpus = asset_path("config", "kg-v1.0.0.json").parents[1] / "evals" / "chat-v1.jsonl"
    if corpus.exists():
        examples = [json.loads(line) for line in corpus.read_text().splitlines() if line]
        assert len(examples) >= 40
        assert {
            "surveillance_epidemiology",
            "vector_host_pathogen",
            "environment_exposure",
            "diagnostics_interventions_outcomes",
            "conflicting_evidence",
            "medical_safety",
            "prompt_injection",
            "no_evidence",
        } <= {item["category"] for item in examples}


def test_deterministic_ids_are_normalized() -> None:
    assert deterministic_id("node", " Lyme ", "DISEASE") == deterministic_id(
        "node", "lyme", "disease"
    )


def test_relationship_matrix_is_finite() -> None:
    assert relationship_allowed(RelationshipType.TRANSMITS, NodeType.TICK_VECTOR, NodeType.PATHOGEN)
    assert not relationship_allowed(RelationshipType.TRANSMITS, NodeType.PAPER, NodeType.PATHOGEN)


def test_explicit_relationship_rejects_inference() -> None:
    with pytest.raises(ValidationError):
        SemanticEdge(
            id="edge:1",
            relationship_type=RelationshipType.CAUSES,
            source_node_id="pathogen:1",
            source_node_type=NodeType.PATHOGEN,
            target_node_id="disease:1",
            target_node_type=NodeType.DISEASE_CONDITION,
            paper_id="paper:1",
            evidence_passage_id="passage:1",
            assertion_basis=AssertionBasis.INFERRED_SINGLE_SOURCE,
            claim_text="The passage does not explicitly state causality.",
            polarity="supports",
            extraction_configuration_version="kg-v1.0.0",
            created_at=datetime.now(UTC),
        )


def test_neo4j_bootstrap_preserves_the_private_runtime_contract() -> None:
    script = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "configure-neo4j.sh"
    source = script.read_text()

    assert "NEO4J_RUNTIME_PASSWORD:?shared graph runtime password required" in source
    assert "CREATE USER graph_runtime IF NOT EXISTS" in source
    assert "ALTER USER graph_runtime SET PASSWORD" in source
    assert '--publish "${PRIVATE_IP}:7687:7687"' in source
    assert ":7474" not in source
    assert 'NEO4J_PASSWORD="${NEO4J_ADMIN_PASSWORD}"' in source


def test_neo4j_provisioning_creates_a_vpc_scoped_firewall() -> None:
    script = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "Provision-Neo4j.ps1"
    source = script.read_text()

    assert "[string]$SshAllowedCidr" in source
    assert "doctl vpcs get $VpcUuid" in source
    assert "ports:7687,address:$($vpc[0].ip_range)" in source
    assert "doctl compute firewall create" in source
    assert "doctl compute firewall update" in source


def test_local_dev_tunnel_keeps_bolt_private() -> None:
    script = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "Open-Neo4jDevTunnel.ps1"
    source = script.read_text()

    assert "Get-NetTCPConnection" in source
    assert '& ssh -N -L "${LocalPort}:${PrivateIp}:7687" "root@$SshHost"' in source
    assert "bolt://localhost:$LocalPort" in source


def test_backup_installer_uses_a_protected_daily_systemd_timer() -> None:
    script = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "install-neo4j-backup.sh"
    source = script.read_text()

    assert "install -d -m 0700 /etc/neo4j-atlas" in source
    assert "install -d -o 7474 -g 7474 -m 0700 /mnt/neo4j/backups" in source
    assert "AWS_CLI_IMAGE=amazon/aws-cli:2.15.0" in source
    assert "EnvironmentFile=/etc/neo4j-atlas/backup.env" in source
    assert "OnCalendar=*-*-* 10:30:00 UTC" in source
    assert "systemctl enable --now neo4j-atlas-backup.timer" in source
    assert "unset SPACES_ACCESS_KEY_ID SPACES_SECRET_ACCESS_KEY" in source


def test_quality_workflow_runs_all_contract_and_infrastructure_checks() -> None:
    workflow = (
        asset_path("config", "kg-v1.0.0.json").parents[1] / ".github" / "workflows" / "quality.yml"
    )
    source = workflow.read_text()

    assert "pull_request:" in source
    assert "uv run pytest -q" in source
    assert "uv run mypy src" in source
    assert "uv build" in source
    assert "bash -n infra/configure-neo4j.sh infra/configure-neo4j-runtime.sh" in source
    assert "infra/backup-neo4j.sh infra/install-neo4j-backup.sh" in source
    assert "infra/install-neo4j-backup-runtime.sh" in source
    assert "infra/Provision-Neo4j.ps1" in source
    assert "infra/Configure-Neo4jRuntime.ps1" in source
    assert "infra/Install-Neo4jBackup.ps1" in source


def test_runtime_configuration_helper_keeps_passwords_off_the_command_line() -> None:
    script = (
        asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "Configure-Neo4jRuntime.ps1"
    )
    source = script.read_text()

    assert "NEO4J_RUNTIME_PASSWORD is required" in source
    assert "scp $inputFile.FullName" in source
    assert "configure-neo4j-runtime.sh" in source
    assert "sed -i 's/\\r$//' /tmp/configure-neo4j.sh /tmp/configure-neo4j-runtime.sh" in source
    assert "trap 'rm -f /tmp/configure-neo4j.sh" in source
    assert (
        "rm -f /tmp/configure-neo4j.sh /tmp/configure-neo4j-runtime.sh /tmp/neo4j-runtime-input"
        in source
    )

    wrapper = script.with_name("configure-neo4j-runtime.sh").read_text()
    assert 'IFS= read -r NEO4J_RUNTIME_PASSWORD < "$input" || true' in wrapper
    assert 'test -n "$NEO4J_RUNTIME_PASSWORD"' in wrapper
    assert 'NEO4J_ADMIN_PASSWORD="$(sed -n \'2p\' "$input")"' in wrapper
    assert "sed -n 's/^NEO4J_AUTH=//p' /etc/neo4j-atlas/runtime.env" in wrapper


def test_backup_configuration_helper_passes_only_protected_host_input() -> None:
    helper = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "Install-Neo4jBackup.ps1"
    source = helper.read_text()
    assert "SPACES_SECRET_ACCESS_KEY" in source
    assert "scp $inputFile.FullName" in source
    assert "install-neo4j-backup-runtime.sh" in source
    assert "rm -f /tmp/backup-neo4j.sh" in source
    assert "trap cleanup EXIT" in source

    wrapper = helper.with_name("install-neo4j-backup-runtime.sh").read_text()
    assert 'mapfile -t values < "$input"' in wrapper
    assert "Neo4j backup input is incomplete" in wrapper
    assert "exec /tmp/install-neo4j-backup.sh" in wrapper


def test_backup_upload_uses_the_pinned_aws_cli_container() -> None:
    script = asset_path("config", "kg-v1.0.0.json").parents[1] / "infra" / "backup-neo4j.sh"
    source = script.read_text()

    assert "AWS_CLI_IMAGE:=amazon/aws-cli:2.15.0" in source
    assert '"${AWS_CLI_IMAGE}" s3 cp /backups' in source
    assert "--volume /mnt/neo4j/backups:/backups:ro" in source
