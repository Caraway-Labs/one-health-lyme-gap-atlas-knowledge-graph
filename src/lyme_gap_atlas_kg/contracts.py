"""Finite typed graph contract with deterministic identities."""

from __future__ import annotations

import hashlib
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class NodeType(StrEnum):
    PAPER = "Paper"
    EVIDENCE_PASSAGE = "EvidencePassage"
    DISEASE_CONDITION = "DiseaseCondition"
    PATHOGEN = "Pathogen"
    TICK_VECTOR = "TickVector"
    HOST = "Host"
    PLACE = "Place"
    STUDY_POPULATION = "StudyPopulation"
    EXPOSURE = "Exposure"
    OUTCOME = "Outcome"
    INTERVENTION = "Intervention"
    DIAGNOSTIC = "Diagnostic"
    ENVIRONMENTAL_FACTOR = "EnvironmentalFactor"


class RelationshipType(StrEnum):
    ASSOCIATED_WITH = "ASSOCIATED_WITH"
    CAUSES = "CAUSES"
    TRANSMITS = "TRANSMITS"
    CARRIES = "CARRIES"
    INFECTS = "INFECTS"
    RESERVOIR_FOR = "RESERVOIR_FOR"
    EXPOSES_TO = "EXPOSES_TO"
    PREVENTS = "PREVENTS"
    TREATS = "TREATS"
    DIAGNOSES = "DIAGNOSES"
    HAS_OUTCOME = "HAS_OUTCOME"
    OCCURS_IN = "OCCURS_IN"
    INFLUENCES = "INFLUENCES"
    EVALUATES = "EVALUATES"


class AssertionBasis(StrEnum):
    EXPLICIT = "explicit"
    INFERRED_SINGLE_SOURCE = "inferred_single_source"
    INFERRED_MULTI_SOURCE = "inferred_multi_source"
    CURATED = "curated"


class Polarity(StrEnum):
    SUPPORTS = "supports"
    DOES_NOT_SUPPORT = "does_not_support"
    MIXED = "mixed"


ExplicitOnly = {
    RelationshipType.CAUSES,
    RelationshipType.TREATS,
    RelationshipType.PREVENTS,
    RelationshipType.DIAGNOSES,
}
InferredAllowed = {
    RelationshipType.ASSOCIATED_WITH,
    RelationshipType.OCCURS_IN,
    RelationshipType.INFLUENCES,
}

_ENTITY_TYPES = set(NodeType) - {NodeType.PAPER, NodeType.EVIDENCE_PASSAGE}
_ALLOWED_ENDPOINTS: dict[RelationshipType, tuple[set[NodeType], set[NodeType]]] = {
    RelationshipType.ASSOCIATED_WITH: (_ENTITY_TYPES, _ENTITY_TYPES),
    RelationshipType.CAUSES: (
        {NodeType.PATHOGEN, NodeType.EXPOSURE, NodeType.ENVIRONMENTAL_FACTOR},
        {NodeType.DISEASE_CONDITION, NodeType.OUTCOME},
    ),
    RelationshipType.TRANSMITS: ({NodeType.TICK_VECTOR}, {NodeType.PATHOGEN}),
    RelationshipType.CARRIES: ({NodeType.TICK_VECTOR, NodeType.HOST}, {NodeType.PATHOGEN}),
    RelationshipType.INFECTS: ({NodeType.PATHOGEN}, {NodeType.HOST, NodeType.STUDY_POPULATION}),
    RelationshipType.RESERVOIR_FOR: ({NodeType.HOST}, {NodeType.PATHOGEN}),
    RelationshipType.EXPOSES_TO: (
        {NodeType.EXPOSURE, NodeType.ENVIRONMENTAL_FACTOR, NodeType.TICK_VECTOR},
        {NodeType.STUDY_POPULATION, NodeType.HOST, NodeType.DISEASE_CONDITION},
    ),
    RelationshipType.PREVENTS: (
        {NodeType.INTERVENTION},
        {NodeType.DISEASE_CONDITION, NodeType.OUTCOME},
    ),
    RelationshipType.TREATS: (
        {NodeType.INTERVENTION},
        {NodeType.DISEASE_CONDITION, NodeType.OUTCOME},
    ),
    RelationshipType.DIAGNOSES: (
        {NodeType.DIAGNOSTIC},
        {NodeType.DISEASE_CONDITION, NodeType.PATHOGEN},
    ),
    RelationshipType.HAS_OUTCOME: (
        {NodeType.DISEASE_CONDITION, NodeType.EXPOSURE, NodeType.INTERVENTION},
        {NodeType.OUTCOME},
    ),
    RelationshipType.OCCURS_IN: (_ENTITY_TYPES - {NodeType.PLACE}, {NodeType.PLACE}),
    RelationshipType.INFLUENCES: (
        {NodeType.ENVIRONMENTAL_FACTOR, NodeType.EXPOSURE},
        _ENTITY_TYPES - {NodeType.ENVIRONMENTAL_FACTOR, NodeType.EXPOSURE},
    ),
    RelationshipType.EVALUATES: (
        {NodeType.INTERVENTION, NodeType.DIAGNOSTIC, NodeType.EXPOSURE},
        {NodeType.OUTCOME, NodeType.DISEASE_CONDITION},
    ),
}


