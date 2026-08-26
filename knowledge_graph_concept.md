# TopX Lyme Project: PubMed Literature Ingestion and Knowledge Graph

## Confirmed v1 requirements

This section records decisions confirmed during the requirements interview. It
supersedes any conflicting proposed detail elsewhere in this document. It is a
requirements record only; it does not authorize implementation.

### Product and public-access scope

- V1 is a production, public feature available without user accounts or
  authentication.
- V1 UI scope is a multi-turn RAG Chatbot Agent only. It has a simple
  non-streaming `Processing...` state while an answer is generated.
- The browser calls the existing Python REST API. The API owns the chatbot
  model, graph-retrieval tools, citation assembly, and all business logic. The
  browser never connects directly to Neo4j or an LLM provider.
- V1 exposes one public chatbot endpoint. Paper/entity/relationship endpoints,
  a visual graph browser, and other graph-exploration UI are future scope.
- The API is public but guarded: server-side bounds, rate limits, abuse
  controls, and monitoring protect it. Restrictive CORS is browser hygiene,
  not an attempt to make a public API secret.
- The chatbot must answer only from Neo4j data. When no relevant graph evidence
  exists, it explicitly says so rather than using general model knowledge.
- If Neo4j retrieval is unavailable, times out, or produces no usable evidence,
  the chatbot fails closed. It does not invoke an LLM fallback based on general
  knowledge. The distinct user-facing messages for temporary evidence-service
  unavailability and no supporting evidence found are source-controlled,
  non-secret configuration text so the copy can be iterated without a UI code
  change.
- Each substantive claim has one or more clickable PubMed citations. The links
  open the cited paper in a new browser tab. Conflicting findings are described
  transparently with citations to the conflicting evidence.

### Conversation handling and telemetry

- Multi-turn context is supported within an anonymous browser session.
- The UI keeps a user's five most recent conversations in local browser
  storage. They expire after 30 days, and the user can delete one conversation
  or clear all saved conversations.
- The API has server-side, non-public `persist_conversations` and
  `conversation_retention_days` settings. When persistence is enabled,
  conversations retain prompts, responses, citations, and necessary
  generation/query context; the retention default is 30 days. When disabled,
  conversation content is not persisted server-side.
- Privacy-conscious operational telemetry and error/audit records are retained
  regardless of conversation-persistence setting.
- A scheduled discovery run, extraction run, Neo4j backup, or restore test that
  exhausts its configured retries creates a durable audit record and structured
  error log. A custom outbound Slack/email/event alert sink is explicitly
  deferred for the initial production release; DigitalOcean infrastructure and
  uptime alerts remain enabled. V1 adds no separate public status UI or
  notification product.
- The public chatbot API has configuration-driven, monitored abuse and cost
  controls. Initial defaults are ten questions per IP address per ten-minute
  window, no more than three simultaneous requests per IP address, a
  1,000-character question limit, and a 30-second response timeout. A limited
  request receives HTTP 429; these limits may be revised through tracked
  configuration as observed use warrants.
- The chat experience displays a compact medical-use notice adjacent to the
  input. Its initial tracked configuration text is: "Research information only;
  not medical advice, diagnosis, or treatment guidance. Consult a qualified
  clinician for personal health decisions." The API declines personalized
  diagnosis and treatment instructions. The notice copy is source-controlled,
  non-secret configuration so it can be updated without a UI code change.

### Literature corpus and processing policy

- Discovery uses PubMed. Permitted full text comes only from the PMC Open
  Access collection. V1 processes English-language full text only.
- V1 has no geographic discovery filter. Study geography is extracted when
  available as context, not as an inclusion gate.
- The initial backfill covers the most recent 20 years, works newest year first,
  and is resumable in batches. Batch size and extraction-worker concurrency are
  tracked, non-secret runtime configuration with conservative initial values.
- After backfill, team-managed, versioned PubMed query families run weekly.
  Public users cannot initiate discovery. One canonical PMID is processed once
  even if it matches multiple query families, and every match is retained for
  provenance.
- Eligible publication types are research articles, systematic reviews,
  meta-analyses, and relevant surveillance reports. Editorials, news, comments,
  and corrections are not graph-evidence sources.
- Paper metadata and processing state live in Snowflake. Permitted immutable
  full-text artifacts live in a private, versioned DigitalOcean Spaces bucket;
  Snowflake records access/license status, content hash, and object pointer.
  Neo4j stores graph data and source references, not full papers.
- A successfully processed paper is never reprocessed in v1. Failures before
  successful processing retry a configurable number of times before becoming
  `failed_final`. A successfully processed paper with no valid relationships is
  still `processed`, with zero graph relationships.
