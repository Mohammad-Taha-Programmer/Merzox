import 'dart:convert';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/password_recovery_bloc.dart';
import '../bloc/password_recovery_event.dart';
import '../bloc/password_recovery_state.dart';

class ResetPasswordPage extends StatefulWidget {
  final VoidCallback onResetSucceeded;
  final VoidCallback onBackToLogin;

  const ResetPasswordPage({
    super.key,
    required this.onResetSucceeded,
    required this.onBackToLogin,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    context.read<PasswordRecoveryBloc>().add(
      ResetPasswordSubmitted(
        token: _tokenController.text.trim(),
        newPassword: _passwordController.text,
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.length < 6) {
      return 'validation.passwordMin6'.tr();
    }

    if (utf8.encode(password).length > 72) {
      return 'passwordRecovery.passwordTooLong'.tr();
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: BlocConsumer<PasswordRecoveryBloc, PasswordRecoveryState>(
        listener: (context, state) {
          if (state.status == PasswordRecoveryStatus.resetSucceeded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('passwordRecovery.resetSuccess'.tr())),
            );
            widget.onResetSucceeded();
            return;
          }

          if (state.status == PasswordRecoveryStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizeApiErrorOrRaw(state.errorMessage!)),
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state.status == PasswordRecoveryStatus.loading;

          return Scaffold(
            appBar: AppBar(
              title: Text('passwordRecovery.newPasswordTitle'.tr()),
              centerTitle: true,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'passwordRecovery.resetDescription'.tr(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _tokenController,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'passwordRecovery.tokenLabel'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final token = value?.trim() ?? '';

                          if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
                            return 'passwordRecovery.invalidToken'.tr();
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !isLoading,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'passwordRecovery.newPasswordLabel'.tr(),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _confirmationController,
                        enabled: !isLoading,
                        obscureText: _obscureConfirmation,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'passwordRecovery.confirmPasswordLabel'
                              .tr(),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmation = !_obscureConfirmation;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmation
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'passwordRecovery.passwordMismatch'.tr();
                          }

                          return _validatePassword(value);
                        },
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: isLoading ? null : _submit,
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('passwordRecovery.changePassword'.tr()),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : widget.onBackToLogin,
                        child: Text('passwordRecovery.backToLogin'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
