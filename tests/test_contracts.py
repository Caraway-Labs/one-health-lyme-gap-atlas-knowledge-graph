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
