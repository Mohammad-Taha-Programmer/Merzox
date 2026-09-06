import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';

/// How many conversations are waiting on the reader.
///
/// The messages icon said nothing at all: a merchant with four people waiting
/// and a merchant with none saw the same outline, so the only way to find out
/// was to open the screen and look. The count is what makes the icon worth
/// glancing at.
final class MessageBadgeState {
  final int unreadCount;

  const MessageBadgeState({this.unreadCount = 0});

  bool get hasUnread => unreadCount > 0;

  MessageBadgeState copyWith({int? unreadCount}) =>
      MessageBadgeState(unreadCount: unreadCount ?? this.unreadCount);
}

sealed class MessageBadgeEvent {
  const MessageBadgeEvent();
}

final class MessageBadgeStarted extends MessageBadgeEvent {
  const MessageBadgeStarted();
}

/// The socket said a conversation changed. What it did not say is how many are
/// unread now, so the count is re-read rather than adjusted.
final class MessageBadgeSyncRequested extends MessageBadgeEvent {
  const MessageBadgeSyncRequested();
}

class MessageBadgeBloc extends Bloc<MessageBadgeEvent, MessageBadgeState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// Whether this counts the shop's conversations or the reader's own.
  final bool businessAudience;

  StreamSubscription<RealtimeMessageInvalidation>? _messages;
  StreamSubscription<RealtimeConnectionStatus>? _connections;

  Timer? _debounce;
  bool _inFlight = false;
  bool _pending = false;
  bool _wasDisconnected = false;

  MessageBadgeBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeMessageInvalidation>? realtimeMessageInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const MessageBadgeState()) {
    on<MessageBadgeStarted>(
      (_, Emitter<MessageBadgeState> emit) => _refresh(emit),
    );
    on<MessageBadgeSyncRequested>((_, Emitter<MessageBadgeState> emit) async {
      if (_inFlight) {
        _pending = true;
        return;
      }
      await _refresh(emit);
    });

    _bindRealtime(realtimeMessageInvalidations, realtimeConnectionStatuses);
  }

  void _bindRealtime(
    Stream<RealtimeMessageInvalidation>? messages,
    Stream<RealtimeConnectionStatus>? connections,
  ) {
    // Every message event matters here: unlike notifications, the socket does
    // not tell the two audiences apart, and a conversation this reader is not
    // part of will simply not change their count.
    _messages = messages?.listen(
      (RealtimeMessageInvalidation _) => _schedule(),
    );

    if (connections == null) return;

    // Assumed disconnected until told otherwise, so the first connection
    // counts as a reconnection and re-reads a count that went stale offline.
    _wasDisconnected = true;

    _connections = connections.listen((RealtimeConnectionStatus status) {
      if (status == RealtimeConnectionStatus.disconnected) {
        _wasDisconnected = true;
        return;
      }

      if (status == RealtimeConnectionStatus.connected && _wasDisconnected) {
        _wasDisconnected = false;
        _schedule();
      }
    });
  }

  /// A burst of messages in one conversation is one refresh, not five.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), () {
      if (!isClosed) add(const MessageBadgeSyncRequested());
    });
  }

  Future<void> _refresh(Emitter<MessageBadgeState> emit) async {
    if (_inFlight) {
      _pending = true;
      return;
    }

    _inFlight = true;
    try {
      final int unread = await _apiService.messageUnreadCount(
        token: await _token(),
        businessAudience: businessAudience,
      );

      emit(state.copyWith(unreadCount: unread));
    } catch (_) {
      // A refresh that failed is not evidence that nothing is waiting. The
      // last proven count stands until the next event or reconnection.
    } finally {
      _inFlight = false;

      if (_pending && !isClosed) {
        _pending = false;
        _schedule();
      }
    }
  }

  Future<String> _token() async {
    final AuthSessionSnapshot session = await _authSessionService.read();
    final String? token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    // A customer session must never be able to read a shop's conversations,
    // even by asking for the business audience.
    if (businessAudience && !session.isBusiness) {
      throw StateError('A business account is required');
    }

    return token;
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _messages?.cancel();
    await _connections?.cancel();
    await super.close();
  }
}
