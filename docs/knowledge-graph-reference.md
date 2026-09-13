# Knowledge graph node and edge reference

This reference describes the implemented `kg-v1.0.0` knowledge-graph contract.
It is a guide to the current schema and publisher, not a proposal to change the
ontology. The authoritative validation rules are in
`src/lyme_gap_atlas_kg/contracts.py` and the portable JSON Schema is
`schemas/graph-v1.schema.json`.

## Reading the graph

The graph separates three kinds of records:

- **Paper** records identify a permitted PubMed/PMC source.
- **EvidencePassage** records preserve the permitted quoted evidence and its
  precise position in one paper.
- **Knowledge nodes** represent the biomedical and study-context entities that
  a paper connects. A semantic relationship is stored once for each supporting
  paper/passage pair, so a relationship is evidence-specific rather than an
  uncited global fact.

`Paper -[:HAS_PASSAGE]-> EvidencePassage` is the sole structural provenance
edge. All other relationships are directed semantic edges between knowledge
nodes. Paper and evidence-passage nodes cannot be semantic-edge endpoints. The
requirements concept document calls this edge `HAS_EVIDENCE_PASSAGE`; the
implemented publisher and this reference use the actual code label,
`HAS_PASSAGE`.

## Node inventory

| Node | Properties |
| --- | --- |
| `Paper` | Common properties plus bibliographic, access, artifact, and discovery-query provenance. |
| `EvidencePassage` | Common properties plus paper linkage, permitted excerpt, location, integrity hash, extraction summary, and optional retrieval embedding. |
| `DiseaseCondition` | Common knowledge-node properties; represents a disease or condition. |
| `Pathogen` | Common knowledge-node properties; represents an infectious agent. |
| `TickVector` | Common knowledge-node properties; represents a tick capable of vector-related roles. |
| `Host` | Common knowledge-node properties; represents an organism that can carry, host, or serve as a reservoir for a pathogen. |
| `Place` | Common knowledge-node properties; represents a geographic place or study location. |
| `StudyPopulation` | Common knowledge-node properties; represents the population being studied. |
| `Exposure` | Common knowledge-node properties; represents an exposure or exposure-related condition. |
| `Outcome` | Common knowledge-node properties; represents a measured result or health outcome. |
| `Intervention` | Common knowledge-node properties; represents a preventive or therapeutic action. |
| `Diagnostic` | Common knowledge-node properties; represents a diagnostic test or approach. |
| `EnvironmentalFactor` | Common knowledge-node properties; represents an environmental condition or measurement. |

## Common node properties

Every node has the following properties. `Paper` and `EvidencePassage` are
specialized nodes; the remaining eleven node labels use the generic
`GraphNode` model.

| Property | Meaning |
| --- | --- |
| `id` | Required stable node identifier. The helper creates deterministic IDs by trimming and case-folding its input parts, joining them, and hashing the result. Neo4j enforces uniqueness for `KnowledgeNode.id`, `Paper.pmid`, and `EvidencePassage.id`. |
| `node_type` | Required finite node label. It controls the Neo4j label used by the publisher and determines whether a semantic relationship endpoint is allowed. |
| `canonical_name` | Required preferred display/lookup name, 1–500 characters. It is included in the full-text entity-name index. |
| `aliases` | Optional array of up to 100 alternative names. This supports synonym lookup and is included in the full-text entity-name index. Defaults to an empty array. |
| `external_ids` | Optional map of external-system identifier names to string values. It defaults to an empty object and holds normalization/provenance identifiers without imposing a specific vocabulary in the schema. |
| `created_at` | Required timestamp recording when the node record was created. |
| `source_configuration_version` | Required source-controlled configuration version used to produce the node. It makes node creation reproducible against a specific extraction configuration. |

## Node details

### `Paper`

`Paper` is the source-document node for one admitted PubMed article. The
pipeline admits only permitted English PMC Open Access full text, while the
paper node retains the identifiers and metadata needed to trace the graph
contribution back to that source. The Neo4j publisher creates a `Paper` node
and replaces its prior graph contribution atomically when republishing it.

In addition to the common node properties, a paper has:

| Property | Meaning |
| --- | --- |
| `pmid` | Required PubMed identifier, one to ten digits. Neo4j enforces this as unique for `Paper` nodes. |
| `pmcid` | Optional PMC identifier. It is null when a PMC identifier is unavailable. |
| `title` | Required publication title. |
| `journal` | Required journal name. |
| `publication_date` | Required source publication date string. |
| `publication_types` | Required list of PubMed publication-type labels used to establish eligibility. |
| `language` | Required source language. The admission flow accepts English full text. |
| `pubmed_url` | Required link to the PubMed record, used for public citation resolution. |
| `access_status` | Required access or license status retained from source admission. |
| `content_hash` | Required SHA-256 hash of the admitted content, expressed as 64 lowercase hexadecimal characters. |
| `full_text_object_key` | Required private object-store key for the permitted full-text artifact; the graph does not store the full paper itself. |
| `query_match_ids` | Required list of the configured PubMed query matches that discovered this paper. A paper can retain multiple discovery paths. |

