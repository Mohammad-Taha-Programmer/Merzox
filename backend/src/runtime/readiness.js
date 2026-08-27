const SERVICE_NAME = 'merzox-api';

let runtimeReady = false;
let databaseReadyProbe = () => false;

/**
 * Registers the live database readiness probe used by the HTTP readiness route.
 *
 * The default probe is deliberately false so importing the Express application
 * without the production bootstrap can never accidentally report readiness.
 */
export function registerDatabaseReadinessProbe(probe) {
  if (typeof probe !== 'function') {
    throw new TypeError(
      'Database readiness probe must be a function'
    );
  }

  databaseReadyProbe = probe;

  return function unregisterDatabaseReadinessProbe() {
    if (databaseReadyProbe === probe) {
      databaseReadyProbe = () => false;
    }
  };
}

export function markRuntimeReady() {
  runtimeReady = true;
}

export function markRuntimeNotReady() {
  runtimeReady = false;
}

export function evaluateReadiness({
  acceptingTraffic,
  databaseReady
}) {
  const ready =
    acceptingTraffic === true &&
    databaseReady === true;

  return {
    ready,
    status: ready ? 'ready' : 'not_ready',
    service: SERVICE_NAME
  };
}

export function currentReadiness() {
  let databaseReady = false;

  try {
    databaseReady =
      databaseReadyProbe() === true;
  } catch {
    // Readiness probes must fail closed and must never expose infrastructure
    // errors or convert them into a successful readiness response.
    databaseReady = false;
  }

  return evaluateReadiness({
    acceptingTraffic: runtimeReady,
    databaseReady
  });
}