def deterministic_id(namespace: str, *parts: str) -> str:
    normalized = "\x1f".join(part.strip().casefold() for part in parts)
    return f"{namespace}:{hashlib.sha256(normalized.encode()).hexdigest()[:32]}"


def relationship_allowed(
    relationship: RelationshipType, source: NodeType, target: NodeType
) -> bool:
    sources, targets = _ALLOWED_ENDPOINTS[relationship]
    return source in sources and target in targets and source != NodeType.EVIDENCE_PASSAGE


class GraphNode(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    node_type: NodeType
    canonical_name: Annotated[str, Field(min_length=1, max_length=500)]
    aliases: list[str] = Field(default_factory=list, max_length=100)
    external_ids: dict[str, str] = Field(default_factory=dict)
    created_at: datetime
    source_configuration_version: str


class PaperNode(GraphNode):
    node_type: NodeType = NodeType.PAPER
    pmid: Annotated[str, Field(pattern=r"^\d{1,10}$")]
    pmcid: str | None = None
    title: str
    journal: str
    publication_date: str
    publication_types: list[str]
    language: str
    pubmed_url: str
    access_status: str
    content_hash: Annotated[str, Field(pattern=r"^[a-f0-9]{64}$")]
    full_text_object_key: str
    query_match_ids: list[str]


class EvidencePassageNode(GraphNode):
    node_type: NodeType = NodeType.EVIDENCE_PASSAGE
    paper_id: str
    excerpt: Annotated[str, Field(min_length=1, max_length=8_000)]
    section_label: str
    character_start: Annotated[int, Field(ge=0)]
    character_end: Annotated[int, Field(gt=0)]
    excerpt_hash: Annotated[str, Field(pattern=r"^[a-f0-9]{64}$")]
    extraction_summary: Annotated[str, Field(min_length=1, max_length=2_000)]
    embedding: list[float] | None = Field(default=None, exclude=True)

    @model_validator(mode="after")
    def offsets_are_ordered(self) -> EvidencePassageNode:
        if self.character_end <= self.character_start:
            raise ValueError("character_end must be greater than character_start")
        return self


class SemanticEdge(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    relationship_type: RelationshipType
    source_node_id: str
    source_node_type: NodeType
    target_node_id: str
    target_node_type: NodeType
    paper_id: str
    evidence_passage_id: str
    assertion_basis: AssertionBasis
    claim_text: Annotated[str, Field(min_length=1, max_length=4_000)]
    polarity: Polarity
    study_design: str | None = None
    study_geography_ids: list[str] = Field(default_factory=list)
    study_period: str | None = None
    extraction_configuration_version: str
    created_at: datetime

    @model_validator(mode="after")
    def validate_semantics(self) -> SemanticEdge:
        if not relationship_allowed(
            self.relationship_type, self.source_node_type, self.target_node_type
        ):
            raise ValueError("relationship endpoints are not allowed")
        if (
            self.relationship_type in ExplicitOnly
            and self.assertion_basis != AssertionBasis.EXPLICIT
        ):
            raise ValueError("relationship requires an explicit assertion")
        if (
            self.assertion_basis
            in {
                AssertionBasis.INFERRED_SINGLE_SOURCE,
                AssertionBasis.INFERRED_MULTI_SOURCE,
            }
            and self.relationship_type not in InferredAllowed
        ):
            raise ValueError("inference is not allowed for this relationship")
        return self


class GraphContribution(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    configuration_version: Literal["kg-v1.0.0"]
    paper: PaperNode
    passages: list[EvidencePassageNode]
    nodes: list[GraphNode]
    edges: list[SemanticEdge]
