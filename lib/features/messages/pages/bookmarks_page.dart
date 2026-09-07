import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/dates.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/services/api_service.dart';

/// The messages this reader marked to come back to.
///
/// One list across every thread, because that is how they will be looked for:
/// a reader remembers what was said, not which conversation it was said in.
/// Opening one goes to its thread and stops at that message, by the same
/// route a search result takes.
class BookmarksPage extends StatefulWidget {
  /// Injected by tests, which have no server.
  final ApiService? apiService;
  final AuthSessionService authSessionService;

  const BookmarksPage({
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    super.key,
  });

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  late final ApiService _api = widget.apiService ?? ApiService();

  List<BookmarkApiModel>? _bookmarks;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');

    try {
      final AuthSessionSnapshot session = await widget.authSessionService
          .read();
      final String? token = session.token;
      if (token == null) throw StateError('Authentication required');

      final BookmarkListApiResponse response = await _api.bookmarks(
        token: token,
      );

      if (!mounted) return;
      setState(() => _bookmarks = response.bookmarks);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bookmarks = const <BookmarkApiModel>[];
        _error = localizeApiErrorOrRaw(ApiService.messageFromError(error));
      });
    }
  }

  /// Opens the thread and stops at the marked message.
  ///
  /// The same query the search results use: the thread pages back until the
  /// message is loaded rather than landing at the bottom and leaving the
  /// reader to scroll for what they marked.
  Future<void> _open(BookmarkApiModel bookmark) async {
    await context.push(
      Uri(
        path: '/chat',
        queryParameters: <String, String>{
          'conversationId': bookmark.conversation.id,
          'title': bookmark.conversation.title,
          'avatarUrl': bookmark.conversation.avatarUrl,
          'matches': bookmark.message.id,
        },
      ).toString(),
    );

    if (!mounted) return;
    // A mark may have been taken off while the thread was open.
    await _load();
  }

  /// Takes the mark off, from the list of marks.
  ///
  /// The row goes only once the server has agreed. Dropping it first and
  /// putting it back on failure would make a list of things the reader saved
  /// flicker, which is the one place that should feel dependable.
  Future<void> _remove(BookmarkApiModel bookmark) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final AuthSessionSnapshot session = await widget.authSessionService
          .read();
      final String? token = session.token;
      if (token == null) throw StateError('Authentication required');

      await _api.setMessageBookmark(
        token: token,
        conversationId: bookmark.conversation.id,
        messageId: bookmark.message.id,
        bookmarked: false,
      );

      if (!mounted) return;
      setState(() {
        _bookmarks = <BookmarkApiModel>[
          for (final BookmarkApiModel row in _bookmarks ?? const [])
            if (row.message.id != bookmark.message.id) row,
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
        // The board's thin chevron rather than Material's full arrow, named
        // for what it does so Material turns it for the reading: it leans
        // right in Arabic and left in English.
        leading: IconButton(
          key: const ValueKey<String>('bookmarks.back'),
          tooltip: 'common.back'.tr(),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: MerzoxColors.kColor5E5E5E,
            size: 28,
          ),
        ),
        title: Text(
          'messages.bookmarksTitle'.tr(),
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
    final List<BookmarkApiModel>? bookmarks = _bookmarks;

    if (bookmarks == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _Notice(text: _error, onRetry: _load);
    }

    if (bookmarks.isEmpty) {
      return _Notice(text: 'messages.bookmarksEmpty'.tr());
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final BookmarkApiModel bookmark = bookmarks[index];

        return _BookmarkRow(
          bookmark: bookmark,
          onTap: () => _open(bookmark),
          onRemove: () => _remove(bookmark),
        );
      },
    );
  }
}

/// One marked message: which thread it was said in, and what it said.
class _BookmarkRow extends StatelessWidget {
  final BookmarkApiModel bookmark;
  final VoidCallback onTap;

  /// Takes the mark off. At the far end of the row, away from the words, so
  /// reaching for the message does not reach for this.
  final VoidCallback onRemove;

  const _BookmarkRow({
    required this.bookmark,
    required this.onTap,
    required this.onRemove,
  });

  /// What the row shows of the message.
  ///
  /// A shared card has no words of its own, so the product's name stands in;
  /// a blank row would give the reader nothing to recognise.
  String get _preview {
    final String body = bookmark.message.body.trim();
    if (body.isNotEmpty) return body;

    final String product = bookmark.message.sharedProduct?.name ?? '';
    return product.isNotEmpty ? product : 'messages.quotedProduct'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MerzoxColors.kColorF9F9F9,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey<String>('bookmark.${bookmark.message.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.bookmark_rounded,
                size: 18,
                color: MerzoxColors.kColor98C1D9,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      bookmark.conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: MerzoxColors.kColor3B3B3B,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (bookmark.message.createdAt != null)
                    Text(
                      merzoxDay(bookmark.message.createdAt!),
                      style: const TextStyle(
                        fontSize: 10,
                        color: MerzoxColors.kColor8D99AE,
                      ),
                    ),
                  IconButton(
                    key: ValueKey<String>(
                      'bookmark.remove.${bookmark.message.id}',
                    ),
                    tooltip: 'messages.actionUnbookmark'.tr(),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