- A paper becomes `processed` only after its complete validated graph
  contribution is committed; incomplete results are not available to RAG.
- Raw LLM extraction output is not retained. The retained record consists of
  permitted source text, validated graph data, evidence passages, paper
  metadata, and configuration/version references.
- Monitoring for retractions, corrections, errata, and any post-processing
  source-status action is deferred beyond v1.

### Review and operational controls

#### Accepted Neo4j Community authorization debt (2026-08-26)

- Neo4j Community does not provide database-enforced reader/writer roles. V1
  therefore uses one shared, trusted server-side `graph_runtime` identity for
  the API and pipeline; this is accepted security debt, not least privilege.
- The compensating controls are private-VPC-only Bolt, a Cloud Firewall, fixed
  API retrieval templates, no arbitrary Cypher interface, protected runtime
  secret storage, human-approved publication, and disabled public chat until
  the live acceptance record is signed.
- Enterprise RBAC or a separately governed internal retrieval gateway must be
  reconsidered before public-scope expansion or additional graph consumers.

- `papers_require_human_review` is a global, tracked pipeline setting captured
  on each paper record. Its initial PROD value is `true`; a later change to
  automatic ingestion is a simple, source-controlled configuration change with
  an audit record. V1 does not require a model-evaluation threshold or other
  blocking gate before the setting can be changed to `false`.
  When true, an internal Snowflake Streamlit application reviews a paper before
  its full text is sent to the LLM.
- The review application reuses the existing owner-rights Streamlit role pattern
  `OH_LYME_<ENV>_STREAMLIT_OWNER` and its authenticated viewer-attribution
  model. It does not create a new reviewer role. The reviewer sees the search
  match, paper metadata/abstract, access status, and PubMed link and selects
  `approved`, `rejected`, or `deferred`.
- The pending-paper queue supports easy multi-selection and batch decisions for
  more than one paper at a time.
- An approval immediately queues the paper for extraction. Approval is final
  authorization for processing and graph insertion; v1 does not revoke an
  approved paper or remove its graph contribution later.
- LLM vendor, model, prompt, tools, and related settings are source-controlled,
  non-secret configuration. Every extraction run and persisted conversation
  references an immutable LLM-configuration version.
- The initial extraction model is GPT OSS 120B, configured through its Groq
  provider integration. Before sending a paper, the pipeline estimates the
  complete request token count: normalized permitted full text, fixed
  instructions, output schema, and reserved output capacity. If that estimate
  exceeds the configured GPT OSS 120B context budget (initially 130,000
  tokens), extraction automatically routes to GPT-5.6 Luna instead. The chosen
  route, estimated token count, threshold, provider/model identifier, and
  configuration version are recorded for the paper. This is a deterministic
  capacity fail-safe, not a quality-based escalation or a silent truncation of
  source text.
- Configurable daily/monthly budgets apply to paper processing and chat. When
  paper-processing budget is exhausted, queued work waits until the next day.
- DEV and PROD are separate. DEV has no UI; it contains the database, pipeline,
  and API only when testing needs it. A future start/stop script will stop DEV
  compute and suspend its warehouse while preserving DEV data stores.
- Neo4j is self-hosted on DigitalOcean for both DEV and PROD. It runs as a
  stateful service on persistent Droplet-attached storage, not as an App
  Platform component. The DEV cost-control script must destroy idle compute,
  not merely power it off, because powered-off Droplets continue to incur
  compute charges.
- Production Neo4j has an automated daily logical backup to a private
  DigitalOcean Spaces bucket, with 30-day retention and a quarterly documented
  restore test. The backup is a recovery control for the graph and provenance;
  it is not a substitute for normal access controls or source-data retention.
- Public production enablement requires both automated checks and a recorded
  live acceptance run. The run verifies a small approved-paper sample
  end-to-end: discovery and rights checks, review decision, extraction routing,
  Neo4j provenance, PubMed citation links, medical-safety behavior, rate
  limiting, backup creation, and rollback readiness. Green CI alone is not
  sufficient release evidence.

### Graph and RAG contract

- The graph is finite and typed. Molecular-detail nodes (genes, proteins,
  variants, chemicals) are out of scope for v1.
- V1 node types are: `Paper`, `EvidencePassage`, `DiseaseCondition`,
  `Pathogen`, `TickVector`, `Host`, `Place`, `StudyPopulation`, `Exposure`,
  `Outcome`, `Intervention`, `Diagnostic`, and `EnvironmentalFactor`. There is
  no separate `Study` node in v1; study context is structured data on a paper
  and its evidence-backed relationships.