### `EvidencePassage`

`EvidencePassage` is the directly cited unit of evidence. A semantic edge must
name both its `paper_id` and `evidence_passage_id`, so the chatbot can return a
claim with a paper citation and the system can verify its evidence lineage. The
passage text is vector-indexed for retrieval; the model field excludes the
embedding from normal Pydantic serialization but the Neo4j publisher explicitly
adds it for storage.

| Property | Meaning |
| --- | --- |
| `paper_id` | Required ID of the source `Paper`. The publisher uses it to create the structural `HAS_PASSAGE` edge. |
| `excerpt` | Required permitted exact source excerpt, 1–8,000 characters. |
| `section_label` | Required source section name or label. |
| `character_start` | Required zero-based starting offset in the normalized article text. |
| `character_end` | Required ending offset. It must be greater than `character_start`. |
| `excerpt_hash` | Required SHA-256 hash of the excerpt, expressed as 64 lowercase hexadecimal characters. |
| `extraction_summary` | Required 1–2,000-character concise description of what the passage contributes to extraction. |
| `embedding` | Optional array of numeric vector values for similarity retrieval. The configured embedding dimension is 1,024 and Neo4j maintains a cosine vector index on this property. |

### `DiseaseCondition`

Represents the disease or health condition side of a literature claim, such as
Lyme disease. It can be the target of `CAUSES`, `PREVENTS`, `TREATS`, or
`DIAGNOSES`, and can participate in association, location, exposure, outcome,
or evaluation relationships when the endpoint matrix permits it.

Its implemented properties are exactly the common node properties. The concept
document describes future/detail expectations such as a preferred label,
disease family, and ontology or MeSH identifiers; those are not separate
validated fields in `kg-v1.0.0` and should therefore be represented, where
appropriate, through `canonical_name` and `external_ids`.

### `Pathogen`

Represents an infectious agent, such as a *Borrelia* organism. It can be
transmitted or carried by a tick vector, infect a host or study population, be
a host reservoir target, cause a disease/outcome, or be diagnosed.

Its implemented properties are the common node properties only. The concept
document names scientific name, strain, class, and NCBI Taxonomy ID as desired
domain detail; only the normalized name and optional external-ID map are
currently contract fields.

### `TickVector`

Represents a tick vector entity. The endpoint matrix permits it to `TRANSMITS`
or `CARRIES` a pathogen and to `EXPOSES_TO` a population, host, or condition.
It may also use the general association and location patterns.

Its implemented properties are the common node properties only. Scientific and
common names, taxonomy, life stage, and vector-role context are conceptual
attributes rather than dedicated schema properties in this version.

### `Host`

Represents an organism that is relevant as a host or possible reservoir. It can
`CARRIES` a pathogen, be `INFECTS`-ed by a pathogen, or be a `RESERVOIR_FOR`
a pathogen. It can also be the target of `EXPOSES_TO`.

Its implemented properties are the common node properties only. Scientific and
common name, host class, taxonomy, and host-role context are not individually
validated fields; use the canonical name and external identifiers for the
implemented representation.

### `Place`

Represents a geographic context, such as a study site or exposure location.
It is the target of `OCCURS_IN`; the contract intentionally excludes `Place`
as the source of that relation. Geography can also be recorded on an edge's
`study_geography_ids` when it describes the study rather than a semantic fact.

Its implemented properties are the common node properties only. Normalized
place name, geographic level, code system/code, and contextual role are
described in the concept document but are not standalone schema fields.

### `StudyPopulation`

Represents the people, animals, or other population observed by a study. It can
be infected, exposed, or be the context for an association or location claim.
It should not be confused with a `Host`: `StudyPopulation` models the sampled
or analyzed group, while `Host` models a biological host entity.

Its implemented properties are the common node properties only. Population
description, species/category, setting, age range, and sample size are intended
domain detail but are not dedicated schema properties in this version.

### `Exposure`

Represents an exposure or exposure-related condition. It can `EXPOSES_TO` a
population, host, or disease condition; may `CAUSES` a disease/outcome; can
have an outcome; and can be evaluated or influence other entity types.

