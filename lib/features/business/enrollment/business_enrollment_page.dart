import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/widgets/merzox_back_chevron.dart';
import '../../../core/widgets/merzox_icons.dart';
import '../../../core/widgets/merzox_notched_nav_bar.dart';
import '../../../core/auth/sign_in_identifier.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../../authentication/widgets/dial_code_selector.dart';
import 'business_enrollment_bloc.dart';
import 'package:merzox/core/widgets/merzox_keyboards.dart';

/// The box every field on this screen sits in.
///
/// Measured rather than chosen: these are ordinary Material fields with a
/// floating label and they settle at 56. It is named because the line that
/// divides the country from the number has to run the whole of it, and a test
/// holds the two together.
const double _kFieldHeight = 56;

class BusinessEnrollmentPage extends StatefulWidget {
  final VoidCallback onCompleted;

  const BusinessEnrollmentPage({super.key, required this.onCompleted});

  @override
  State<BusinessEnrollmentPage> createState() => _BusinessEnrollmentPageState();
}

class _BusinessEnrollmentPageState extends State<BusinessEnrollmentPage> {
  final _firstKey = GlobalKey<FormState>();
  final _secondKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _englishName = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _address = TextEditingController();
  final _attachment = TextEditingController();

  DialCode _selectedCountry = defaultDialCode;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _fillPhoneFromAccount();
  }

  /// The number the reader already signs in with, put in the field for them.
  ///
  /// A guess, and a safe one: somebody opening a shop on their own account is
  /// almost always reachable on the number that account already carries, and
  /// the server refuses a number belonging to anybody else anyway. It is a
  /// starting value and nothing more - the field is ordinary, and clearing it
  /// and typing another number is the whole of changing the guess.
  ///
  /// Read from the copy the app already keeps rather than asked of the server:
  /// the account's own number is not worth a round trip, and a field that
  /// fills in a moment late has already been typed into.
  Future<void> _fillPhoneFromAccount() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String stored = prefs.getString(AuthBloc.phoneKey)?.trim() ?? '';

    // Never over the reader. They may have started typing while this was in
    // flight, and their own typing outranks a guess.
    if (!mounted || stored.isEmpty || _phone.text.isNotEmpty) return;

    _phone.text = stored;
  }

  @override
  void dispose() {
    for (final controller in [
      _phone,
      _email,
      _password,
      _name,
      _englishName,
      _description,
      _category,
      _address,
      _attachment,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'validation.required'.tr() : null;

  /// Anything, including nothing.
  String? _optional(String? value) => null;

  /// The number as the server stores it, from whichever spelling was typed.
  ///
  /// This screen had its own copy of the arithmetic, and the copy had a
  /// country written into it: anything that was not already international got
  /// `+972` in front of it whatever the reader meant. The rule lives in one
  /// place now, and the country comes from the flag beside the field.
  String get _normalizedPhone => internationalPhoneNumber(
    _phone.text,
    dialPrefix: _selectedCountry.prefix,
  );

  String? _phoneValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'validation.required'.tr();
    // Judged on what will be sent, not on what was typed: a local number is
    // seven digits and a refusal of it would be a refusal of the normal case.
    final String normalized = internationalPhoneNumber(
      raw,
      dialPrefix: _selectedCountry.prefix,
    );
    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)
        ? null
        : 'validation.invalidPhone'.tr();
  }

  /// An address is welcome here and not required.
  ///
  /// Opening a shop needs a way to reach the merchant, and the number above is
  /// one. An address can be added later from the shop's own settings, so
  /// demanding it at this step stops somebody who has one shop and no work
  /// email from getting started at all.
  ///
  /// Empty passes. Anything else still has to be an address: a half-typed one
  /// is a mistake, not an omission.
  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? null
        : 'validation.invalidEmail'.tr();
  }

  String? _passwordValidator(String? value) {
    if ((value ?? '').length < 6) {
      return 'validation.passwordMin6'.tr();
    }
    return null;
  }

  /// A link to the register is welcome here and not required.
  ///
  /// Empty passes. Anything else still has to be a link a browser could open:
  /// a half-typed one helps nobody and cannot be told from a typo later.
  String? _urlValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? null
        : 'businessEnrollment.invalidAttachmentUrl'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: BlocConsumer<BusinessEnrollmentBloc, BusinessEnrollmentState>(
        listener: (context, state) {
          if (state.status == BusinessEnrollmentStatus.success) {
            widget.onCompleted();
          } else if (state.status == BusinessEnrollmentStatus.failure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.errorMessage == null
                      ? 'businessEnrollment.createFailed'.tr()
                      : localizeApiErrorOrRaw(state.errorMessage!),
                ),
              ),
            );
          }
        },
        builder: (context, state) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text('businessEnrollment.title'.tr()),
            // A null `leading` does not mean "no way back": `AppBar` fills
            // it in itself when the route can be popped, and what it fills it
            // in with is Material's own back button. The chevron here was put
            // on the second step only, so the first - the step a reader lands
            // on - kept Material's arrow, and the screen drew two different
            // marks for one thing.
            //
            // The fix is the `leading` below, which is now given on both
            // steps; this line is the fence behind it, for the day somebody
            // makes it conditional again.
            automaticallyImplyLeading: false,
            // What it means differs - the second step goes back a step, the
            // first leaves the screen - and the mark does not.
            leading: Center(
              child: MerzoxBackChevronButton(
                valueKey: const ValueKey<String>('businessEnrollment.back'),
                semanticsLabel: 'common.back'.tr(),
                onTap: () {
                  if (state.step == 1) {
                    context.read<BusinessEnrollmentBloc>().add(
                      const BusinessEnrollmentBackPressed(),
                    );
                    return;
                  }

                  Navigator.of(context).maybePop();
                },
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: state.step == 0
                  ? _firstStep(context)
                  : _secondStep(context, state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int selected) => Column(
    children: [
      Image.asset('assets/images/MERZOX_LOGO.png', height: 78),
      const SizedBox(height: 18),
      Text('businessEnrollment.subtitle'.tr()),
      const SizedBox(height: 18),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepIcon(MerzoxIcons.businessEnrollmentAccountStep, selected == 0),
          const SizedBox(width: 18),
          _stepIcon(MerzoxIcons.businessEnrollmentStoreStep, selected == 1),
        ],
      ),
      const SizedBox(height: 28),
    ],
  );

  Widget _stepIcon(IconData icon, bool selected) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: selected ? MerzoxColors.kColor3D5A80 : Colors.white,
      border: Border.all(color: MerzoxColors.kColor98C1D9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(
      icon,
      // The size the bar's own places draw these at. Their ink fills the em
      // box, so the number is the mark's height as well as its font size.
      size: kMerzoxNavItemGlyphSize,
      color: selected ? Colors.white : MerzoxColors.kColor8D99AE,
    ),
  );

  Widget _firstStep(BuildContext context) => Form(
    key: _firstKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(0),
        _field(
          _phone,
          'businessEnrollment.phoneLabel'.tr(),
          keyboardType: kMerzoxPhoneKeyboard,
          validator: _phoneValidator,
          // Was `+972 59 000 0000`. A worked example naming one country, in a
          // field that now carries a flag list, tells the reader the opposite
          // of what the list does.
          hintText: 'businessEnrollment.phoneHint'.tr(),
          // The same block the other two screens draw, in this screen's own
          // box: its height, and its border colour, which here is the theme's
          // own outline rather than a colour of the screen's choosing.
          suffix: DialCodeSelector(
            key: const Key('businessEnrollment.countryCode'),
            lineKey: const Key('businessEnrollment.countryDivider'),
            fieldHeight: _kFieldHeight,
            lineColor: Theme.of(context).colorScheme.outline,
            value: _selectedCountry,
            onChanged: (DialCode? country) {
              if (country == null) return;
              setState(() => _selectedCountry = country);
            },
          ),
          suffixConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: _kFieldHeight,
            maxHeight: _kFieldHeight,
          ),
        ),
        _field(
          _email,
          'businessEnrollment.emailLabel'.tr(),
          keyboardType: kMerzoxEmailKeyboard,
          validator: _emailValidator,
        ),
        _field(
          _password,
          'businessEnrollment.currentPasswordLabel'.tr(),
          obscure: _obscurePassword,
          validator: _passwordValidator,
          // Hidden, so the eye offered is the one that reveals it.
          suffix: IconButton(
            key: const ValueKey<String>('businessEnrollment.revealPassword'),
            tooltip: _obscurePassword
                ? 'auth.showPassword'.tr()
                : 'auth.hidePassword'.tr(),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? MerzoxIcons.businessEnrollmentShowPassword
                  : MerzoxIcons.businessEnrollmentHidePassword,
              color: MerzoxColors.kColor98C1D9,
              // The size it drew at as a Material eye, converted.
              size: 24 * MerzoxIcons.passwordEyeSizeFactor,
            ),
          ),
        ),
        const SizedBox(height: 22),
        _button('businessEnrollment.next'.tr(), () {
          if (_firstKey.currentState?.validate() != true) return;
          context.read<BusinessEnrollmentBloc>().add(
            BusinessEnrollmentFirstStepSaved(
              phone: _normalizedPhone,
              email: _email.text,
              password: _password.text,
            ),
          );
        }),
      ],
    ),
  );

  Widget _secondStep(BuildContext context, BusinessEnrollmentState state) =>
      Form(
        key: _secondKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(1),
            _field(_name, 'business.storeName'.tr()),
            // Optional, and not policed for language either. Most shops here
            // trade under one name; the field is a second name for the ones
            // that have one, and a shop with a single Arabic name should not
            // be made to invent an English one - nor stopped from writing the
            // Arabic one again if that is what it wants on the label.
            _field(
              _englishName,
              'businessEnrollment.storeEnglishName'.tr(),
              validator: _optional,
            ),
            _field(
              _description,
              'businessEnrollment.storeDescription'.tr(),
              maxLines: 3,
            ),
            // Optional for now. It is how a customer comes across the shop -
            // the catalogue and the search both match on it, and it is one of
            // the four fields in the text index - rather than something the
            // shop cannot exist without, and every screen that draws it checks
            // first whether it is there.
            _field(
              _category,
              'businessEnrollment.productCategory'.tr(),
              validator: _optional,
            ),
            _field(_address, 'businessEnrollment.storeAddress'.tr()),
            _field(
              _attachment,
              'business.attachmentUrl'.tr(),
              keyboardType: TextInputType.url,
              validator: _urlValidator,
              hintText: 'https://example.com/document.pdf',
            ),
            const SizedBox(height: 22),
            _button(
              'auth.createAccountButton'.tr(),
              state.status == BusinessEnrollmentStatus.submitting
                  ? null
                  : () {
                      if (_secondKey.currentState?.validate() != true) return;
                      context.read<BusinessEnrollmentBloc>().add(
                        BusinessEnrollmentSubmitted(
                          name: _name.text,
                          englishName: _englishName.text,
                          description: _description.text,
                          category: _category.text,
                          address: _address.text,
                          attachmentUrl: _attachment.text,
                        ),
                      );
                    },
              loading: state.status == BusinessEnrollmentStatus.submitting,
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? hintText,
    Widget? suffix,
    BoxConstraints? suffixConstraints,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator ?? _required,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        suffixIcon: suffix,
        suffixIconConstraints: suffixConstraints,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
  );

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool loading = false,
  }) => SizedBox(
    height: 50,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: MerzoxColors.kColorEE6C4D),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );
}
