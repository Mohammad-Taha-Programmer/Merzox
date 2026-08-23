import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/password_recovery_bloc.dart';
import '../bloc/password_recovery_event.dart';
import '../bloc/password_recovery_state.dart';

class ForgotPasswordPage extends StatefulWidget {
  final VoidCallback onRequestAccepted;
  final VoidCallback onBackToLogin;

  const ForgotPasswordPage({
    super.key,
    required this.onRequestAccepted,
    required this.onBackToLogin,
  });

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    context.read<PasswordRecoveryBloc>().add(
      ForgotPasswordSubmitted(email: _emailController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<PasswordRecoveryBloc, PasswordRecoveryState>(
        listener: (context, state) {
          if (state.status == PasswordRecoveryStatus.requestAccepted) {
            widget.onRequestAccepted();
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
              title: const Text('استعادة كلمة المرور'),
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
                      const SizedBox(height: 24),
                      const Icon(Icons.lock_reset_outlined, size: 72),
                      const SizedBox(height: 24),
                      const Text(
                        'نسيت كلمة المرور؟',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'أدخل البريد الإلكتروني المرتبط بحسابك. '
                        'إذا كان الحساب مؤهلاً للاستعادة فسنرسل إليه رمزاً مؤقتاً.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        enabled: !isLoading,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          hintText: 'name@example.com',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';

                          if (email.isEmpty) {
                            return 'البريد الإلكتروني مطلوب';
                          }

                          if (email.length > 254 ||
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(email)) {
                            return 'أدخل بريداً إلكترونياً صحيحاً';
                          }

                          return null;
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
                            : const Text('إرسال تعليمات الاستعادة'),
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
