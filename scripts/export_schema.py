import json
from pathlib import Path

from lyme_gap_atlas_kg import GraphContribution

schema = GraphContribution.model_json_schema()
schema["$id"] = "https://carawaylabs.com/schemas/knowledge-graph-v1.json"
schema["title"] = "One Health Lyme Gap Atlas graph contribution"
Path("schemas/graph-v1.schema.json").write_text(
    json.dumps(schema, indent=2) + "\n", encoding="utf-8"
)
