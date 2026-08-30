import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

// MERZOX-UI-GOLDEN-I5-I1-R1 - customer login SCREEN-SPACE geometry.
//
// The comparator matches the FULL 375x812 XD PNG against the FULL 375x812
// Flutter golden, so the authoritative coordinates here are XD SCREEN-space,
// not XD app-space. The two differ by the artboard's status chrome:
//
//   SCREEN_Y = APP_Y + 44
//
// The previous revision of this file consumed app-space Y values directly and
// therefore drew the whole page ~44px too high. Every constant below is now a
// slot height or a gap in SCREEN space.
//
// Top-bar policy: XD spends screen y=0..44 on status chrome and y=44..88 on its
// own app bar. Merzox draws neither. Its real application top bar stays at
// y=0..44 and the 44..88 band is left as plain white - that mismatch against
// XD's OS chrome is accepted, and the correction concerns the content below it.
//
// The three rects the reference pins land exactly:
//
//   identifier field  16,320 .. 359,368   (343x48)
//   password field    16,412 .. 359,460   (343x48)
//   login button      74,547 .. 301,595   (227x48)
//
// The text slots are FIXED heights with their content centred, so the rects
// above are a property of this layout rather than of whatever line height the
// active font reports. The lower region is pinned the same way: the signup row
// sits at a fixed offset from the top so it lands on XD's y=763 screen baseline,
// and the single trailing `Spacer` absorbs the surplus on a tall viewport and
// collapses - leaving the page scrollable - on a short one.

/// Height of the real application top bar (screen y=0..44).
const double _kTopBarHeight = 44;

/// Top bar bottom (44) -> logo top (100).
///
/// This gap spans XD's own app-bar band (44..88); Merzox leaves it white rather
/// than recreating chrome it does not own.
const double _kTopBarToLogo = 56;

/// The brand mark. The asset keeps its current size; only the surrounding
/// spacing is tuned, so the normalized "Merzox" wordmark under it centres on
/// XD's screen baseline y=154.
const double _kLogoHeight = 36;
const double _kLogoToBrandText = 2;
const double _kBrandTextSlotHeight = 24;

/// Brand block bottom (162) -> title slot top (210), title baseline y=226.
const double _kBrandToTitle = 48;
const double _kTitleSlotHeight = 24;

/// Title slot bottom (234) -> subtitle slot top (249), subtitle baseline y=262.
const double _kTitleToSubtitle = 15;
const double _kSubtitleSlotHeight = 20;

/// Subtitle slot bottom (269) -> identifier label slot top (291).
const double _kSubtitleToForm = 22;

/// A field label slot; its baseline lands 15px above the field it describes
/// (identifier y=305/320, password y=397/412).
const double _kFieldLabelSlotHeight = 20;
const double _kFieldLabelToField = 9;

/// The exact XD field box. Locked - do not resize.
const double _kFieldHeight = 48;
const double _kFieldRadius = 5;

/// Identifier field bottom (368) -> password label slot top (383).
const double _kFieldToNextLabel = 15;

/// Password field bottom (460) -> remember/forgot row top (465),
/// row text baseline y=483.
const double _kFieldToRememberRow = 5;
const double _kRememberRowHeight = 28;

/// Remember/forgot row bottom (493) -> login button top (547).
const double _kRememberRowToButton = 54;

/// The exact XD primary button box. Locked - do not resize.
const double _kPrimaryButtonWidth = 227;
const double _kPrimaryButtonHeight = 48;
const double _kPrimaryButtonRadius = 5;

/// Button bottom (595) -> secondary-action region top (619).
const double _kButtonToLowerRegion = 24;

/// The Merzox-only lower region (guest browsing, the courier entry point).
///
/// XD does not draw these, so they are given a FIXED band (619..721) with their
/// content centred in it. Fixing the band is what keeps the signup row on its
/// screen-space target whether or not the courier entry point is present.
const double _kSecondaryRegionHeight = 102;
const double _kSecondaryActionSlotHeight = 44;
const double _kLowerRegionGap = 12;

