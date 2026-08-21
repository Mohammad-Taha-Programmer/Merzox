import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/colors.dart';
import 'auth_session_service.dart';

class AuthActionGuard {
  final AuthSessionService _sessionService;

  const AuthActionGuard({
    AuthSessionService sessionService = const AuthSessionService(),
  }) : _sessionService = sessionService;

  Future<bool> isAuthenticated() async {
    final session = await _sessionService.read();
    return session.isAuthenticated;
  }

  Future<bool> run(FutureOr<void> Function() action) async {
    if (!await isAuthenticated()) {
      return false;
    }

    await action();
    return true;
  }
}

final class AuthGate {
  const AuthGate._();

  static Future<bool> run(
    BuildContext context, {
    required FutureOr<void> Function() onAuthenticated,
    AuthSessionService sessionService = const AuthSessionService(),
  }) async {
    final guard = AuthActionGuard(sessionService: sessionService);
    var actionExecuted = false;
    final authenticated = await guard.run(() async {
      if (!context.mounted) {
        return;
      }
      actionExecuted = true;
      await onAuthenticated();
    });

    if (authenticated) {
      return actionExecuted;
    }

    if (!context.mounted) {
      return false;
    }

    final route = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: MerzoxColors.kColor3D5A80),
            const SizedBox(width: 10),
            Expanded(child: Text('authGate.title'.tr())),
          ],
        ),
        content: Text('authGate.message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('authGate.cancel'.tr()),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('/signup'),
            child: Text('authGate.signup'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('/login'),
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
            ),
            child: Text('authGate.login'.tr()),
          ),
        ],
      ),
    );

    if (route != null && context.mounted) {
      unawaited(context.push<void>(route));
    }

    return false;
  }
}