- Entities use canonical identifiers, aliases, and authoritative external IDs
  where available. An entity that cannot be normalized to an allowed type and
  identifier is skipped and logged; no unresolved catch-all node is created.
- `Paper` and `EvidencePassage` are first-class nodes. A passage stores the
  permitted excerpt, section/offsets, and extraction summary. `Paper`
  `HAS_EVIDENCE_PASSAGE` `EvidencePassage` is the structural provenance edge.
- Semantic edges are one per supporting paper/passage. They carry an edge ID,
  source PMID, supporting passage ID, `assertion_basis`, and extraction/LLM
  configuration version. `assertion_basis` is one of `explicit`,
  `inferred_single_source`, `inferred_multi_source`, or `curated`.
- The initial semantic edge enum is: `ASSOCIATED_WITH`, `CAUSES`, `TRANSMITS`,
  `CARRIES`, `INFECTS`, `RESERVOIR_FOR`, `EXPOSES_TO`, `PREVENTS`, `TREATS`,
  `DIAGNOSES`, `HAS_OUTCOME`, `OCCURS_IN`, `INFLUENCES`, and `EVALUATES`.
  Generic `MENTIONS` and `RELATED_TO` edges are not permitted.
- `CAUSES`, `TREATS`, `PREVENTS`, and `DIAGNOSES` require an explicit cited
  statement. Inferred edges are permitted only for `ASSOCIATED_WITH`,
  `OCCURS_IN`, and `INFLUENCES`. The RAG chatbot can retrieve every permitted
  `assertion_basis` value.
- The chatbot model uses a small set of server-defined, parameterized
  Neo4j-retrieval tools with fixed limits. It does not generate arbitrary Cypher.

### Detailed v1 implementation contract

The following is the implementation-ready contract derived from the confirmed
requirements. Names and field types are proposed Pydantic-style models; their
implementation belongs in the owning repositories and requires the normal
contract/ADR workflow.

#### Processing and review states

`PaperProcessingState` is a finite enum:

| State | Meaning |
| --- | --- |
| `discovered` | PubMed query found the PMID; query-match provenance is recorded. |
| `metadata_ready` | Required PubMed metadata has been normalized. |
| `ineligible_access` | Full text is unavailable or lacks permitted PMC OA rights. |
| `awaiting_review` | Eligible paper awaits a human decision while review is required. |
| `deferred` | Reviewer intentionally postponed the decision. |
| `rejected` | Reviewer declined processing; no LLM extraction occurs. |
| `queued` | Approved or automatically eligible paper waits for budget/worker capacity. |
| `extracting` | A worker owns the paper and is performing validated extraction. |
| `processed` | Complete validated graph contribution committed; may contain zero semantic edges. |
| `failed_retryable` | Pre-success failure; retry budget remains. |
| `failed_final` | Retry budget exhausted; operator action is required. |

`ReviewDecision` is separately recorded as `approved`, `rejected`, or
`deferred`, with actor, timestamp, reason (optional), and configuration version.
It is not an editable post-processing control after approval in v1.

#### Typed graph models

Every node has `id`, `node_type`, `canonical_name`, `aliases`,
`external_ids`, `created_at`, and `source_configuration_version`. `id` is a
stable, deterministic identifier; external identifiers are recorded as a typed
map rather than free-text keys.

| Pydantic-style node | Additional required properties |
| --- | --- |
| `PaperNode` | `pmid`, optional `pmcid`, title, journal, publication date, allowed publication types, language, PubMed URL, PMC OA license/access status, content hash, full-text object key, and query-match IDs. |
| `EvidencePassageNode` | `paper_id`, permitted exact excerpt, section label, character start/end offsets, excerpt hash, and concise extraction summary. |
| `DiseaseConditionNode` | preferred label, disease family, and authoritative ontology/MeSH identifiers. |
| `PathogenNode` | scientific name, optional strain designation, pathogen class, and NCBI Taxonomy identifier where available. |
| `TickVectorNode` | scientific name, common names, NCBI Taxonomy identifier where available, life stage when asserted, and vector-role context. |
| `HostNode` | scientific/common name, host class, NCBI Taxonomy identifier where available, and host-role context. |
| `PlaceNode` | normalized place name, geographic level, code system/code, and study-context role such as study site or exposure location. |
| `StudyPopulationNode` | population description, species/population category, setting, age range when asserted, and sample-size value/unit when asserted. |
| `ExposureNode` | normalized exposure name, exposure category, measurement method, and time window when asserted. |
| `OutcomeNode` | normalized outcome name, outcome category, measurement/definition, and time window when asserted. |
| `InterventionNode` | normalized name, intervention category, delivery/administration context, and target when asserted. |
| `DiagnosticNode` | normalized test/approach name, diagnostic category, target analyte/condition, and result interpretation when asserted. |
| `EnvironmentalFactorNode` | normalized factor name, factor category, measurement/unit, value/range when asserted, and time window when asserted. |

