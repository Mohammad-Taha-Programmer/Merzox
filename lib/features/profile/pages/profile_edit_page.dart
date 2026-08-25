import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/services/api_service.dart';
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

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
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
                          const _BirthdayPlaceholders(),
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

class _BirthdayPlaceholders extends StatelessWidget {
  const _BirthdayPlaceholders();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PlaceholderDropdown(text: 'profileEdit.day'.tr())),
        const SizedBox(width: 18),
        Expanded(child: _PlaceholderDropdown(text: 'profileEdit.month'.tr())),
        const SizedBox(width: 18),
        Expanded(child: _PlaceholderDropdown(text: 'profileEdit.year'.tr())),
      ],
    );
  }
}

class _PlaceholderDropdown extends StatelessWidget {
  final String text;

  const _PlaceholderDropdown({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColorB9DDF3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: TextStyle(color: MerzoxColors.kColorC7C7C7)),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: MerzoxColors.kColor3D5A80,
          ),
        ],
      ),
    );
  }
}

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
