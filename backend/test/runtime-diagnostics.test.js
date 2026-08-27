import assert from 'node:assert/strict';
import {
  readFile,
  readdir
} from 'node:fs/promises';
import {
  fileURLToPath
} from 'node:url';
import test from 'node:test';

const sourceRoot =
  fileURLToPath(
    new URL(
      '../src/',
      import.meta.url
    )
  );

async function javascriptFiles(
  directory,
  relative = ''
) {
  const entries =
    await readdir(
      directory,
      {
        withFileTypes: true
      }
    );

  const output = [];

  for (const entry of entries) {
    const childRelative =
      relative
        ? `${relative}/${entry.name}`
        : entry.name;

    const child =
      `${directory}/${entry.name}`;

    if (entry.isDirectory()) {
      if (
        childRelative ===
        'scripts'
      ) {
        continue;
      }

      output.push(
        ...await javascriptFiles(
          child,
          childRelative
        )
      );

      continue;
    }

    if (
      entry.isFile() &&
      entry.name.endsWith('.js')
    ) {
      output.push({
        path:
          childRelative,
        absolute:
          child
      });
    }
  }

  return output;
}

test(
  'server runtime contains no direct console diagnostics',
  async () => {
    const files =
      await javascriptFiles(
        sourceRoot
      );

    const offenders = [];

    for (
      const {
        path,
        absolute
      } of files
    ) {
      const source =
        await readFile(
          absolute,
          'utf8'
        );

      if (
        /console\.(?:log|info|warn|error|debug)\s*\(/.test(
          source
        )
      ) {
        offenders.push(path);
      }
    }

    assert.deepEqual(
      offenders,
      []
    );
  }
);

test(
  'email fallback never prints recipient or verification URL diagnostics',
  async () => {
    const source =
      await readFile(
        `${sourceRoot}/services/email.service.js`,
        'utf8'
      );

    assert.equal(
      source.includes(
        'Merzox email verification link for'
      ),
      false
    );

    assert.equal(
      source.includes(
        'console.warn'
      ),
      false
    );

    assert.equal(
      source.includes(
        "'verification_email_not_sent'"
      ),
      true
    );

    assert.equal(
      source.includes(
        "'password_reset_email_not_sent'"
      ),
      true
    );
  }
);

test(
  'all five migrated runtime diagnostics use fixed structured events',
  async () => {
    const expectations = [
      [
        'controllers/message.controller.js',
        "'message_compensation_failed'"
      ],
      [
        'services/checkout-reconciler.service.js',
        "'checkout_reconciliation_failed'"
      ],
      [
        'services/email.service.js',
        "'verification_email_not_sent'"
      ],
      [
        'services/notification.service.js',
        "'notification_persist_failed'"
      ],
      [
        'services/password-recovery.service.js',
        "'password_reset_request_failed'"
      ]
    ];

    for (
      const [
        relative,
        event
      ] of expectations
    ) {
      const source =
        await readFile(
          `${sourceRoot}/${relative}`,
          'utf8'
        );

      assert.equal(
        source.includes(event),
        true,
        relative
      );
    }
  }
);
