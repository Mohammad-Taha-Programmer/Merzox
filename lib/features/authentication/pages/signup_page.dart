import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';

class SignupPage extends StatefulWidget {
  final VoidCallback onSignupCreated;
  final VoidCallback onLoginRequested;

  const SignupPage({
    super.key,
    required this.onSignupCreated,
    required this.onLoginRequested,
  });

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  _DialCode _selectedDialCode = _dialCodes.first;
  _Gender _gender = _Gender.female;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(AuthBloc bloc) {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    bloc.add(
      SignupSubmitted(
        name: _nameController.text,
        identifier: _normalizedIdentifier,
        password: _passwordController.text,
        address: '',
        userType: UserType.normal,
        gender: _gender.name,
      ),
    );
  }

  bool get _identifierIsEmail =>
      _identifierController.text.trim().contains('@');

  String get _normalizedIdentifier {
    final value = _identifierController.text.trim();
    if (_identifierIsEmail) {
      return value.toLowerCase();
    }

    final countryCode = _selectedDialCode.prefix.startsWith('+')
        ? _selectedDialCode.prefix
        : '+${_selectedDialCode.prefix}';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final localNumber = digits.startsWith('0') ? digits.substring(1) : digits;

    return '$countryCode$localNumber';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.signupCreated) {
          final message = state.successMessageKey?.tr() ?? state.successMessage;

          if (message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }

          widget.onSignupCreated();
        }