`SemanticEdge` has `id`, `relationship_type`, `source_node_id`,
`target_node_id`, `paper_id`, `evidence_passage_id`, `assertion_basis`,
`claim_text`, `polarity` (`supports`, `does_not_support`, or `mixed`),
`study_design`, `study_geography_ids`, `study_period`,
`extraction_configuration_version`, and `created_at`. The specified passage
must directly support `claim_text`; an edge cannot be created without its paper
and passage provenance. `HAS_EVIDENCE_PASSAGE` is the sole structural edge from
`PaperNode` to `EvidencePassageNode`; all other edges use the approved semantic
relationship enum.

#### Snowflake ledger and artifact minimums

`PAPER_RECORDS` is the authoritative processing ledger. It contains PMID,
PMCID, normalized metadata, matched query-family/version IDs, access/license
decision and evidence, artifact object key/hash, processing state, review
decision/audit values, retry count, timestamps, run IDs, and extraction-route
metadata. A separate immutable `PIPELINE_RUNS` record captures discovery,
review-batch, extraction, backup, restore-test, and configuration-change runs.
No raw LLM response payload is persisted.

#### Public chat endpoint

V1 exposes one non-streaming endpoint, proposed as
`POST /api/v1/knowledge-graph/chat` in the existing Python API. Its request is
bounded to `message` (1–1,000 characters), optional client-generated
`conversation_id`, and a bounded recent `history` supplied by the browser when
server conversation persistence is disabled. The API validates and limits this
history; the browser retains the five 30-day sessions.

The success response contains `request_id`, `conversation_id`, `answer`, and a
deduplicated `citations` array. Each citation contains `pmid`, title, PubMed
URL, claim/passage identifiers, and a short source label. The API returns a
typed non-answer status of `no_evidence` or `evidence_unavailable` when it
fails closed, and returns HTTP 429 for configured rate/concurrency limits.
No raw Cypher, LLM prompt, full text, Neo4j credentials, or provider credential
is returned to the browser.

#### Source-controlled configuration outline

One versioned, non-secret configuration record contains: query-family versions;
20-year backfill and weekly schedule; allowed language/types/access policy;
batch/concurrency/retry settings; `papers_require_human_review`; named LLM
provider/model/prompt/tool/schema versions; GPT OSS 120B's 130,000-token route
budget and GPT-5.6 Luna fallback; daily/monthly spending budgets; chat limits;
conversation retention/persistence; user-facing notice/fail-closed copy; and
backup/restore-test retention schedules. Provider credentials, Snowflake
credentials, and Spaces credentials remain secrets outside this configuration.

#### Acceptance matrix

| Area | Required evidence before public enablement |
| --- | --- |
| Rights and corpus | PMC OA/English/type rules enforced; ineligible papers never reach LLM extraction. |
| Review and state | Batch review attribution, state transitions, retries, terminal approval, and no-reprocessing rule verified. |
| Extraction and graph | Both model routes exercised; invalid/unprovenanced candidates rejected; commit is atomic; every returned claim resolves to paper and passage. |
| Chat behavior | Multi-turn request bounds, citations opening PubMed, conflict display, no-evidence and outage fail-closed responses, and medical-safety handling verified. |
| Security and cost | Browser has no secrets/direct database access; API limits return 429; budgets queue work; telemetry/audit records exist. |
| Operations | Weekly scheduler/backfill resume works; backup is created; a restore test is recorded; exhausted retries create durable audit records and structured error logs. |
| Release | Automated quality gates pass and the defined live acceptance sample/rollback record is attached to the production enablement. |

## Feature at a glance

Create a governed literature-evidence capability for the One Health Lyme Gap Atlas. The feature discovers and ingests a defined corpus of PubMed records, enriches it with normalized biomedical concepts and evidence annotations, and materializes a Knowledge Graph (KG) that links publications to Lyme-relevant diseases, pathogens, vectors, hosts, genes, chemicals, interventions, places, time periods, study designs, and data-quality context.

The purpose is **evidence navigation and synthesis**, not automated clinical advice, diagnosis, treatment recommendation, or causal inference. Users should be able to move from an Atlas question—such as “What evidence connects Lyme disease, tick exposure, and this geography or time period?”—to the specific papers, excerpts, concepts, and provenance that support a relationship.

This is a proposed, forward-only feature. It extends the governed TopX platform without modifying or migrating the existing Alpha/POC `LANDING` and `PRESENTATION` objects.

