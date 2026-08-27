# Merzox Database Recovery Contract

This document defines the provider-neutral production contract for MongoDB backup,
restore verification, and disaster recovery. It is an operational safety contract,
not evidence that a production backup has already been created.

## Production acceptance inputs

Before production launch, the deployment owner must explicitly record:

- accepted Recovery Point Objective (RPO);
- accepted Recovery Time Objective (RTO);
- backup frequency and retention periods;
- backup storage location;
- encryption-at-rest mechanism and key owner;
- access-control owner;
- restore-drill cadence;
- selected backup consistency mechanism;
- exact MongoDB Database Tools release used for logical backups.

The repository deliberately does not invent business RPO/RTO or retention values.

## Database Tools provenance

Record both tool versions before every logical backup or restore procedure:

`mongodump --version`
`mongorestore --version`

A backup used for recovery should be restored with the same MongoDB Database Tools
release that created it unless a separately reviewed migration procedure explicitly
allows otherwise.

## Credential handling

Do not place a production MongoDB URI, password, TLS-key password, or other database
secret in this repository or in recovery evidence.

Use a MongoDB Database Tools `--config` file stored outside the repository with
appropriately restrictive filesystem permissions. Do not paste a credential-bearing
`--uri` argument into shell history, CI logs, tickets, reports, or screenshots.

## Logical backup template

When a logical dump is the approved consistency mechanism, the provider-neutral shape is:

`mongodump --config=<secure-tools-config.yml> --db=<source-db> --archive=<outside-repository-archive> --gzip`

The archive path must be outside the Git working tree. Recovery evidence must record
UTC creation time, non-secret source identity, source database name, Database Tools
version, consistency mechanism, non-zero archive size, SHA-256 checksum, storage and
encryption destination, and retention classification.

A zero-byte archive or missing checksum is not an accepted backup.

## Consistency boundary

A normal logical `mongodump` taken while application writes continue may not represent
one point in time. The repository must not silently add `--oplog` because the deployed
MongoDB topology has not yet been selected.

Before production launch, the deployment must choose and test one approved consistency
mechanism: a provider/platform-native consistent backup, an explicitly reviewed
application/database write-quiescence procedure, or another MongoDB-supported mechanism
reviewed for the deployed topology.

If no consistency mechanism has been selected and tested, the production recovery gate
remains incomplete.

## Backup storage boundary

Production backups must not exist only on the application host. Accepted storage must
be off-host, access controlled, and encrypted at rest. Key-management authority must not
depend solely on the host or credentials whose loss would require disaster recovery.

## Restore verification

A backup is not verified until it completes an isolated restore drill. Never use the
production database as a restore-drill destination.

Each drill must use a unique disposable database such as:

`merzox_restore_verify_<utc-run-id>`

For an archive created from `<source-db>`, the provider-neutral restore shape is:

`mongorestore --config=<secure-restore-config.yml> --archive=<archive> --gzip --nsFrom="<source-db>.*" --nsTo="<verify-db>.*" --stopOnError`

The standard restore-drill template deliberately contains no `--drop`; the verification
target must start empty and disposable.

## Restore validation evidence

A successful restore process alone is insufficient. Verify expected application
collections, plausible document counts, required indexes, representative critical
records, namespace correctness, and that no production database was written.

When Merzox is exercised against the restored database, isolate SMTP, Firebase push,
production clients, and production credentials.

## Disaster-recovery sequence

During a real database-loss incident: prevent uncontrolled writes, identify the accepted
recovery point, provision a clean target, verify tool versions and credentials without
exposing secrets, restore using the approved mechanism, perform validation, reconfigure
Merzox to the recovered database, require `GET /ready` to return HTTP 200 before traffic
resumes, verify critical workflows, record recovery evidence, and rotate credentials if
the incident involved credential or host compromise.

Traffic must not resume merely because a restore command returned exit code zero.

## Destructive-operation boundary

Recovery automation must fail closed when a target database is ambiguous. No repository
recovery procedure may automatically erase or overwrite a production database merely
because its name was supplied through an environment variable or command-line option.

Production replacement, destructive cleanup, or rollback requires an explicit
deployment-specific operator procedure and separate approval.

## Provider boundary

This document does not choose MongoDB Atlas backup, filesystem snapshots, cloud
block-volume snapshots, Kubernetes storage snapshots, or another hosting provider.

The selected production mechanism must map back to this contract and provide evidence
for consistency, retention, encryption, restore verification, RPO, and RTO.

## Recovery acceptance evidence

Before production launch, recovery acceptance must contain explicit RPO and RTO, backup
and retention schedule, consistency mechanism, protected credential mechanism, encrypted
off-host storage, backup metadata and checksum, successful isolated restore-drill
evidence, validation results, responsible owner, and the date of the next scheduled
restore drill.

Until those items exist for the real deployment, Merzox has a recovery contract but not
an activated production recovery service.
