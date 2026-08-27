import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const NODE_RANGE =
  '>=24.0.0 <25.0.0';

const packageJson =
  JSON.parse(
    fs.readFileSync(
      new URL(
        '../package.json',
        import.meta.url
      ),
      'utf8'
    )
  );

const packageLock =
  JSON.parse(
    fs.readFileSync(
      new URL(
        '../package-lock.json',
        import.meta.url
      ),
      'utf8'
    )
  );

const deployment =
  fs.readFileSync(
    new URL(
      '../DEPLOYMENT.md',
      import.meta.url
    ),
    'utf8'
  );

test(
  'production runtime is pinned to the accepted Node 24 major',
  () => {
    assert.deepEqual(
      packageJson.engines,
      {
        node:
          NODE_RANGE
      }
    );

    assert.deepEqual(
      packageLock.packages?.['']?.engines,
      {
        node:
          NODE_RANGE
      }
    );

    assert.equal(
      packageJson.scripts?.start,
      'node src/server.js'
    );
  }
);

test(
  'deployment contract preserves authoritative probes and shutdown',
  () => {
    for (
      const expected of [
        'npm ci --omit=dev',
        'npm start',
        'GET /health',
        'GET /ready',
        'SIGTERM',
        'SIGINT',
        'TRUST_PROXY_RANGES',
        'PUBLIC_BASE_URL',
        'CORS_ORIGINS'
      ]
    ) {
      assert.ok(
        deployment.includes(
          expected
        ),
        `missing deployment contract: ${expected}`
      );
    }
  }
);

test(
  'deployment contract keeps liveness separate from readiness',
  () => {
    assert.match(
      deployment,
      /\/health.*process liveness/is
    );

    assert.match(
      deployment,
      /\/ready.*deployment readiness/is
    );

    assert.match(
      deployment,
      /\/ready.*HTTP\s+200/is
    );

    assert.match(
      deployment,
      /\/ready.*HTTP 503/is
    );
  }
);

test(
  'deployment contract preserves bounded proxy trust',
  () => {
    assert.match(
      deployment,
      /explicit IP\/CIDR/is
    );

    assert.match(
      deployment,
      /trust proxy=true/is
    );

    assert.match(
      deployment,
      /numeric hop-count/is
    );

    assert.match(
      deployment,
      /proxy trust must remain disabled/is
    );
  }
);

test(
  'current realtime production baseline is one backend replica',
  () => {
    assert.match(
      deployment,
      /no repository-configured shared cross-process\s+adapter/is
    );

    assert.match(
      deployment,
      /one backend Node process \/ one backend application replica/is
    );

    assert.match(
      deployment,
      /multi-replica backend requires a separate architecture change/is
    );
  }
);

test(
  'deployment contract is provider-neutral and leaves recovery explicit',
  () => {
    assert.match(
      deployment,
      /does not select a cloud provider/is
    );

    assert.match(
      deployment,
      /backup, retention, restore verification, RPO\/RTO/is
    );

    assert.match(
      deployment,
      /separate required production-operations gate/is
    );

    for (
      const forbidden of [
        'railway.app',
        'render.com',
        'fly.dev',
        'amazonaws.com'
      ]
    ) {
      assert.equal(
        deployment.includes(
          forbidden
        ),
        false,
        `provider-specific endpoint leaked into contract: ${forbidden}`
      );
    }
  }
);

test(
  'deployment documentation contains no literal production secret assignment',
  () => {
    assert.equal(
      /JWT_SECRET\s*=\s*[^\s`]+/.test(
        deployment
      ),
      false
    );

    assert.equal(
      /MONGODB_URI\s*=\s*mongodb/.test(
        deployment
      ),
      false
    );

    assert.equal(
      /SMTP_PASS\s*=\s*[^\s`]+/.test(
        deployment
      ),
      false
    );
  }
);