## The use case

The Atlas already brings together heterogeneous public-health and contextual data. The literature KG fills a different need: it makes the scientific evidence behind interpretation discoverable, reviewable, and comparable.

### Example user journeys

| User | Question | Feature outcome |
| --- | --- | --- |
| Public-health analyst | What papers support an association between *Borrelia burgdorferi*, tick vectors, and Lyme surveillance trends? | A curated, provenance-linked evidence trail, separated by claim type and study context. |
| Research steward | Should a newly discovered paper or its extracted relationships enter the product? | A review queue with the query, record metadata, extraction output, quality signals, and approval decision. |
| Atlas user | Why is this geographic indicator accompanied by an ecological caveat? | A readable explanation with linked papers and excerpts, not an unexplained model output. |
| Product/data team | Which conclusions are based on reviews versus primary observational studies, and which need refresh? | Graph filters and source status showing publication type, dates, extraction version, review state, and evidence gaps. |

## Scope of the first release

The initial corpus is a narrow, versioned PubMed search focused on Lyme disease and One Health context. Begin with article metadata and abstracts; only ingest full text when it is explicitly available through a permitted open-access route. PubMed inclusion does **not** grant a right to redistribute publisher PDFs, abstracts, or full text.

First-release content:

- PubMed identifiers (PMID), title, abstract when available, authorship, journal, publication date, publication types, MeSH terms, and links.
- Query and retrieval provenance: exact PubMed query, query version, retrieval timestamp, API parameters, request batches, response checksums, and source record version.
- Biomedical concepts from authoritative article metadata and normalized text-mining annotations.
- Human-reviewed literature-to-concept and literature-supported relationship assertions.
- Links from literature evidence to Atlas concepts and indicators where geographic/time semantics and interpretation are valid.

Explicitly out of scope for the first release:

- Automatic acceptance of model-extracted claims as scientific fact.
- Automated clinical recommendations, patient-level risk scores, or treatment guidance.
- Full-text scraping or storing copyrighted publisher content outside approved access and licensing routes.
- Conflating literature associations with observed local data, causation, clinical consensus, or product endorsement.

## Source and enrichment strategy

### 1. PubMed as the bibliographic source of record

Use NCBI Entrez E-utilities to search PubMed and retrieve records in deterministic batches. The pipeline stores both a normalized record and the raw response artifact so the corpus can be reproduced from the query, date, and source payload. Use the Entrez History mechanism for large result sets and batch retrieval rather than one request per record.

Requests identify the registered application tool and contact email. Respect NCBI’s published request limits: without an API key, do not exceed three requests per second; an API key supports a default limit of ten requests per second. The key and any contact configuration belong in secrets/runtime configuration, never in source control.

### 2. PMC open-access full text as an optional, separate route

PubMed bibliographic presence is independent of full-text reuse rights. For an article with a PMCID, the pipeline may check the PMC Open Access Subset service and only retrieve/process full text when the article is available under the applicable PMC access terms. Store the PMCID, license/access status, retrieval route, and a content checksum. If full text is unavailable, continue with citation metadata and abstract-level evidence only.

### 3. PubTator3 for biomedical annotations

Use NCBI PubTator3 as a supplementary annotation source. It offers normalized entity annotations for genes, diseases, chemicals, variants, species, and cell lines, plus relation annotations and BioC exports. Treat these outputs as **machine-generated candidates**. Preserve the PubTator3 annotation version/retrieval time, entity spans, normalized identifiers, relation type, and source article; do not elevate them to approved TopX claims without review.

PubTator3’s normalized identifiers should be retained alongside TopX canonical identifiers, including NCBI Gene, MeSH, NCBI Taxonomy, dbSNP/HGVS, and Cellosaurus identifiers where present.

### 4. Curated TopX vocabulary and mappings

TopX owns the controlled vocabulary that connects literature to product concepts. It maps, for example, “Lyme borreliosis,” “Lyme disease,” pathogen names, Ixodes vector terms, care-access measures, and counties/regions to stable internal concept IDs. Mappings must be versioned and reviewed; a synonym match alone is not sufficient proof that a paper supports a product concept or local indicator.

## Knowledge Graph model

The graph should model evidence as first-class data. A relationship is never only an edge; it is an assertion with a source, context, extraction method, and review status.

### Core nodes

