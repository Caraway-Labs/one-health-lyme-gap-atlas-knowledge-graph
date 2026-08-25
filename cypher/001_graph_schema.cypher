CREATE CONSTRAINT knowledge_node_id IF NOT EXISTS
FOR (node:KnowledgeNode) REQUIRE node.id IS UNIQUE;

CREATE CONSTRAINT paper_pmid IF NOT EXISTS
FOR (paper:Paper) REQUIRE paper.pmid IS UNIQUE;

CREATE CONSTRAINT evidence_passage_id IF NOT EXISTS
FOR (passage:EvidencePassage) REQUIRE passage.id IS UNIQUE;

CREATE FULLTEXT INDEX entity_names IF NOT EXISTS
FOR (node:DiseaseCondition|Pathogen|TickVector|Host|Place|StudyPopulation|Exposure|Outcome|Intervention|Diagnostic|EnvironmentalFactor)
ON EACH [node.canonical_name, node.aliases];

CREATE VECTOR INDEX evidence_passage_summary IF NOT EXISTS
FOR (passage:EvidencePassage) ON passage.embedding
OPTIONS {indexConfig: {
  `vector.dimensions`: 1024,
  `vector.similarity_function`: 'cosine'
}};