Its implemented properties are the common node properties only. Normalized
exposure name, category, measurement method, and asserted time window are
documented expectations rather than individually validated fields.

### `Outcome`

Represents a measured result or health outcome. It is a target for causal,
preventive, therapeutic, outcome, and evaluation relationships, which lets the
graph distinguish an intervention from the result it is evaluated against.

Its implemented properties are the common node properties only. Outcome
category, definition/measurement, and time window are not specialized schema
fields in the current contract.

### `Intervention`

Represents a preventive or treatment action. It can `PREVENTS` or `TREATS` a
disease condition or outcome, `HAS_OUTCOME`, and `EVALUATES` an outcome or
disease condition. The first three causal/clinical relation types require an
explicit assertion basis.

Its implemented properties are the common node properties only. Intervention
category, delivery context, and target are conceptual detail, not dedicated
validated fields today.

### `Diagnostic`

Represents a test or diagnostic approach. It can `DIAGNOSES` a disease condition
or pathogen. Because diagnostic claims can be clinically consequential,
`DIAGNOSES` requires directly explicit evidence, not an inferred assertion.

Its implemented properties are the common node properties only. Diagnostic
category, analyte/condition, and result interpretation remain conceptual
properties rather than separately enforced fields.

### `EnvironmentalFactor`

Represents an environmental condition, such as climate or habitat-related
information. It can cause a disease/outcome, expose entities, or influence a
non-environmental/non-exposure entity. It may not be an `INFLUENCES` target
under the current endpoint matrix.

Its implemented properties are the common node properties only. Factor
category, measurement/unit, asserted value/range, and time window are not
specialized schema properties in `kg-v1.0.0`.

## Edge inventory

| Edge | Properties |
| --- | --- |
| `HAS_PASSAGE` | Structural `Paper` → `EvidencePassage` provenance link; it has no modeled edge-property payload. |
| `ASSOCIATED_WITH` | Semantic-edge provenance and claim properties; any knowledge-node type may connect to any other. |
| `CAUSES` | Semantic-edge properties; Pathogen, Exposure, or EnvironmentalFactor → DiseaseCondition or Outcome. |
| `TRANSMITS` | Semantic-edge properties; TickVector → Pathogen. |
| `CARRIES` | Semantic-edge properties; TickVector or Host → Pathogen. |
| `INFECTS` | Semantic-edge properties; Pathogen → Host or StudyPopulation. |
| `RESERVOIR_FOR` | Semantic-edge properties; Host → Pathogen. |
| `EXPOSES_TO` | Semantic-edge properties; Exposure, EnvironmentalFactor, or TickVector → StudyPopulation, Host, or DiseaseCondition. |
| `PREVENTS` | Semantic-edge properties; Intervention → DiseaseCondition or Outcome. |
| `TREATS` | Semantic-edge properties; Intervention → DiseaseCondition or Outcome. |
| `DIAGNOSES` | Semantic-edge properties; Diagnostic → DiseaseCondition or Pathogen. |
| `HAS_OUTCOME` | Semantic-edge properties; DiseaseCondition, Exposure, or Intervention → Outcome. |
| `OCCURS_IN` | Semantic-edge properties; any non-Place knowledge node → Place. |
| `INFLUENCES` | Semantic-edge properties; EnvironmentalFactor or Exposure → a knowledge node other than EnvironmentalFactor or Exposure. |
| `EVALUATES` | Semantic-edge properties; Intervention, Diagnostic, or Exposure → Outcome or DiseaseCondition. |

## Common semantic-edge properties

Every semantic edge carries the following properties. The publisher stores
these properties on the Neo4j relationship itself and creates one relationship
per supporting paper/passage contribution.

| Property | Meaning |
| --- | --- |
| `id` | Required stable edge identifier. |
| `relationship_type` | Required one of the 14 approved semantic edge types listed above. Generic `MENTIONS` and `RELATED_TO` are not part of the enum. |
| `source_node_id` / `source_node_type` | Required identifier and type of the directed relationship source. The type is validated against the relationship endpoint matrix. |
| `target_node_id` / `target_node_type` | Required identifier and type of the directed relationship target. The target type is also validated against the endpoint matrix. |
| `paper_id` | Required ID of the paper that supports this particular assertion. |
| `evidence_passage_id` | Required ID of the direct supporting passage. This creates the claim-to-evidence provenance path. |
| `assertion_basis` | Required derivation classification: `explicit`, `inferred_single_source`, `inferred_multi_source`, or `curated`. |
| `claim_text` | Required human-readable extracted claim, 1–4,000 characters. The named passage must directly support it. |
| `polarity` | Required evidence direction: `supports`, `does_not_support`, or `mixed`. This preserves conflicting findings rather than hiding them. |
| `study_design` | Optional study-design description. |
| `study_geography_ids` | Optional list of geographic identifiers describing study context; defaults to an empty list. |
| `study_period` | Optional period string describing study context. |
| `extraction_configuration_version` | Required immutable configuration version for the extraction/model route that created the assertion. |
| `created_at` | Required edge-creation timestamp. |

