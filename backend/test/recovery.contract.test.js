import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const recovery =
  fs.readFileSync(
    new URL(
      '../RECOVERY.md',
      import.meta.url
    ),
    'utf8'
  );

test(
  'production recovery inputs are explicit rather than invented defaults',
  () => {
    for (
      const expected of [
        'Recovery Point Objective (RPO)',
        'Recovery Time Objective (RTO)',
        'backup frequency',
        'retention periods',
        'backup storage location',
        'encryption-at-rest mechanism and key owner',
        'restore-drill cadence',
        'selected backup consistency mechanism'
      ]
    ) {
      assert.ok(
        recovery.includes(
          expected
        ),
        `missing recovery acceptance input: ${expected}`
      );
    }

    assert.match(
      recovery,
      /does not invent business RPO\/RTO or retention values/is
    );
  }
);

test(
  'Database Tools provenance is recorded for backup and restore',
  () => {
    assert.match(
      recovery,
      /mongodump --version/is
    );

    assert.match(
      recovery,
      /mongorestore --version/is
    );

    assert.match(
      recovery,
      /same MongoDB Database Tools\s+release/is
    );
  }
);

test(
  'credential handling keeps production connection secrets out of repository evidence',
  () => {
    assert.match(
      recovery,
      /--config/is
    );

    assert.match(
      recovery,
      /stored outside the repository/is
    );

    assert.match(
      recovery,
      /Do not paste a credential-bearing\s+`--uri` argument/is
    );

    assert.equal(
      /mongodb(?:\+srv)?:\/\/[^<\s]/i.test(
        recovery
      ),
      false
    );
  }
);

test(
  'logical backup template records archive integrity and stays outside the worktree',
  () => {
    assert.match(
      recovery,
      /mongodump --config=<secure-tools-config\.yml> --db=<source-db> --archive=<outside-repository-archive> --gzip/is
    );

    assert.match(
      recovery,
      /outside the Git working tree/is
    );

    assert.match(
      recovery,
      /SHA-256 checksum/is
    );

    assert.match(
      recovery,
      /zero-byte archive or missing checksum is not an accepted backup/is
    );
  }
);

test(
  'backup consistency remains fail-closed for an unknown production topology',
  () => {
    assert.match(
      recovery,
      /writes continue may not represent\s+one point in time/is
    );

    assert.match(
      recovery,
      /must not silently add `--oplog`/is
    );

    assert.match(
      recovery,
      /provider\/platform-native consistent backup/is
    );

    assert.match(
      recovery,
      /write-quiescence procedure/is
    );

    assert.match(
      recovery,
      /recovery gate\s+remains incomplete/is
    );
  }
);

test(
  'restore verification is isolated and namespace-remapped',
  () => {
    assert.match(
      recovery,
      /Never use the\s+production database as a restore-drill destination/is
    );

    assert.match(
      recovery,
      /merzox_restore_verify_<utc-run-id>/is
    );

    assert.match(
      recovery,
      /--nsFrom="<source-db>\.\*"/is
    );

    assert.match(
      recovery,
      /--nsTo="<verify-db>\.\*"/is
    );

    assert.match(
      recovery,
      /--stopOnError/is
    );

    assert.equal(
      /mongorestore[^\n]*--drop/is.test(
        recovery
      ),
      false
    );
  }
);

test(
  'backup storage and destructive operations remain bounded',
  () => {
    assert.match(
      recovery,
      /off-host/is
    );

    assert.match(
      recovery,
      /encrypted at rest/is
    );

    assert.match(
      recovery,
      /fail closed when a target database is ambiguous/is
    );

    assert.match(
      recovery,
      /may automatically erase or overwrite a production database/is
    );
  }
);

test(
  'disaster recovery requires readiness and real deployment evidence before activation',
  () => {
    assert.match(
      recovery,
      /GET \/ready/is
    );

    assert.match(
      recovery,
      /HTTP 200/is
    );

    assert.match(
      recovery,
      /Traffic must not resume merely because a restore command returned exit code zero/is
    );

    assert.match(
      recovery,
      /explicit RPO and RTO/is
    );

    assert.match(
      recovery,
      /activated production recovery service/is
    );
  }
);
