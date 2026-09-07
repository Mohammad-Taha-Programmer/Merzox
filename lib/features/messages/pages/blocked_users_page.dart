import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/services/api_service.dart';

/// Everyone this reader has closed the door on.
///
/// Blocking happens inside a conversation, where the other side is known
/// without being named. Undoing it needs a place of its own: a thread the
/// reader no longer wants to open is a poor way back to a decision they may
/// want to reverse.
class BlockedUsersPage extends StatefulWidget {
  /// Injected by tests, which have no server.
  final ApiService? apiService;
  final AuthSessionService authSessionService;

  const BlockedUsersPage({
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    super.key,
  });

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  late final ApiService _api = widget.apiService ?? ApiService();

  List<BlockedUserApiModel>? _blocks;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _token() async {
    final AuthSessionSnapshot session = await widget.authSessionService.read();
    final String? token = session.token;
    if (token == null) throw StateError('Authentication required');

    return token;
  }

  Future<void> _load() async {
    setState(() => _error = '');

    try {
      final BlockedUserListApiResponse response = await _api.blockedUsers(
        token: await _token(),
      );

      if (!mounted) return;
      setState(() => _blocks = response.blocks);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _blocks = const <BlockedUserApiModel>[];
        _error = localizeApiErrorOrRaw(ApiService.messageFromError(error));
      });
    }
  }

  /// Opens the door again.
  ///
  /// The row goes once the server has agreed, not before: this is a list of
  /// decisions, and one that reappeared after seeming to go would leave the
  /// reader unsure which way it had settled.
  Future<void> _unblock(BlockedUserApiModel block) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await _api.unblockUser(token: await _token(), userId: block.userId);

      if (!mounted) return;
      setState(() {
        _blocks = <BlockedUserApiModel>[
          for (final BlockedUserApiModel row in _blocks ?? const [])
            if (row.userId != block.userId) row,
        ];
      });
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              localizeApiErrorOrRaw(ApiService.messageFromError(error)),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          key: const ValueKey<String>('blockedUsers.back'),
          tooltip: 'common.back'.tr(),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: MerzoxColors.kColor5E5E5E,
            size: 28,
          ),
        ),
        title: Text(
          'messages.blockedUsersTitle'.tr(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final List<BlockedUserApiModel>? blocks = _blocks;

    if (blocks == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _Notice(text: _error, onRetry: _load);
    }

    if (blocks.isEmpty) {
      return _Notice(text: 'messages.blockedUsersEmpty'.tr());
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final BlockedUserApiModel block = blocks[index];

        return _BlockedRow(block: block, onUnblock: () => _unblock(block));
      },
    );
  }
}

class _BlockedRow extends StatelessWidget {
  final BlockedUserApiModel block;
  final VoidCallback onUnblock;

  const _BlockedRow({required this.block, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>('blockedUser.${block.userId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          RemoteCircleAvatar(
            url: block.avatarUrl,
            radius: 18,
            backgroundColor: MerzoxColors.kColorDEEEF8,
            fallback: const Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: MerzoxColors.kColor3D5A80,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              block.name.trim().isEmpty
                  ? 'messages.quotedFallbackName'.tr()
                  : block.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: ValueKey<String>('blockedUser.unblock.${block.userId}'),
            onPressed: onUnblock,
            style: OutlinedButton.styleFrom(
              foregroundColor: MerzoxColors.kColor3D5A80,
              side: const BorderSide(color: MerzoxColors.kColor98C1D9),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
            ),
            child: Text(
              'messages.unblockUser'.tr(),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Notice({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColor8D99AE,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text('common.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
