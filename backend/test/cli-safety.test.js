import assert from 'node:assert/strict';
import {
  readFile
} from 'node:fs/promises';
import {
  fileURLToPath
} from 'node:url';
import test from 'node:test';

import {
  CLI_ACTIONS,
  CLI_REFUSAL,
  cliExecutionRefusal,
  cliRefusalMessage,
  safeCliErrorSummary
} from '../src/scripts/cli-safety.js';

const sourceRoot =
  fileURLToPath(
    new URL(
      '../src/',
      import.meta.url
    )
  );

test(
  'production is refused even when destructive opt-in is true',
  () => {
    assert.equal(
      cliExecutionRefusal({
        nodeEnv:
          ' production ',
        allowValue:
          'true'
      }),
      CLI_REFUSAL.production
    );
  }
);

test(
  'production is refused even when SMTP diagnostic opt-in is true',
  () => {
    assert.equal(
      cliExecutionRefusal({
        nodeEnv:
          'PRODUCTION',
        allowValue:
          'true'
      }),
      CLI_REFUSAL.production
    );
  }
);

test(
  'non-production requires exact true opt-in',
  () => {
    for (
      const value of [
        undefined,
        '',
        'false',
        'TRUE',
        '1'
      ]
    ) {
      assert.equal(
        cliExecutionRefusal({
          nodeEnv:
            'development',
          allowValue:
            value
        }),
        CLI_REFUSAL.optIn
      );
    }

    assert.equal(
      cliExecutionRefusal({
        nodeEnv:
          'development',
        allowValue:
          'true'
      }),
      null
    );
  }
);

test(
  'refusal messages identify only the safe action and opt-in flag',
  () => {
    assert.equal(
      cliRefusalMessage({
        action:
          CLI_ACTIONS.destructiveSeed,
        refusal:
          CLI_REFUSAL.production
      }),
      'Seed is disabled when NODE_ENV=production.'
    );

    assert.equal(
      cliRefusalMessage({
        action:
          CLI_ACTIONS.emailDiagnostic,
        refusal:
          CLI_REFUSAL.optIn
      }),
      'SMTP diagnostic requires explicit opt-in: MERZOX_ALLOW_EMAIL_DIAGNOSTIC=true.'
    );
  }
);

test(
  'safe CLI errors never carry raw message or stack content',
  () => {
    const secret =
      'provider-secret-123';

    const error =
      new Error(
        `provider failed: ${secret}`
      );

    error.stack =
      `STACK ${secret}`;

    error.code =
      'EAUTH';

    const result =
      safeCliErrorSummary(
        error
      );

    const serialized =
      JSON.stringify(
        result
      );

    assert.equal(
      serialized.includes(
        secret
      ),
      false
    );

    assert.deepEqual(
      result,
      {
        errorName:
          'Error',
        errorCode:
          'EAUTH'
      }
    );
  }
);

test(
  'seed safety decision precedes database execution and raw failure output is gone',
  async () => {
    const source =
      await readFile(
        `${sourceRoot}/scripts/seed.js`,
        'utf8'
      );

    const decisionIndex =
      source.indexOf(
        'const seedRefusal'
      );

    const invocationIndex =
      source.indexOf(
        'seed().catch'
      );

    assert.notEqual(
      decisionIndex,
      -1
    );

    assert.notEqual(
      invocationIndex,
      -1
    );

    assert.equal(
      decisionIndex <
        invocationIndex,
      true
    );

    assert.equal(
      source.includes(
        'process.exit('
      ),
      false
    );

    assert.equal(
      source.includes(
        'console.error(error)'
      ),
      false
    );

    assert.equal(
      source.includes(
        "Login user@merzox.local / Password123"
      ),
      false
    );

    assert.equal(
      source.includes(
        "Login +972590000001 / Password123"
      ),
      false
    );

    assert.equal(
      source.includes(
        'safeCliErrorSummary'
      ),
      true
    );
  }
);

test(
  'SMTP diagnostic has production and explicit opt-in guard',
  async () => {
    const source =
      await readFile(
        `${sourceRoot}/scripts/check-email.js`,
        'utf8'
      );

    assert.equal(
      source.includes(
        'CLI_ACTIONS.emailDiagnostic'
      ),
      true
    );

    assert.equal(
      source.includes(
        'cliExecutionRefusal'
      ),
      true
    );

    assert.equal(
      source.indexOf(
        'const diagnosticRefusal'
      ) <
      source.indexOf(
        'await runEmailDiagnostic()'
      ),
      true
    );
  }
);

test(
  'SMTP diagnostic never prints recipient or raw provider errors',
  async () => {
    const source =
      await readFile(
        `${sourceRoot}/scripts/check-email.js`,
        'utf8'
      );

    for (
      const forbidden of [
        'Test email sent to ${to}',
        'Provider response:',
        'error.response',
        'error.message',
        'console.error(error)'
      ]
    ) {
      assert.equal(
        source.includes(
          forbidden
        ),
        false,
        forbidden
      );
    }

    assert.equal(
      source.includes(
        'safeCliErrorSummary'
      ),
      true
    );
  }
);