| Node | Examples | Required identity/provenance |
| --- | --- | --- |
| `Publication` | PubMed record, PMC full-text record | PMID, PMCID when applicable, source payload hash, retrieval run |
| `Passage` | title, abstract sentence, permitted full-text section | article ID, offsets/section, content hash, access status |
| `BiomedicalConcept` | Lyme disease, *B. burgdorferi*, *Ixodes scapularis*, doxycycline | TopX concept ID, external IDs, vocabulary/mapping version |
| `AtlasConcept` | reported cases, vector habitat, healthcare access, diagnostic context | semantic category and data-interpretation constraints |
| `Place` / `TimePeriod` | county FIPS, state, study period, publication year | code system and temporal/geographic semantics |
| `Study` | observational study, review, trial, surveillance report | publication linkage and study-design classification |
| `EvidenceAssertion` | “paper reports association of X and Y” | assertion ID, polarity/type, reviewer status, evidence strength |
| `SourceVersion` / `PipelineRun` | PubMed query version, extraction run | immutable source/run identifiers and hashes |

### Core edges

| Edge | Meaning | Important constraints |
| --- | --- | --- |
| `MENTIONS` | a passage or paper contains a concept | mention only; not a scientific claim |
| `STUDIES` | paper examines a concept/relationship | preserve study population and design |
| `REPORTS_ASSOCIATION` | paper reports an association | must not be rendered as causal |
| `REPORTS_CAUSAL_CLAIM` | source explicitly makes a causal claim | requires careful human review and claim context |
| `EVALUATES_INTERVENTION` | paper evaluates intervention/exposure/outcome | not treatment guidance |
| `HAS_GEOGRAPHIC_CONTEXT` / `HAS_TEMPORAL_CONTEXT` | paper or assertion applies to place/time | distinguish study site, residence, exposure, and publication geography |
| `SUPPORTED_BY` | assertion is supported by a passage/publication | citation/excerpt required |
| `EXTRACTED_FROM` | annotation/assertion derives from a run or tool | model/tool version required |
| `REVIEWED_AS` | steward/editor disposition | pending, approved, rejected, conditional, superseded |
| `ALIGNS_WITH` | reviewed link to an Atlas concept/indicator | semantic compatibility review required |

### Assertion, not edge-only, pattern

```text
Publication / Passage
        |
        +-- SUPPORTED_BY -- EvidenceAssertion -- ABOUT --> Concept A
                                           |
                                           +-- ABOUT --> Concept B
                                           |
                                           +-- EXTRACTED_FROM --> ExtractionRun
                                           +-- REVIEWED_AS --> ReviewDecision
                                           +-- HAS_GEOGRAPHIC_CONTEXT --> Place
                                           +-- HAS_TEMPORAL_CONTEXT --> TimePeriod
```

This pattern permits contradictory findings, different populations, evolving evidence, and multiple sources without overwriting earlier assertions.

## End-to-end workflow

```text
Versioned search policy
  -> PubMed discovery (ESearch)
  -> metadata/abstract retrieval (ESummary + EFetch)
  -> raw immutable response artifacts + checksum
  -> normalize citation, MeSH, authorship, dates, identifiers
  -> optional permitted PMC OA full text
  -> PubTator3 annotations + deterministic rule-based extraction
  -> candidate nodes, mentions, and assertions
  -> human review / approval
  -> approved KG materialization
  -> FastAPI read model
  -> Next.js / MapLibre Atlas evidence experience
```

### Discovery and refresh policy

- Store each search as a `LiteratureQueryVersion`: query string, intended research question, inclusion/exclusion rationale, curator, effective date, and status.
- Use an initial backfill plus incremental refreshes by PubMed entry date/last-update date; never silently replace a prior corpus result.
- Deduplicate by PMID and retain a record revision history. Retraction,
  correction, erratum, and other post-processing source-status monitoring is
  explicitly deferred beyond v1; v1 does not change graph/RAG availability
  after a paper has been approved and processed.
- Keep a durable “not ingested” decision for records excluded by scope, access, quality, duplication, or relevance review.
- Use exponential backoff and a resumable cursor/history state; a partial run is retained and labeled rather than discarded or falsely marked complete.

### Extraction policy

Extraction proceeds in layers:

1. **Deterministic metadata:** PMID, title, publication types, MeSH, dates, journal, authors, links.
2. **Normalized annotations:** PubTator3 entities/relations and versioned vocabulary mappings.
3. **Candidate assertions:** sentence/passage-backed, typed candidates from rules and/or a controlled model workflow.
4. **Human-approved assertions:** only reviewed candidates are visible as product evidence connections.

For any model-assisted extraction, retain the prompt/template version, model identifier, input content hash, output payload, parser version, validation result, and reviewer disposition. Models may propose candidates but cannot fabricate citations, silently combine papers, or create unsourced claims.

## Governance and safety controls

### Approval boundary

The existing Snowflake governance model remains the control point:

