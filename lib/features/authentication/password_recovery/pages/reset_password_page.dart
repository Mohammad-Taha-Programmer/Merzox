import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (utf8.encode(password).length > 72) {
      return 'كلمة المرور طويلة جداً';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<PasswordRecoveryBloc, PasswordRecoveryState>(
        listener: (context, state) {
          if (state.status == PasswordRecoveryStatus.resetSucceeded) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
            );
            widget.onResetSucceeded();
            return;
          }

          if (state.status == PasswordRecoveryStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
        },
        builder: (context, state) {
          final isLoading = state.status == PasswordRecoveryStatus.loading;

          return Scaffold(
            appBar: AppBar(
              title: const Text('تعيين كلمة مرور جديدة'),
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
                      const Text(
                        'إذا كان البريد الإلكتروني مرتبطاً بحساب مؤهل، '
                        'ستصلك رسالة تحتوي على رمز استعادة صالح لمدة محدودة.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _tokenController,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'رمز الاستعادة',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final token = value?.trim() ?? '';

                          if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
                            return 'رمز الاستعادة غير صالح';
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
                          labelText: 'كلمة المرور الجديدة',
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
                          labelText: 'تأكيد كلمة المرور',
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
                            return 'كلمتا المرور غير متطابقتين';
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
                            : const Text('تغيير كلمة المرور'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : widget.onBackToLogin,
                        child: const Text('العودة إلى تسجيل الدخول'),
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
