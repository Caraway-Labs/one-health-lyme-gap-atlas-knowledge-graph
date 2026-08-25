param([string]$DropletId, [string]$RetainedVolumeId, [switch]$Confirm)
$ErrorActionPreference = 'Stop'
if (-not $Confirm) {
  [pscustomobject]@{ mode = 'preview'; action = 'destroy DEV compute'; retained_volume = $RetainedVolumeId } | ConvertTo-Json
  exit 0
}
if (-not $DropletId -or -not $RetainedVolumeId) { throw 'Explicit DropletId and RetainedVolumeId are required.' }
$droplet = & doctl compute droplet get $DropletId --output json | ConvertFrom-Json
$volume = & doctl compute volume get $RetainedVolumeId --output json | ConvertFrom-Json
if ($droplet[0].name -ne 'oh-lyme-dev-neo4j') { throw 'Droplet is not the exact DEV Neo4j target.' }
if ($volume[0].name -ne 'oh-lyme-dev-neo4j-data') { throw 'Retained volume identity check failed.' }
if ($volume[0].droplet_ids -notcontains [int64]$DropletId) { throw 'Retained volume is not attached to the target Droplet.' }
& doctl compute droplet delete $DropletId --force
[pscustomobject]@{ destroyed_droplet_id = $DropletId; retained_volume_id = $RetainedVolumeId } | ConvertTo-Json
