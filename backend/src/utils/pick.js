export function pick(source, allowedKeys) {
  return allowedKeys.reduce((result, key) => {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      result[key] = source[key];
    }

    return result;
  }, {});
}
