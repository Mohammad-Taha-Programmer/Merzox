import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final VoidCallback onBrowseAsGuest;
  final VoidCallback onSignupRequested;
  final bool businessMode;

  const LoginPage({
    super.key,
    required this.onAuthenticated,
    required this.onBrowseAsGuest,
    required this.onSignupRequested,
    this.businessMode = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  _CountryDialCode _selectedCountry = _countryDialCodes.firstWhere(
    (country) => country.prefix == '+972',
  );
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(AuthBloc bloc) {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final identifier = _normalizedIdentifier;

    bloc.add(
      LoginSubmitted(
        identifier: identifier,
        password: _passwordController.text,
        requiredUserType: widget.businessMode ? 'business' : null,
      ),
    );
  }

  String get _normalizedIdentifier {
    final value = _identifierController.text.trim();
    final isEmail = value.contains('@');
    final hasInternationalPrefix = value.startsWith('+');

    if (isEmail || hasInternationalPrefix) {
      return value;
    }

    final countryCode = _selectedCountry.prefix.startsWith('+')
        ? _selectedCountry.prefix
        : '+${_selectedCountry.prefix}';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final localNumber = digits.startsWith('0') ? digits.substring(1) : digits;

    return '$countryCode$localNumber';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == AuthStatus.authenticated) {
            widget.onAuthenticated();
          }

          if (state.status == AuthStatus.guest) {
            widget.onBrowseAsGuest();
          }

          if (state.status == AuthStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _AuthTopBar(title: 'تسجيل الدخول'),
                            const SizedBox(height: 34),
                            const _AuthLogo(),
                            const SizedBox(height: 34),
                            const _AuthTitleBlock(
                              title: 'تسجيل الدخول',
                              subtitle:
                                  'الرجاء تسجيل الدخول لمواصلة استخدام التطبيق',
                            ),
                            const SizedBox(height: 26),
                            _XdField(
                              label: 'رقم الجوال أو البريد الإلكتروني',
                              hint: 'قم بإدخال رقم الجوال أو البريد الإلكتروني',
                              controller: _identifierController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              leading: _CountryCodeDropdown(
                                selectedCountry: _selectedCountry,
                                onChanged: (country) {
                                  if (country == null) {
                                    return;
                                  }

                                  setState(() {
                                    _selectedCountry = country;
                                  });
                                },
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'هذا الحقل مطلوب';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _XdField(
                              label: 'كلمة المرور',
                              hint: 'الرجاء قم بإدخال كلمة المرور',
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(bloc),
                              trailing: IconButton(
                                tooltip: _obscurePassword
                                    ? 'إظهار كلمة المرور'
                                    : 'إخفاء كلمة المرور',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: MerzoxColors.kColor98C1D9,
                                  size: 20,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'هذا الحقل مطلوب';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: MerzoxColors.kColor3D5A80,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? true;
                                    });
                                  },
                                ),
                                const Text(
                                  'تذكرني لاحقاً',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    'نسيت كلمة المرور؟',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            _PrimaryAuthButton(
                              label: 'تسجيل الدخول',
                              isLoading: isLoading,
                              onPressed: () => _submit(bloc),
                            ),
                            const SizedBox(height: 14),
                            if (!widget.businessMode)
                              TextButton(
                                onPressed: isLoading
                                    ? null
                                    : () =>
                                          bloc.add(const GuestSessionStarted()),
                                child: const Text('المتابعة كضيف'),
                              ),
                            const SizedBox(height: 18),
                            if (!widget.businessMode)
                              _SwitchAuthMode(
                                prompt: 'ألا تملك حساب؟',
                                action: 'قم بإنشاء حساب',
                                onPressed: widget.onSignupRequested,
                              ),
                            const SizedBox(height: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuthTopBar extends StatelessWidget {
  final String title;

  const _AuthTopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2B2B),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthLogo extends StatelessWidget {
  const _AuthLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/MERZOX_LOGO.png',
          height: 82,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),
        const Text(
          'Merzox',
          style: TextStyle(
            fontFamily: 'Concept',
            fontSize: 22,
            color: Color(0xFF2B2B2B),
          ),
        ),
      ],
    );
  }
}

class _AuthTitleBlock extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AuthTitleBlock({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2B2B2B),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: MerzoxColors.kColor767676,
          ),
        ),
      ],
    );
  }
}

class _XdField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? leading;
  final Widget? trailing;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  const _XdField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.leading,
    this.trailing,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2B2B),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            onFieldSubmitted: onSubmitted,
            validator: validator,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColorBEBEBE,
              ),
              prefixIcon: leading,
              suffixIcon: trailing,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MerzoxColors.kColorC7C7C7),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MerzoxColors.kColorC7C7C7),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF006CBF),
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryCodeDropdown extends StatelessWidget {
  final _CountryDialCode selectedCountry;
  final ValueChanged<_CountryDialCode?> onChanged;

  const _CountryCodeDropdown({
    required this.selectedCountry,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_CountryDialCode>(
          value: selectedCountry,
          isDense: true,
          iconSize: 18,
          menuMaxHeight: 300,
          dropdownColor: Colors.white,
          onChanged: onChanged,
          selectedItemBuilder: (context) {
            return _countryDialCodes.map((country) {
              return _CountryDialCodeView(country: country);
            }).toList();
          },
          items: _countryDialCodes.map((country) {
            return DropdownMenuItem(
              value: country,
              child: _CountryDialCodeView(country: country),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CountryDialCodeView extends StatelessWidget {
  final _CountryDialCode country;

  const _CountryDialCodeView({required this.country});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        Text(country.flag, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(
          country.prefix,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 13, color: Color(0xFF2B2B2B)),
        ),
      ],
    );
  }
}

class _CountryDialCode {
  final String flag;
  final String prefix;

  const _CountryDialCode({required this.flag, required this.prefix});
}

const List<_CountryDialCode> _countryDialCodes = [
  _CountryDialCode(flag: '🇮🇱', prefix: '+972'),
  _CountryDialCode(flag: '🇵🇸', prefix: '+970'),
  _CountryDialCode(flag: '🇯🇴', prefix: '+962'),
  _CountryDialCode(flag: '🇪🇬', prefix: '+20'),
  _CountryDialCode(flag: '🇸🇦', prefix: '+966'),
  _CountryDialCode(flag: '🇦🇪', prefix: '+971'),
  _CountryDialCode(flag: '🇺🇸', prefix: '+1'),
];

class _PrimaryAuthButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryAuthButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 227,
        height: 48,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColorEE6C4D,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
              : Text(label),
        ),
      ),
    );
  }
}

class _SwitchAuthMode extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onPressed;

  const _SwitchAuthMode({
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: const TextStyle(fontSize: 14)),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MerzoxColors.kColorEE6C4D,
            ),
          ),
        ),
      ],
    );
  }
}