## Edge details and validation rules

### `HAS_PASSAGE`

This is the only structural edge: `Paper -[:HAS_PASSAGE]-> EvidencePassage`.
It is created by the publisher from the passage's `paper_id`, rather than being
included in the `SemanticEdge` payload. Its purpose is source navigation and
provenance; it is not an extracted biomedical claim.

### `ASSOCIATED_WITH`

Represents a supported association without asserting causality. Any two
knowledge-node types may be its endpoints. It is one of only three semantic
types that may use an inferred basis (`inferred_single_source` or
`inferred_multi_source`); explicit and curated assertions are also permitted.

### `CAUSES`

Represents an asserted causal relationship from a pathogen, exposure, or
environmental factor to a disease condition or outcome. The contract requires
`assertion_basis: explicit`; a model may not infer this relationship.

### `TRANSMITS`

Represents vector-to-pathogen transmission: `TickVector → Pathogen`. Its
direction records the vector as the transmitter and the pathogen as what is
transmitted. It requires an explicit or curated basis; inference is prohibited.

### `CARRIES`

Represents a tick vector or host carrying a pathogen:
`TickVector|Host → Pathogen`. It is narrower than an association and does not
by itself assert transmission, infection, or reservoir status.

### `INFECTS`

Represents a pathogen infecting a host or study population:
`Pathogen → Host|StudyPopulation`. This directional form distinguishes an
infectious relationship from a host simply carrying the pathogen.

### `RESERVOIR_FOR`

Represents a host serving as a reservoir for a pathogen: `Host → Pathogen`.
This requires evidence appropriate to that stronger ecological role; it is not
automatically implied by `CARRIES`.

### `EXPOSES_TO`

Represents an exposure, environmental factor, or tick vector exposing a study
population, host, or disease condition. The direction is
`Exposure|EnvironmentalFactor|TickVector → StudyPopulation|Host|DiseaseCondition`.

### `PREVENTS`

Represents an intervention preventing a disease condition or outcome:
`Intervention → DiseaseCondition|Outcome`. It must be an explicit assertion,
which protects against treating a weak association as clinical prevention.

### `TREATS`

Represents an intervention treating a disease condition or outcome:
`Intervention → DiseaseCondition|Outcome`. It also requires explicit evidence
and should be interpreted with its edge-level polarity and cited passage.

### `DIAGNOSES`

Represents a diagnostic approach diagnosing a disease condition or pathogen:
`Diagnostic → DiseaseCondition|Pathogen`. It requires an explicit assertion
and is not a general statement that the diagnostic is merely associated with
the condition.

### `HAS_OUTCOME`

Connects a disease condition, exposure, or intervention to an outcome. It is
useful for recording what was measured without implying that the source caused
the outcome. Its direction is `DiseaseCondition|Exposure|Intervention → Outcome`.

### `OCCURS_IN`

Connects any knowledge-node type other than `Place` to a place:
`non-Place entity → Place`. It may be explicit or inferred, allowing a study
context to be normalized into a location relation while preserving the basis.

### `INFLUENCES`

Represents an environmental factor or exposure influencing another knowledge
node, except an environmental factor or exposure:
`EnvironmentalFactor|Exposure → other entity`. It can be explicit or inferred,
but the endpoints intentionally prevent chaining the relation between two
factors/exposures in this version.

### `EVALUATES`

Represents an intervention, diagnostic, or exposure evaluating an outcome or
disease condition:
`Intervention|Diagnostic|Exposure → Outcome|DiseaseCondition`. It models study
evaluation context rather than an automatically favorable clinical result.

## Important implementation boundaries

- Validation rejects unknown properties on nodes and semantic edges. Therefore,
  descriptive attributes named only in the concept document are not safe to
  emit as top-level node fields in v1.
- Relationship endpoint types, explicit-only relations, and inferred-only
  allowances are enforced by the `SemanticEdge` model before publication.
- The implementation allows `curated` for any allowed relationship, while
  inferred values are limited to `ASSOCIATED_WITH`, `OCCURS_IN`, and
  `INFLUENCES`.
- A Neo4j publication deletes the existing paper, its passages, and all edges
  with that `paper_id` before recreating the submitted contribution in one
  write transaction. Shared knowledge nodes are merged by ID and remain.
