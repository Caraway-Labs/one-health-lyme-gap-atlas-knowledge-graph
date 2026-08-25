"""Canonical contracts for the One Health Lyme Gap Atlas knowledge graph."""

from importlib.resources import files
from pathlib import Path

from .contracts import (
    AssertionBasis,
    EvidencePassageNode,
    GraphContribution,
    GraphNode,
    NodeType,
    PaperNode,
    Polarity,
    RelationshipType,
    SemanticEdge,
    deterministic_id,
    relationship_allowed,
)

CONFIGURATION_VERSION = "kg-v1.0.0"


def asset_path(kind: str, name: str) -> Path:
    """Return an installed contract asset, rejecting arbitrary paths."""
    allowed = {
        ("config", "kg-v1.0.0.json"),
        ("config", "public-copy-v1.json"),
        ("schemas", "graph-v1.schema.json"),
        ("cypher", "001_graph_schema.cypher"),
    }
    if (kind, name) not in allowed:
        raise ValueError("unknown contract asset")
    installed = Path(str(files(__package__).joinpath(kind, name)))
    if installed.exists():
        return installed
    source_checkout = Path(__file__).resolve().parents[2] / kind / name
    if source_checkout.exists():
        return source_checkout
    raise FileNotFoundError(f"contract asset is missing: {kind}/{name}")


__all__ = [
    "CONFIGURATION_VERSION",
    "AssertionBasis",
    "EvidencePassageNode",
    "GraphContribution",
    "GraphNode",
    "NodeType",
    "PaperNode",
    "Polarity",
    "RelationshipType",
    "SemanticEdge",
    "asset_path",
    "deterministic_id",
    "relationship_allowed",
]
