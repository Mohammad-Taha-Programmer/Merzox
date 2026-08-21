export function normalizeIdentifier(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function normalizePhone(value) {
  return String(value ?? '').trim().replace(/[^\d+]/g, '');
}

export function normalizeUserType(value) {
  return value === 'business' ? 'business' : 'normal';
}

export function normalizeGender(value) {
  if (value === 'male' || value === 'female') {
    return value;
  }

  return 'unspecified';
}