/// Secondary region bottom (721) -> signup row top (746),
/// signup baseline y=763.
const double _kLowerRegionToSignup = 25;
const double _kSignupRowHeight = 28;

/// Trailing whitespace only. XD's home-indicator chrome starts around y=778 and
/// Merzox does not draw a fake one.
const double _kPageBottomPadding = 24;

class LoginPage extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final VoidCallback onBrowseAsGuest;
  final VoidCallback onSignupRequested;
  final VoidCallback onForgotPasswordRequested;
  final VoidCallback? onCourierLocationRequested;
  final bool businessMode;

  const LoginPage({
    super.key,
    required this.onAuthenticated,
    required this.onBrowseAsGuest,
    required this.onSignupRequested,
    required this.onForgotPasswordRequested,
    this.onCourierLocationRequested,
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
        rememberMe: _rememberMe,
      ),
    );
  }

  /// The Arabic identifier label reads "رقم الجوال" for XD parity, but the
  /// field itself stays an identifier field: an entry containing '@' is sent
  /// verbatim as an email, an entry already carrying an international prefix is
  /// left alone, and anything else is normalized against the selected country
  /// dial code.
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
      textDirection: Directionality.of(context),
      child: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == AuthStatus.authenticated) {
            widget.onAuthenticated();
          }

          if (state.status == AuthStatus.failure) {
            final message =
                state.errorMessageKey?.tr() ??
                (state.errorMessage == null
                    ? null
                    : localizeApiErrorOrRaw(state.errorMessage!));

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

          // Merzox capabilities XD does not draw. Guest browsing is required,
          // so it stays visible and functional; both live in the fixed lower
          // band rather than displacing the signup row.
          final secondaryActions = <Widget>[
            if (widget.onCourierLocationRequested != null)
              SizedBox(
                height: _kSecondaryActionSlotHeight,
                child: OutlinedButton.icon(
                  onPressed: isLoading
                      ? null
                      : widget.onCourierLocationRequested,
                  icon: const Icon(Icons.delivery_dining_outlined, size: 18),
                  label: Text(
                    'courierLocation.loginEntry'.tr(),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            if (!widget.businessMode)
              SizedBox(
                height: _kSecondaryActionSlotHeight,
                child: TextButton(
                  onPressed: isLoading ? null : widget.onBrowseAsGuest,
                  child: Text(
                    'auth.continueAsGuest'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ];

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
                        // `IntrinsicHeight` is what lets a trailing flexible gap
                        // work inside a scroll view: it hands the column a tight
                        // height of max(content, viewport), so the `Spacer`
                        // takes the surplus on a tall viewport and collapses to
                        // zero - leaving the page scrollable rather than
                        // overflowing - on a short one. Every slot above it is
                        // fixed, so the screen-space pins hold either way.
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AuthTopBar(title: 'authGate.login'.tr()),
                              const SizedBox(height: _kTopBarToLogo),
                              const _AuthLogo(),
                              const SizedBox(height: _kBrandToTitle),
                              _AuthTitleBlock(
                                title: 'authGate.login'.tr(),
                                subtitle: 'auth.loginSubtitle'.tr(),
                              ),
                              const SizedBox(height: _kSubtitleToForm),
                              _XdField(
                                label: 'auth.loginIdentifierLabel'.tr(),
                                hint: 'auth.loginIdentifierHint'.tr(),
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
                                    return 'validation.required'.tr();
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: _kFieldToNextLabel),
                              _XdField(
                                label: 'auth.password'.tr(),
                                hint: 'auth.passwordHint'.tr(),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(bloc),
                                trailing: IconButton(
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
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: MerzoxColors.kColor98C1D9,
                                    size: 20,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'validation.required'.tr();
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: _kFieldToRememberRow),
                              SizedBox(
                                height: _kRememberRowHeight,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor: MerzoxColors.kColor3D5A80,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (value) {
                                          setState(() {
                                            _rememberMe = value ?? true;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'auth.rememberMe'.tr(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.0,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: isLoading
                                          ? null
                                          : widget.onForgotPasswordRequested,
                                      // Zero padding so the row's outer edges
                                      // line up with the two field boxes above.
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'auth.forgotPassword'.tr(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.0,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: _kRememberRowToButton),
                              _PrimaryAuthButton(
                                label: 'authGate.login'.tr(),
                                isLoading: isLoading,
                                onPressed: () => _submit(bloc),
                              ),
                              const SizedBox(height: _kButtonToLowerRegion),
                              // Fixed band: the Merzox-only actions centre
                              // inside it, so adding or dropping one of them
                              // never drags the signup row off its screen-space
                              // baseline.
                              SizedBox(
                                height: _kSecondaryRegionHeight,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      int i = 0;
                                      i < secondaryActions.length;
                                      i++
                                    ) ...[
                                      if (i > 0)
                                        const SizedBox(
                                          height: _kLowerRegionGap,
                                        ),
                                      secondaryActions[i],
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: _kLowerRegionToSignup),
                              if (!widget.businessMode)
                                _SwitchAuthMode(
                                  prompt: 'auth.noAccount'.tr(),
                                  action: 'auth.createAccountAction'.tr(),
                                  onPressed: widget.onSignupRequested,
                                ),
                              // Trailing surplus only: on the canonical 812
                              // surface everything above is already placed, and
                              // on a short viewport this collapses to zero so
                              // the page scrolls rather than overflowing.
                              const Spacer(),
                              const SizedBox(height: _kPageBottomPadding),
                            ],
                          ),
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
      height: _kTopBarHeight,
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
          height: _kLogoHeight,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: _kLogoToBrandText),
        const SizedBox(
          height: _kBrandTextSlotHeight,
          child: Center(
            // XD's legacy brand string is normalized to "Merzox"; the artboard
            // wordmark is never reproduced.
            child: Text(
              'Merzox',
              maxLines: 1,
              // `height: 1.0` pins the line box to the font size, so the slot
              // centres the wordmark on XD's screen baseline y=154 no matter
              // what ascent/descent the active font reports.
              style: TextStyle(
                fontFamily: 'Concept',
                fontSize: 16,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor293241,
              ),
            ),
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
        SizedBox(
          height: _kTitleSlotHeight,
          child: Center(
            child: Text(
              title,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
          ),
        ),
        const SizedBox(height: _kTitleToSubtitle),
        SizedBox(
          height: _kSubtitleSlotHeight,
          child: Center(
            child: Text(
              subtitle,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                fontWeight: FontWeight.w300,
                color: MerzoxColors.kColor3B3B3B,
              ),
            ),
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

  OutlineInputBorder _border(Color color, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFieldRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _kFieldLabelSlotHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 13,
                height: 1.0,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2B2B2B),
              ),
            ),
          ),
        ),
        const SizedBox(height: _kFieldLabelToField),
        SizedBox(
          height: _kFieldHeight,
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
                fontSize: 12,
                fontWeight: FontWeight.w300,
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
              border: _border(MerzoxColors.kColor98C1D9),
              enabledBorder: _border(MerzoxColors.kColor98C1D9),
              focusedBorder: _border(const Color(0xFF006CBF), width: 1.4),
              errorBorder: _border(errorColor),
              focusedErrorBorder: _border(errorColor, width: 1.4),
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2B2B2B),
          ),
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
        width: _kPrimaryButtonWidth,
        height: _kPrimaryButtonHeight,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColorEE6C4D,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_kPrimaryButtonRadius),
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
    return SizedBox(
      height: _kSignupRowHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prompt, style: const TextStyle(fontSize: 13, height: 1.0)),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              action,
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColorEE6C4D,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
