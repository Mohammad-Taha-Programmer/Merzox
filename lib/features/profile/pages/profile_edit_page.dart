import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'dart:ui' as ui;

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final List<_EmailFieldData> _emails = [];
  final List<_PhoneFieldData> _phones = [];
  String _gender = 'female';
  bool _initialized = false;
  bool _canChangeName = true;
  bool _canChangeGender = true;

  /// The birth date is held as three independent calendar components so the
  /// XD Day / Month / Year controls stay individually selectable. It is only
  /// assembled into a canonical `YYYY-MM-DD` at submit time.
  int? _birthDay;
  int? _birthMonth;
  int? _birthYear;
  String? _initialBirthDate;
  String? _birthDateError;

  /// The start of the Gregorian calendar, and the only floor the year list
  /// has. It is a calendar-domain bound, not an age bound: this product has no
  /// minimum-age, adult-only or maximum-age rule, so the selector must never
  /// encode one by cutting the list off at some span of years before today.
  static const _earliestGregorianYear = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    for (final email in _emails) {
      email.dispose();
    }
    for (final phone in _phones) {
      phone.dispose();
    }
    super.dispose();
  }

  void _initialize(AuthApiUser user) {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _canChangeName = user.canChangeName;
    _canChangeGender = user.canChangeGender;
    _nameController.text = user.name;
    _addressController.text = user.address;
    _gender = user.gender == 'male' ? 'male' : 'female';

    // A legacy account carries no birth date; the three selectors then stay
    // unselected and keep showing their placeholder labels.
    final birthDate = canonicalBirthDate(user.birthDate);
    _initialBirthDate = birthDate;

    if (birthDate != null) {
      _birthYear = int.parse(birthDate.substring(0, 4));
      _birthMonth = int.parse(birthDate.substring(5, 7));
      _birthDay = int.parse(birthDate.substring(8, 10));
    }

    final emails = user.emails.isNotEmpty
        ? user.emails
        : [
            if ((user.email ?? '').isNotEmpty)
              ContactEmail(value: user.email!, label: 'personal'),
          ];
    final phones = user.phones.isNotEmpty
        ? user.phones
        : [
            if ((user.phone ?? '').isNotEmpty)
              ContactPhone(value: user.phone!, label: 'mobile'),
          ];

    _emails
      ..clear()
      ..addAll(
        emails.isEmpty
            ? [_EmailFieldData()]
            : emails.map(
                (email) =>
                    _EmailFieldData(value: email.value, label: email.label),
              ),
      );
    _phones
      ..clear()
      ..addAll(
        phones.isEmpty
            ? [_PhoneFieldData()]
            : phones.map(
                (phone) =>
                    _PhoneFieldData(value: phone.value, label: phone.label),
              ),
      );
  }

  /// Today, as a calendar day, read in UTC.
  ///
  /// The backend compares birth dates against the UTC calendar day, so the
  /// selector uses the same clock. Reading the local day instead would, for
  /// anyone ahead of UTC, offer a "today" the server still considers tomorrow
  /// and reject for a few hours around midnight.
  DateTime get _today {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  int get _maxBirthMonth => _birthYear == _today.year ? _today.month : 12;

  /// The highest day the current month/year selection can legitimately offer.
  ///
  /// April stops at 30, February 2024 at 29 and February 2025 at 28. When the
  /// year is still unknown February stays open to 29 so a leap year remains
  /// reachable; the clamp below removes it again if a non-leap year follows.
  int get _maxBirthDay {
    final month = _birthMonth;

    if (month == null) {
      return 31;
    }

    final year = _birthYear;

    if (year == null) {
      return _daysInMonth(2024, month);
    }

    final inMonth = _daysInMonth(year, month);

    if (year == _today.year && month == _today.month) {
      return inMonth < _today.day ? inMonth : _today.day;
    }

    return inMonth;
  }

  /// Drops a selection that the new month/year makes impossible.
  ///
  /// Clearing is preferred over silently moving the user's chosen birthday to
  /// a neighbouring day they never picked.
  void _clampBirthSelection() {
    final month = _birthMonth;

    if (month != null && month > _maxBirthMonth) {
      _birthMonth = null;
    }

    final day = _birthDay;

    if (day != null && day > _maxBirthDay) {
      _birthDay = null;
    }
  }

  void _onBirthYearChanged(int? value) {
    setState(() {
      _birthYear = value;
      _birthDateError = null;
      _clampBirthSelection();
    });
  }

  void _onBirthMonthChanged(int? value) {
    setState(() {
      _birthMonth = value;
      _birthDateError = null;
      _clampBirthSelection();
    });
  }

  void _onBirthDayChanged(int? value) {
    setState(() {
      _birthDay = value;
      _birthDateError = null;
    });
  }

  /// The canonical `YYYY-MM-DD` for a complete selection, or null when the
  /// selection is incomplete, not a real calendar date, or in the future.
  String? _selectedBirthDate() {
    final year = _birthYear;
    final month = _birthMonth;
    final day = _birthDay;

    if (year == null || month == null || day == null) {
      return null;
    }

    final candidate = DateTime.utc(year, month, day);

    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day ||
        candidate.isAfter(_today)) {
      return null;
    }

    return '${year.toString().padLeft(4, '0')}'
        '-${month.toString().padLeft(2, '0')}'
        '-${day.toString().padLeft(2, '0')}';
  }

  void _submit() {
    final isFormValid = _formKey.currentState?.validate() ?? false;

    final chosen = [
      _birthYear,
      _birthMonth,
      _birthDay,
    ].where((part) => part != null).length;

    String? birthDateError;
    String? birthDate;

    if (chosen > 0 && chosen < 3) {
      // The birth date stays optional, but a half-filled one is a mistake
      // rather than an intent to clear it.
      birthDateError = 'profileEdit.birthDateIncomplete'.tr();
    } else if (chosen == 3) {
      birthDate = _selectedBirthDate();

      if (birthDate == null) {
        birthDateError = 'profileEdit.birthDateInvalid'.tr();
      }
    }

    if (_birthDateError != birthDateError) {
      setState(() => _birthDateError = birthDateError);
    }

    if (!isFormValid || birthDateError != null) {
      return;
    }

    final user = context.read<ProfileEditBloc>().state.user;
    context.read<ProfileEditBloc>().add(
      ProfileEditSubmitted(
        name: _canChangeName && _nameController.text.trim() != user?.name
            ? _nameController.text.trim()
            : null,
        gender: _canChangeGender && _gender != user?.gender ? _gender : null,
        address: _addressController.text.trim(),
        // An unchanged date is not resent: the PATCH carries the field only
        // when it actually differs from the stored value.
        birthDate: birthDate == _initialBirthDate ? null : birthDate,
        emails: _emails
            .map(
              (email) => ContactEmail(
                value: email.controller.text.trim().toLowerCase(),
                label: email.label,
              ),
            )
            .where((email) => email.value.isNotEmpty)
            .toList(),
        phones: _phones
            .map(
              (phone) => ContactPhone(
                value: _normalizePhone(phone.controller.text),
                label: phone.label,
              ),
            )
            .where((phone) => phone.value.isNotEmpty)
            .toList(),
      ),
    );
  }

  String _normalizePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');
      return digits.isEmpty ? '' : '+$digits';
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    final withoutLeadingZero = digits.startsWith('0')
        ? digits.substring(1)
        : digits;
    return withoutLeadingZero.isEmpty ? '' : '+970$withoutLeadingZero';
  }

  void _addEmail() {
    setState(() => _emails.add(_EmailFieldData(label: 'other')));
  }

  void _addPhone() {
    setState(() => _phones.add(_PhoneFieldData(label: 'other')));
  }

  Future<void> _toggleLanguage() async {
    final nextLocale = context.locale.languageCode == 'ar'
        ? const Locale('en')
        : const Locale('ar');
    await context.setLocale(nextLocale);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileEditBloc, ProfileEditState>(
      listener: (context, state) {
        if (state.status == ProfileEditStatus.success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('profileEdit.saved'.tr())));
          context.go('/home');
        }

        if (state.status == ProfileEditStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizeApiErrorOrRaw(state.errorMessage!))),
          );
        }
      },
      builder: (context, state) {
        final user = state.user;
        if (user != null) {
          _initialize(user);
        }

        final isBusy =
            state.status == ProfileEditStatus.loading ||
            state.status == ProfileEditStatus.saving;

        return Directionality(
          textDirection: Directionality.of(context),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: state.status == ProfileEditStatus.loading && user == null
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(21, 18, 21, 32),
                        children: [
                          _ProfileEditHeader(
                            onBack: () => context.pop(),
                            onToggleLanguage: _toggleLanguage,
                          ),
                          const SizedBox(height: 34),
                          _ProfileLabel(text: 'auth.fullNameLabel'.tr()),
                          _ProfileTextField(
                            controller: _nameController,
                            hintText: 'auth.fullNameHint'.tr(),
                            enabled: _canChangeName && !isBusy,
                            validator: (value) {
                              if (!_canChangeName) return null;
                              return (value?.trim().length ?? 0) >= 2
                                  ? null
                                  : 'profileEdit.nameTooShort'.tr();
                            },
                          ),
                          if (!_canChangeName)
                            _RestrictionText(
                              text: 'profileEdit.nameChangeUsed'.tr(),
                            ),
                          const SizedBox(height: 18),
                          _ProfileLabel(
                            text: 'businessEnrollment.emailLabel'.tr(),
                          ),
                          ..._emails.asMap().entries.map(
                            (entry) => _EmailInputRow(
                              data: entry.value,
                              enabled: !isBusy,
                              canRemove: _emails.length > 1,
                              onRemove: () {
                                setState(() {
                                  entry.value.dispose();
                                  _emails.removeAt(entry.key);
                                });
                              },
                            ),
                          ),
                          _AddLineButton(
                            text: 'profileEdit.addEmail'.tr(),
                            onTap: _addEmail,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(
                            text: 'businessEnrollment.phoneLabel'.tr(),
                          ),
                          ..._phones.asMap().entries.map(
                            (entry) => _PhoneInputRow(
                              data: entry.value,
                              enabled: !isBusy,
                              canRemove: _phones.length > 1,
                              onRemove: () {
                                setState(() {
                                  entry.value.dispose();
                                  _phones.removeAt(entry.key);
                                });
                              },
                            ),
                          ),
                          _AddLineButton(
                            text: 'profileEdit.addPhone'.tr(),
                            onTap: _addPhone,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(text: 'business.address'.tr()),
                          _ProfileTextField(
                            controller: _addressController,
                            hintText: 'profileEdit.addressHint'.tr(),
                            enabled: !isBusy,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(text: 'profileEdit.gender'.tr()),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _GenderChoice(
                                label: 'profileEdit.genderFemale'.tr(),
                                value: 'female',
                                groupValue: _gender,
                                enabled: _canChangeGender && !isBusy,
                                onChanged: (value) {
                                  setState(() => _gender = value);
                                },
                              ),
                              const SizedBox(width: 28),
                              _GenderChoice(
                                label: 'profileEdit.genderMale'.tr(),
                                value: 'male',
                                groupValue: _gender,
                                enabled: _canChangeGender && !isBusy,
                                onChanged: (value) {
                                  setState(() => _gender = value);
                                },
                              ),
                            ],
                          ),
                          if (!_canChangeGender)
                            _RestrictionText(
                              text: 'profileEdit.genderChangeUsed'.tr(),
                            ),
                          const SizedBox(height: 20),
                          _ProfileLabel(text: 'profileEdit.birthDate'.tr()),
                          _BirthDateSelectors(
                            day: _birthDay,
                            month: _birthMonth,
                            year: _birthYear,
                            maxDay: _maxBirthDay,
                            maxMonth: _maxBirthMonth,
                            latestYear: _today.year,
                            earliestYear: _earliestGregorianYear,
                            enabled: !isBusy,
                            errorText: _birthDateError,
                            onDayChanged: _onBirthDayChanged,
                            onMonthChanged: _onBirthMonthChanged,
                            onYearChanged: _onBirthYearChanged,
                          ),
                          const SizedBox(height: 124),
                          Center(
                            child: SizedBox(
                              width: 210,
                              height: 55,
                              child: FilledButton(
                                onPressed: isBusy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: MerzoxColors.kColorEE6C4D,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: isBusy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        'common.save'.tr(),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileEditHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onToggleLanguage;

  const _ProfileEditHeader({
    required this.onBack,
    required this.onToggleLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == ui.TextDirection.rtl;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              'profileEdit.title'.tr(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2B2B2B),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'common.back'.tr(),
              onPressed: onBack,
              icon: Icon(
                isRtl
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.arrow_back_ios_new_rounded,
                size: 28,
                color: const Color(0xFF686868),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              tooltip: 'profileEdit.changeLanguage'.tr(),
              onPressed: onToggleLanguage,
              icon: Icon(
                Icons.language_rounded,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLabel extends StatelessWidget {
  final String text;

  const _ProfileLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: TextAlign.start,
        style: const TextStyle(fontSize: 14, color: Color(0xFF2B2B2B)),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final String? Function(String?)? validator;

  const _ProfileTextField({
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        textAlign: TextAlign.start,
        validator: validator,
        decoration: _profileInputDecoration(hintText),
      ),
    );
  }
}

class _EmailInputRow extends StatelessWidget {
  final _EmailFieldData data;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  const _EmailInputRow({
    required this.data,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledContactRow(
      controller: data.controller,
      label: data.label,
      labels: _emailLabels,
      hintText: 'profileEdit.emailHint'.tr(),
      enabled: enabled,
      canRemove: canRemove,
      keyboardType: TextInputType.emailAddress,
      onLabelChanged: (value) => data.label = value,
      onRemove: onRemove,
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) return null;
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)
            ? null
            : 'validation.invalidEmail'.tr();
      },
    );
  }
}

class _PhoneInputRow extends StatelessWidget {
  final _PhoneFieldData data;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  const _PhoneInputRow({
    required this.data,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledContactRow(
      controller: data.controller,
      label: data.label,
      labels: _phoneLabels,
      hintText: 'profileEdit.phoneHint'.tr(),
      enabled: enabled,
      canRemove: canRemove,
      keyboardType: TextInputType.phone,
      onLabelChanged: (value) => data.label = value,
      onRemove: onRemove,
      validator: (value) {
        final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return null;
        return digits.length >= 7 ? null : 'profileEdit.phoneTooShort'.tr();
      },
    );
  }
}

class _LabeledContactRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Map<String, String> labels;
  final String hintText;
  final bool enabled;
  final bool canRemove;
  final TextInputType keyboardType;
  final ValueChanged<String> onLabelChanged;
  final VoidCallback onRemove;
  final String? Function(String?)? validator;

  const _LabeledContactRow({
    required this.controller,
    required this.label,
    required this.labels,
    required this.hintText,
    required this.enabled,
    required this.canRemove,
    required this.keyboardType,
    required this.onLabelChanged,
    required this.onRemove,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 54,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: labels.containsKey(label)
                  ? label
                  : labels.keys.first,
              items: labels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value.tr(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (value) {
                      if (value != null) onLabelChanged(value);
                    }
                  : null,
              decoration: _profileInputDecoration(''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 54,
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                keyboardType: keyboardType,
                textAlign: TextAlign.start,
                validator: validator,
                decoration: _profileInputDecoration(hintText),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: canRemove
                ? IconButton(
                    tooltip: 'common.delete'.tr(),
                    onPressed: enabled ? onRemove : null,
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: MerzoxColors.kColorE40909,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _AddLineButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _AddLineButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(text),
        style: TextButton.styleFrom(foregroundColor: MerzoxColors.kColor3D5A80),
      ),
    );
  }
}

class _GenderChoice extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _GenderChoice({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;

    return InkWell(
      onTap: enabled ? () => onChanged(value) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 18,
            height: 18,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? MerzoxColors.kColor98C1D9
                    : MerzoxColors.kColor8D99AE,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? MerzoxColors.kColor98C1D9
                    : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keys for the three XD birth-date controls.
///
/// Selection is real state on the page, so a test asserts against the control
/// rather than against a rendered placeholder string.
const birthDayFieldKey = Key('profileEdit.birthDay');
const birthMonthFieldKey = Key('profileEdit.birthMonth');
const birthYearFieldKey = Key('profileEdit.birthYear');

/// The XD Day | Month | Year row, made interactive.
///
/// The visual structure is unchanged: three horizontal bordered dropdown-style
/// controls sharing the profile form's border, radius and placeholder colours,
/// laid out directionally so RTL and LTR both read Day first.
class _BirthDateSelectors extends StatelessWidget {
  final int? day;
  final int? month;
  final int? year;
  final int maxDay;
  final int maxMonth;
  final int latestYear;
  final int earliestYear;
  final bool enabled;
  final String? errorText;
  final ValueChanged<int?> onDayChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<int?> onYearChanged;

  const _BirthDateSelectors({
    required this.day,
    required this.month,
    required this.year,
    required this.maxDay,
    required this.maxMonth,
    required this.latestYear,
    required this.earliestYear,
    required this.enabled,
    required this.errorText,
    required this.onDayChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthDayFieldKey,
                label: 'profileEdit.day'.tr(),
                value: day,
                options: [
                  for (var option = 1; option <= maxDay; option++) option,
                ],
                enabled: enabled,
                onChanged: onDayChanged,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthMonthFieldKey,
                label: 'profileEdit.month'.tr(),
                value: month,
                options: [
                  for (var option = 1; option <= maxMonth; option++) option,
                ],
                enabled: enabled,
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthYearFieldKey,
                label: 'profileEdit.year'.tr(),
                value: year,
                // The whole past calendar domain, newest first. The list is
                // long on purpose: truncating it to a span of years would be a
                // maximum-age rule, and this product has none.
                options: [
                  for (
                    var option = latestYear;
                    option >= earliestYear;
                    option--
                  )
                    option,
                ],
                enabled: enabled,
                onChanged: onYearChanged,
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: MerzoxColors.kColorE40909),
            ),
          ),
      ],
    );
  }
}

class _BirthDateDropdown extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final int? value;
  final List<int> options;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  const _BirthDateDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The unselected label keeps the XD placeholder colour, and is repeated as
    // the disabled hint so a busy form still reads Day / Month / Year.
    final placeholder = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 14, color: MerzoxColors.kColorC7C7C7),
    );

    return SizedBox(
      height: 55,
      child: InputDecorator(
        decoration: _profileInputDecoration(''),
        child: DropdownButtonHideUnderline(
          // A plain DropdownButton is used rather than the form-field variant
          // because the page owns the value: when a month change invalidates
          // the chosen day, the control must follow that state immediately.
          child: DropdownButton<int>(
            key: fieldKey,
            isExpanded: true,
            isDense: true,
            menuMaxHeight: 320,
            value: options.contains(value) ? value : null,
            hint: placeholder,
            disabledHint: placeholder,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: MerzoxColors.kColor3D5A80,
            ),
            borderRadius: BorderRadius.circular(4),
            items: [
              for (final option in options)
                DropdownMenuItem<int>(
                  value: option,
                  child: Text('$option', style: const TextStyle(fontSize: 14)),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

/// The length of a Gregorian month: day zero of the next month is its last.
int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

class _RestrictionText extends StatelessWidget {
  final String text;

  const _RestrictionText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: MerzoxColors.kColor8D99AE),
      ),
    );
  }
}

InputDecoration _profileInputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontSize: 14, color: MerzoxColors.kColorC7C7C7),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: _profileBorder(MerzoxColors.kColorB9DDF3),
    enabledBorder: _profileBorder(MerzoxColors.kColorB9DDF3),
    focusedBorder: _profileBorder(MerzoxColors.kColor98C1D9, 1.4),
    errorBorder: _profileBorder(MerzoxColors.kColorE40909),
    focusedErrorBorder: _profileBorder(MerzoxColors.kColorE40909, 1.4),
  );
}

OutlineInputBorder _profileBorder(Color color, [double width = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _EmailFieldData {
  final TextEditingController controller;
  String label;

  _EmailFieldData({String value = '', this.label = 'personal'})
    : controller = TextEditingController(text: value);

  void dispose() => controller.dispose();
}

class _PhoneFieldData {
  final TextEditingController controller;
  String label;

  _PhoneFieldData({String value = '', this.label = 'mobile'})
    : controller = TextEditingController(text: value);

  void dispose() => controller.dispose();
}

const _emailLabels = {
  'personal': 'profileEdit.contactLabels.personal',
  'work': 'profileEdit.contactLabels.work',
  'home': 'profileEdit.contactLabels.home',
  'other': 'profileEdit.contactLabels.other',
};

const _phoneLabels = {
  'mobile': 'profileEdit.contactLabels.mobile',
  'work': 'profileEdit.contactLabels.work',
  'home': 'profileEdit.contactLabels.home',
  'fax': 'profileEdit.contactLabels.fax',
  'other': 'profileEdit.contactLabels.other',
};
