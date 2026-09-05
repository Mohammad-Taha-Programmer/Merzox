export function normalizeIdentifier(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function normalizePhone(value) {
  return String(value ?? '').trim().replace(/[^\d+]/g, '');
}

export function normalizeGender(value) {
  if (value === 'male' || value === 'female') {
    return value;
  }

  return 'unspecified';
}
