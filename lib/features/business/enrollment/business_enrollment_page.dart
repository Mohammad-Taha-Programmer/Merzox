import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../../../core/constants/colors.dart';
import 'business_enrollment_bloc.dart';

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

  String get _normalizedPhone {
    final raw = _phone.text.trim();
    if (raw.startsWith('+')) return raw;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('972')) return '+$digits';
    final local = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+972$local';
  }

  String? _phoneValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'validation.required'.tr();
    final normalized = raw.startsWith('+') ? raw : _normalizedPhone;
    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)
        ? null
        : 'validation.invalidPhone'.tr();
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'validation.required'.tr();
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

  String? _urlValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'validation.required'.tr();
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
            leading: state.step == 1
                ? IconButton(
                    onPressed: () => context.read<BusinessEnrollmentBloc>().add(
                      const BusinessEnrollmentBackPressed(),
                    ),
                    icon: const Icon(Icons.arrow_forward_ios_rounded),
                  )
                : null,
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
          _stepIcon(Icons.person_outline_rounded, selected == 0),
          const SizedBox(width: 18),
          _stepIcon(Icons.storefront_outlined, selected == 1),
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
          keyboardType: TextInputType.phone,
          validator: _phoneValidator,
          hintText: '+972 59 000 0000',
        ),
        _field(
          _email,
          'businessEnrollment.emailLabel'.tr(),
          keyboardType: TextInputType.emailAddress,
          validator: _emailValidator,
        ),
        _field(
          _password,
          'businessEnrollment.currentPasswordLabel'.tr(),
          obscure: true,
          validator: _passwordValidator,
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
            _field(_englishName, 'businessEnrollment.storeEnglishName'.tr()),
            _field(
              _description,
              'businessEnrollment.storeDescription'.tr(),
              maxLines: 3,
            ),
            _field(_category, 'businessEnrollment.productCategory'.tr()),
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