- New sources, search policies, enrichment providers, and graph-publication rules are reviewable governed resources.
- The Snowflake Streamlit approval console obtains reviewer identity from `st.user.user_name` and records decisions only through `GOVERNANCE.SP_RECORD_SOURCE_REVIEW_DECISION`.
- A source approval activates an approved version; it does not automatically perform a broad PubMed harvest, run extraction, or publish relationships.
- Candidate assertions remain pending until review. Rejections and superseded decisions remain in history, separate from the pending queue.

### Scientific interpretation

- Label **mention**, **reported association**, **review conclusion**, **study result**, and **TopX synthesis** distinctly.
- Preserve study design, population, intervention/exposure, outcome, sample/context, publication type, and relevant limitations.
- Keep biological plausibility, ecological conditions, reported case counts, diagnostic practice, healthcare access, and individual infection risk as different semantic categories.
- Never use a literature graph edge alone to establish local prevalence, causality, clinical efficacy, or policy recommendation.
- Surface disagreement, absence of evidence, and incompatible geography/time instead of aggregating them into a single confidence score.

### Copyright, access, and security

- Retain only the content necessary for the permitted use case; use links and identifiers when storage/republication rights are unclear.
- Maintain a source-access and license field at article and passage level. Full-text storage and display are conditioned on the applicable PMC/open-access terms.
- Attribute NCBI/NLM resources and make applicable NCBI disclaimer/copyright information visible in the product’s source/evidence experience.
- Treat NCBI API keys and contact configuration as secrets. Store ordinary search policy, quotas, and allowed-source configuration in tracked, inspectable configuration.

## Proposed implementation architecture

### Existing TopX stack to reuse

- **Data/pipeline:** Python with `uv`, dbt, source-controlled SQL migrations, Docker, immutable object-storage artifacts, and Snowflake.
- **Governed Snowflake layers:** `GOVERNANCE`, `RAW`, `STAGING`, `CONFORMED`, `ANALYTICS`, and `FEATURE_STORE`; preserve separation from Alpha `LANDING`/`PRESENTATION`.
- **Review:** Snowflake Streamlit owner-rights application, pending-only queues, decision history, and stored-procedure-only writes.
- **API:** Python FastAPI with generated OpenAPI contracts; Snowflake remains server-side.
- **Web:** React, TypeScript, Next.js App Router, MapLibre, generated API types, Playwright, and componentized UI.
- **Delivery:** GitHub quality/deploy workflow and DigitalOcean App Platform; validate CI, deployment, live API, data state, and UI behavior separately.

### New governed objects

Use forward-only migrations to add a literature-specific namespace or equivalent governed tables/views:

```text
GOVERNANCE.LITERATURE_QUERY_VERSIONS
GOVERNANCE.LITERATURE_SOURCE_VERSIONS
GOVERNANCE.LITERATURE_REVIEW_DECISIONS
RAW.PUBMED_RESPONSE_ARTIFACTS
RAW.PMC_OA_CONTENT_ARTIFACTS
STAGING.PUBMED_RECORDS
STAGING.PUBTATOR_ANNOTATIONS
CONFORMED.LITERATURE_PUBLICATIONS
CONFORMED.LITERATURE_PASSAGES
CONFORMED.BIOMEDICAL_CONCEPT_MAPPINGS
CONFORMED.LITERATURE_ASSERTION_CANDIDATES
ANALYTICS.KG_NODES
ANALYTICS.KG_EDGES
ANALYTICS.KG_EVIDENCE_ASSERTIONS
FEATURE_STORE.LITERATURE_EVIDENCE_READ_MODEL
```

These names are a design starting point, not a directive to create objects without the normal migration and review process.

### API and UI contract

The API returns a bounded, evidence-first subgraph—never an unbounded graph traversal.

- `GET /literature/search`: query approved papers by concept, type, date, study context, and review status.
- `GET /knowledge-graph/neighborhood`: retrieve nodes, assertions, and edges around an Atlas concept/place/time with depth and result limits.
- `GET /evidence/assertions/{id}`: show the assertion, supporting paper/passage, extraction provenance, and review/quality status.
- `GET /publications/{pmid}`: citation metadata, permitted excerpt/links, annotations, and related approved assertions.

The Next.js experience should begin with a clear evidence list and filters, then offer an optional connected-relationships view. Map selection can pass geography/time context to literature results, but the UI must distinguish local data from a paper’s study context.

### Confirmed v1 UI scope and future graph-exploration idea

The v1 public experience is the Knowledge Graph-backed RAG Chatbot Agent. It
does not require user authentication. The agent queries Neo4j for all answer
context; it does not retrieve directly from the stored full-text artifacts at
answer time. Each response includes grounded citations that link to the
corresponding PubMed paper and open in a new browser tab.

