export function applyProxyTrust(
  app,
  trustedProxyRanges
) {
  if (
    !app ||
    typeof app.set !== 'function'
  ) {
    throw new TypeError(
      'Express application is required'
    );
  }

  if (
    !Array.isArray(
      trustedProxyRanges
    )
  ) {
    throw new TypeError(
      'Trusted proxy ranges must be an array'
    );
  }

  if (
    trustedProxyRanges.length === 0
  ) {
    app.set(
      'trust proxy',
      false
    );

    return;
  }

  app.set(
    'trust proxy',
    trustedProxyRanges
  );
}