        if (state.status == AuthStatus.failure) {
          final message = state.errorMessageKey?.tr() ?? state.errorMessage;

          if (message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        }
      },
      builder: (context, state) {
        final bloc = context.read<AuthBloc>();
        final isLoading = state.status == AuthStatus.loading;

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        MediaQuery.sizeOf(context).height -
                        MediaQuery.paddingOf(context).top -
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SignupHeader(onBack: widget.onLoginRequested),
                      const SizedBox(height: 24),
                      const _Logo(),
                      const SizedBox(height: 28),
                      Text(
                        'authGate.signup'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'auth.signupSubtitle'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: MerzoxColors.kColor8D99AE,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _LabeledField(
                        label: 'auth.fullNameLabel'.tr(),
                        child: TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          textAlign: TextAlign.start,
                          decoration: _fieldDecoration(
                            hintText: 'auth.fullNameHint'.tr(),
                          ),
                          validator: _requiredValidator,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LabeledField(
                        label: 'auth.signupIdentifierLabel'.tr(),
                        child: TextFormField(
                          controller: _identifierController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          textAlign: TextAlign.start,
                          onChanged: (_) => setState(() {}),
                          decoration: _fieldDecoration(
                            hintText: 'auth.signupIdentifierHint'.tr(),
                            prefixIcon: _identifierIsEmail
                                ? null
                                : _DialCodeDropdown(
                                    value: _selectedDialCode,
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() {
                                        _selectedDialCode = value;
                                      });
                                    },
                                  ),
                            prefixIconConstraints: _identifierIsEmail
                                ? null
                                : const BoxConstraints.tightFor(
                                    width: 120,
                                    height: 46,
                                  ),
                          ),
                          validator: _identifierValidator,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LabeledField(
                        label: 'auth.password'.tr(),
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          textAlign: TextAlign.start,
                          decoration: _fieldDecoration(
                            hintText: 'auth.passwordHint'.tr(),
                            prefixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'auth.showPassword'.tr()
                                  : 'auth.hidePassword'.tr(),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: MerzoxColors.kColor98C1D9,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'validation.required'.tr();
                            }

                            if (value.trim().length < 6) {
                              return 'validation.passwordMin6'.tr();
                            }

                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'auth.gender'.tr(),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _GenderRadio(
                              label: 'auth.female'.tr(),
                              value: _Gender.female,
                              groupValue: _gender,
                              onChanged: (value) {
                                setState(() {
                                  _gender = value;
                                });
                              },
                            ),
                            const SizedBox(width: 28),
                            _GenderRadio(
                              label: 'auth.male'.tr(),
                              value: _Gender.male,
                              groupValue: _gender,
                              onChanged: (value) {
                                setState(() {
                                  _gender = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 42),
                      Center(
                        child: SizedBox(
                          width: 221,
                          height: 47,
                          child: FilledButton(
                            onPressed: isLoading ? null : () => _submit(bloc),
                            style: FilledButton.styleFrom(
                              backgroundColor: MerzoxColors.kColorEE6C4D,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'auth.createAccountButton'.tr(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'auth.haveAccount'.tr(),
                            style: TextStyle(
                              fontSize: 14,
                              color: MerzoxColors.kColor8D99AE,
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onLoginRequested,
                            child: Text(
                              'auth.signInAction'.tr(),
                              style: TextStyle(
                                fontSize: 14,
                                color: MerzoxColors.kColor3D5A80,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'validation.required'.tr();
    }

    return null;
  }

  String? _identifierValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'validation.required'.tr();
    }

    if (trimmed.contains('@')) {
      final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      return emailPattern.hasMatch(trimmed)
          ? null
          : 'validation.invalidEmail'.tr();
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    final localNumber = digits.startsWith('0') ? digits.substring(1) : digits;
    final countryCode = _selectedDialCode.prefix.startsWith('+')
        ? _selectedDialCode.prefix
        : '+${_selectedDialCode.prefix}';
    final normalized = '$countryCode$localNumber';

    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)
        ? null
        : 'validation.invalidPhone'.tr();
  }
}

class _SignupHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _SignupHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'auth.createAccountButton'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2B2B),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'common.back'.tr(),
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 26,
                color: Color(0xFF3B3B3B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/MERZOX_LOGO.png',
      height: 80,
      fit: BoxFit.contain,
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.start,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2B2B2B),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 46, child: child),
      ],
    );
  }
}

InputDecoration _fieldDecoration({
  required String hintText,
  Widget? prefixIcon,
  BoxConstraints? prefixIconConstraints,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontSize: 13, color: MerzoxColors.kColorC7C7C7),
    prefixIcon: prefixIcon,
    prefixIconConstraints:
        prefixIconConstraints ??
        const BoxConstraints(minWidth: 48, minHeight: 46),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true,
    fillColor: Colors.white,
    border: _border(MerzoxColors.kColorB9DDF3),
    enabledBorder: _border(MerzoxColors.kColorB9DDF3),
    focusedBorder: _border(MerzoxColors.kColor98C1D9, 1.4),
    errorBorder: _border(MerzoxColors.kColorE40909),
    focusedErrorBorder: _border(MerzoxColors.kColorE40909, 1.4),
  );
}

class _DialCodeDropdown extends StatelessWidget {
  final _DialCode value;
  final ValueChanged<_DialCode?> onChanged;

  const _DialCodeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(color: MerzoxColors.kColorB9DDF3),
          ),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_DialCode>(
                value: value,
                isDense: true,
                isExpanded: true,
                iconSize: 16,
                dropdownColor: Colors.white,
                onChanged: onChanged,
                selectedItemBuilder: (context) {
                  return _dialCodes
                      .map((dialCode) => _DialCodeView(dialCode: dialCode))
                      .toList();
                },
                items: _dialCodes.map((dialCode) {
                  return DropdownMenuItem(
                    value: dialCode,
                    child: _DialCodeView(dialCode: dialCode),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialCodeView extends StatelessWidget {
  final _DialCode dialCode;

  const _DialCodeView({required this.dialCode});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.ltr,
      children: [
        Text(dialCode.flag, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(
          dialCode.prefix,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 13, color: Color(0xFF2B2B2B)),
        ),
      ],
    );
  }
}

class _GenderRadio extends StatelessWidget {
  final String label;
  final _Gender value;
  final _Gender groupValue;
  final ValueChanged<_Gender> onChanged;

  const _GenderRadio({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onChanged(value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: MerzoxColors.kColor707070)),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 18,
            height: 18,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: value == groupValue
                    ? MerzoxColors.kColor3D5A80
                    : MerzoxColors.kColor98C1D9,
                width: 1.6,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value == groupValue
                    ? MerzoxColors.kColor3D5A80
                    : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

OutlineInputBorder _border(Color color, [double width = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color, width: width),
  );
}

enum _Gender { male, female }

class _DialCode {
  final String flag;
  final String prefix;

  const _DialCode({required this.flag, required this.prefix});

  @override
  String toString() => prefix;
}

const List<_DialCode> _dialCodes = [
  _DialCode(flag: '🇮🇱', prefix: '+972'),
  _DialCode(flag: '🇵🇸', prefix: '+970'),
  _DialCode(flag: '🇯🇴', prefix: '+962'),
  _DialCode(flag: '🇪🇬', prefix: '+20'),
  _DialCode(flag: '🇸🇦', prefix: '+966'),
  _DialCode(flag: '🇦🇪', prefix: '+971'),
  _DialCode(flag: '🇺🇸', prefix: '+1'),
];