A standalone visual graph browser is explicitly out of scope for v1. A future
evidence-explorer experience may let users search and filter canonical
entities/papers, open paper detail pages, inspect the exact evidence passages
behind relationships, and navigate a visual graph. That future work should be
designed with an accessible non-visual alternative and should not be inferred
to be part of the chatbot v1 delivery.

## First vertical slice

Use a small, approved Lyme corpus—such as a tightly versioned query for Lyme disease plus tick/vector terminology—and process a fixed number of records in DEV.

1. Approve the search policy and PubMed source version.
2. Retrieve a bounded batch of metadata/abstract records and preserve raw responses, request logs, row counts, and checksums.
3. Normalize citation metadata, MeSH terms, and PubTator3 annotations.
4. Materialize `Publication`, `BiomedicalConcept`, `Passage`, and `MENTIONS` edges. Do not yet publish relation/causal claims automatically.
5. Add a reviewer workflow for candidate paper-to-Atlas-concept links.
6. Expose a read-only paper/evidence endpoint and an Atlas evidence panel for one selected concept.
7. Demonstrate provenance from UI evidence item back to PMID, query version, raw artifact, extraction run, and reviewer decision.

This proves ingestion, traceability, and useful retrieval before adding sophisticated relationship extraction or a separate graph database.

## Acceptance criteria / definition of done

- Alpha POC objects are unchanged; all new work is additive and forward-only.
- Every stored paper has a PMID, retrieval provenance, query version, raw artifact checksum, and source access status.
- Every displayed assertion has a typed claim/relationship, supporting source/passage, extraction provenance, review status, and an explicit caveat where needed.
- PubTator3/model-generated annotations are clearly marked as generated candidates until approved.
- The product distinguishes article mentions, associations, causal claims, and TopX synthesis in both data model and UI.
- Full-text processing/display occurs only through verified permitted access; no publisher content is silently harvested or redistributed.
- API calls are typed, bounded, authenticated/authorized as appropriate, and expose no direct Snowflake connection.
- Automated checks cover schema/migration validation, pipeline idempotency/resume behavior, duplicate handling, rate-limit/backoff behavior, provenance completeness, dbt models, API contracts, UI empty/caveat states, and security/access controls.
- A live DEV acceptance record verifies: approved query; bounded retrieval; raw artifacts; Snowflake row/edge/assertion counts; sample lineage; review decisions; API responses; deployed UI; and rollback/supersession behavior. Green CI alone is not release evidence.

## Delivery phases

| Phase | Outcome |
| --- | --- |
| 0. Policy and schema | Approved corpus policy, access rules, controlled vocabulary, assertion taxonomy, and review rubric. |
| 1. PubMed metadata | Reproducible search, bounded retrieval, raw artifacts, normalized citations/MeSH, and refresh ledger. |
| 2. Annotation candidates | PubTator3 ingestion, entity normalization, passage-backed candidate nodes/edges, and review UI. |
| 3. Evidence graph read model | Approved assertions/nodes/edges, FastAPI bounded-subgraph endpoints, evidence-detail views. |
| 4. Atlas experience | Evidence panel, filters, graph exploration, and geographic/time compatibility cues. |
| 5. Expanded evidence | Optional permitted PMC OA full text, additional sources, scoring/evaluation, and carefully governed model assistance. |

## Key decisions to make before implementation

1. Approve the initial research questions and PubMed query set, including explicit inclusions/exclusions.
2. Choose the human review roles and the rubric for paper relevance, assertion type, evidence quality, and “approved for Atlas” disposition.
3. Confirm whether full-text processing is limited to PMC Open Access Subset content in the first release (recommended).
4. Define whether the public Atlas can show only approved evidence or also a clearly separated “under review” research workspace.
5. Set the first operational bounds: max records per run, refresh cadence, query change review, retention period, and API result limits.

## External technical references

- [NCBI Entrez Programming Utilities Help](https://www.ncbi.nlm.nih.gov/books/NBK25501/): retrieval workflow, tool/email registration, request-rate guidance, batching, and copyright/disclaimer considerations.
- [PubTator3 API](https://www.ncbi.nlm.nih.gov/research/pubtator3/api): publication annotations, normalized biomedical entities, relation querying, and supported export formats.
- [PubTator3 tutorial](https://www.ncbi.nlm.nih.gov/research/pubtator3/tutorial): entity normalizations and relationship-extraction context.
- [PMC Open Access Subset](https://pmc.ncbi.nlm.nih.gov/tools/openftlist/): determine which full-text articles may be used through the open-access route.
