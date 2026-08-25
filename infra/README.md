# Neo4j operations

All PowerShell entry points preview by default. `-Confirm` is reserved for the
owner-approved protected workflow. No credential belongs in a manifest, cloud
init, command line, log, or repository.

1. Provision the retained volume and private-VPC Droplet with
   `Provision-Neo4j.ps1`.
2. Transfer `configure-neo4j.sh` over the protected operator connection and
   supply its secrets as ephemeral environment values. Only Bolt on the VPC
   address is published; Browser/HTTP is not published.
3. Apply `cypher/001_graph_schema.cypher`, create distinct `api_reader` and
   `graph_writer` credentials, and attach the API/data App Platform components
   to the same VPC before enabling their feature flags.
4. Schedule `backup-neo4j.sh` off peak and apply `spaces-lifecycle.json` to the
   private bucket. The script stops the database, dumps both `system` and
   `neo4j`, records checksums, uploads, and restarts via its exit trap.
5. Run `Test-Neo4jRestore.ps1` quarterly in the protected workflow. Store the
   restore record with constraints, counts, dump checksums, and representative
   retrieval evidence, then destroy only the verified ephemeral compute.

Rollback is feature-flag first: disable public chat and publication, leave the
Snowflake ledgers and retained volume intact, restore the most recent verified
dump if graph reconciliation cannot repair the deployment, and record the event
in the operational audit ledger.
