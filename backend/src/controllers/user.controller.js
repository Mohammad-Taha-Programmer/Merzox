import {
  BIRTH_DATE_ERRORS,
  parseBirthDate
} from '../policies/birth-date.policy.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { normalizeGender, normalizeIdentifier, normalizePhone } from '../utils/normalize.js';
import { pick } from '../utils/pick.js';
import {
  notificationPreferenceView,
  parseNotificationPreferencePatch,
  updateProductOffersPreference
} from '../services/notification-preference.service.js';

const emailLabels = new Set(['personal', 'work', 'home', 'other']);
const phoneLabels = new Set(['mobile', 'work', 'home', 'fax', 'other']);

export const getMyNotificationPreferences = asyncHandler(async (req, res) => {
  res.json({
    success: true,
    data: {
      notificationPreferences: notificationPreferenceView(req.user)
    }
  });
});

export const updateMyNotificationPreferences = asyncHandler(
  async (req, res) => {
    const productOffers = parseNotificationPreferencePatch(req.body);

    const notificationPreferences = await updateProductOffersPreference({
      user: req.user,
      productOffers
    });

    res.json({
      success: true,
      data: { notificationPreferences }
    });
  }
);

export const updateMe = asyncHandler(async (req, res) => {
  const updates = pick(req.body, [
    'name',
    'gender',
    'address',
    'birthDate',
    'emails',
    'phones',
    'permissions'
  ]);

  if (updates.name !== undefined) {
    const nextName = String(updates.name).trim();

    if (req.user.nameChangedAt) {
      throw new AppError('Name can only be changed once', 400, 'NAME_CHANGE_LIMIT');
    }

    if (nextName.length < 2) {
      throw new AppError('Name must be at least 2 characters', 400, 'INVALID_NAME');
    }

    req.user.name = nextName;
    req.user.nameChangedAt = new Date();
  }

  if (updates.gender !== undefined) {
    const nextGender = normalizeGender(updates.gender);

    if (req.user.genderChangedAt) {
      throw new AppError('Gender can only be changed once', 400, 'GENDER_CHANGE_LIMIT');
    }

    req.user.gender = nextGender;
    req.user.genderChangedAt = new Date();
  }

  if (updates.address !== undefined) {
    req.user.address = String(updates.address).trim();
  }

  // An omitted birthDate leaves the stored value untouched. This carries no
  // one-time-change restriction, so nameChangedAt/genderChangedAt are not
  // consulted or written here.
  if (updates.birthDate !== undefined) {
    if (updates.birthDate === null) {
      req.user.birthDate = null;
    } else {
      const birthDate = parseBirthDate(updates.birthDate);

      if (!birthDate) {
        throw new AppError(
          'Date of birth must be a real past date in YYYY-MM-DD format',
          400,
          BIRTH_DATE_ERRORS.invalid
        );
      }

      req.user.birthDate = birthDate;
    }
  }

  if (Array.isArray(updates.emails)) {
    const normalizedEmails = updates.emails
      .map((email, index) => {
        const value = normalizeIdentifier(typeof email === 'string' ? email : email.value);
        const label = typeof email === 'object' && emailLabels.has(email.label)
          ? email.label
          : index === 0
          ? 'personal'
          : 'other';

        return { value, label, isPrimary: index === 0 };
      })
      .filter((email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value));

    const uniqueEmails = [];
    const seenEmails = new Set();
    for (const email of normalizedEmails) {
      if (!seenEmails.has(email.value)) {
        seenEmails.add(email.value);
        uniqueEmails.push(email);
      }
    }

    const conflictingUser = await req.user.constructor.findOne({
      _id: { $ne: req.user._id },
      $or: [
        { email: { $in: uniqueEmails.map((email) => email.value) } },
        { 'emails.value': { $in: uniqueEmails.map((email) => email.value) } }
      ]
    });

    if (conflictingUser) {
      throw new AppError('Email already belongs to another account', 409, 'EMAIL_EXISTS');
    }

    req.user.emails = uniqueEmails.map((email, index) => ({
      ...email,
      isPrimary: index === 0,
      verified: req.user.email === email.value ? req.user.emailVerified : false
    }));
    req.user.email = uniqueEmails[0]?.value;
    req.user.emailVerified = req.user.emails[0]?.verified ?? false;
  }

  if (Array.isArray(updates.phones)) {
    const normalizedPhones = updates.phones
      .map((phone, index) => {
        const value = normalizePhone(typeof phone === 'string' ? phone : phone.value);
        const label = typeof phone === 'object' && phoneLabels.has(phone.label)
          ? phone.label
          : index === 0
          ? 'mobile'
          : 'other';

        return { value, label, isPrimary: index === 0 };
      })
      .filter((phone) => /^\+?[0-9]{7,15}$/.test(phone.value));

    const uniquePhones = [];
    const seenPhones = new Set();
    for (const phone of normalizedPhones) {
      if (!seenPhones.has(phone.value)) {
        seenPhones.add(phone.value);
        uniquePhones.push(phone);
      }
    }

    const conflictingUser = await req.user.constructor.findOne({
      _id: { $ne: req.user._id },
      $or: [
        { phone: { $in: uniquePhones.map((phone) => phone.value) } },
        { 'phones.value': { $in: uniquePhones.map((phone) => phone.value) } }
      ]
    });

    if (conflictingUser) {
      throw new AppError('Phone number already belongs to another account', 409, 'PHONE_EXISTS');
    }

    req.user.phones = uniquePhones.map((phone, index) => ({
      value: phone.value,
      label: phone.label,
      isPrimary: index === 0
    }));
    req.user.phone = uniquePhones[0]?.value;
  }

  if (updates.permissions && typeof updates.permissions === 'object') {
    const allowedPermissions = pick(updates.permissions, [
      'aiPersonalization',
      'location',
      'contacts'
    ]);
    const booleanPermissions = Object.fromEntries(
      Object.entries(allowedPermissions).filter(
        ([, value]) => typeof value === 'boolean'
      )
    );

    req.user.permissions = {
      ...req.user.permissions,
      ...booleanPermissions
    };

    for (const [key, value] of Object.entries(booleanPermissions)) {
      req.user.permissionConsents ??= {};
      req.user.permissionConsents[key] = {
        status: value ? 'granted' : 'denied',
        askedAt: req.user.permissionConsents?.[key]?.askedAt ?? new Date(),
        respondedAt: new Date()
      };
    }
  }

  await req.user.save();

  res.json({ success: true, data: { user: req.user.toSafeJSON() } });
});
