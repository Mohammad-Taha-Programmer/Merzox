import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_state.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/orders/bloc/order_tracking_bloc.dart';
import 'package:merzox/features/orders/bloc/order_tracking_event.dart';
import 'package:merzox/features/orders/bloc/order_tracking_state.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// Records every protected call it receives. The assertions below are about
/// this list staying EMPTY: a bloc that never reaches the network is the only
/// proof that the session check happened before the request, not after it.
class _SpyApi extends ApiService {
  final List<String> calls = [];

  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('conversations');
    return const ConversationListApiResponse(
      conversations: [],
      unreadConversationCount: 0,
      page: 1,
      hasMore: false,
    );
  }

  @override
  Future<ConversationListApiResponse> merchantConversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('merchantConversations');
    return const ConversationListApiResponse(
      conversations: [],
      unreadConversationCount: 0,
      page: 1,
      hasMore: false,
    );
  }

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    calls.add('conversationMessages');
    return ConversationMessagesApiResponse(
      conversation: ConversationApiModel.fromJson(const {'id': 'c1'}),
      messages: const [],
      page: 1,
      hasMore: false,
    );
  }

  @override
  Future<ConversationApiModel> openConversation({
    required String token,
    required String businessId,
  }) async {
    calls.add('openConversation');
    return ConversationApiModel.fromJson(const {'id': 'c1'});
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    calls.add('markConversationRead');
    return ConversationApiModel.fromJson(const {'id': 'c1'});
  }

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('notifications');
    return const NotificationListApiResponse(
      notifications: [],
      unreadCount: 0,
      page: 1,
      hasMore: false,
    );
  }

  @override
  Future<OrderApiModel> order({
    required String token,
    required String orderId,
  }) async {
    calls.add('order');
    return OrderApiModel.fromJson(const {'id': 'o1', 'status': 'pending'});
  }

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async {
    calls.add('ownerBusiness');
    return OwnerBusiness.fromJson(const {'id': 'b1', 'name': 'Store'});
  }

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async {
    calls.add('businessDashboard');
    return BusinessDashboardData.fromJson(const {});
  }

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String? statusGroup,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('ownerOrders');
    return OwnerOrderList.fromJson(const {});
  }

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async {
    calls.add('ownerProducts');
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Each subsystem is driven through the same three stored-session shapes.
  /// `start` kicks the bloc off, `settled` waits for it to stop moving, and
  /// `reachedApi` reports whether the network was touched.
  Future<void> runContract({
    required String label,
    required Future<bool> Function(_SpyApi api) attempt,
  }) async {
    useStaleTokenWithoutSession();
    final staleApi = _SpyApi();
    final staleReached = await attempt(staleApi);
    expect(
      staleApi.calls,
      isEmpty,
      reason: '$label: a logged-out token must not reach the API',
    );
    expect(
      staleReached,
      isFalse,
      reason: '$label: stale token must not succeed',
    );

    useBlankTokenSession();
    final blankApi = _SpyApi();
    final blankReached = await attempt(blankApi);
    expect(
      blankApi.calls,
      isEmpty,
      reason: '$label: a blank token must not reach the API',
    );
    expect(
      blankReached,
      isFalse,
      reason: '$label: blank token must not succeed',
    );

    useAuthenticatedSession(business: true);
    final liveApi = _SpyApi();
    final liveReached = await attempt(liveApi);
    expect(
      liveApi.calls,
      isNotEmpty,
      reason: '$label: a real session must reach the API',
    );
    expect(liveReached, isTrue, reason: '$label: real session must succeed');
  }

  test('MessagesBloc honours the centralized session contract', () async {
    await runContract(
      label: 'MessagesBloc',
      attempt: (api) async {
        final bloc = MessagesBloc(apiService: api);
        bloc.add(const MessagesStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == MessagesStatus.ready ||
              s.status == MessagesStatus.failure,
        );
        await bloc.close();
        return state.status == MessagesStatus.ready;
      },
    );
  });

  test('MessagesBloc merchant mode honours the contract', () async {
    await runContract(
      label: 'MessagesBloc(merchant)',
      attempt: (api) async {
        final bloc = MessagesBloc(apiService: api, merchantMode: true);
        bloc.add(const MessagesStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == MessagesStatus.ready ||
              s.status == MessagesStatus.failure,
        );
        await bloc.close();
        return state.status == MessagesStatus.ready;
      },
    );
  });

  test('ChatBloc honours the contract when loading a thread', () async {
    await runContract(
      label: 'ChatBloc',
      attempt: (api) async {
        final bloc = ChatBloc(apiService: api, conversationId: 'c1');
        bloc.add(const ChatStarted());
        final state = await bloc.stream.firstWhere(
          (s) => s.status == ChatStatus.ready || s.status == ChatStatus.failure,
        );
        await bloc.close();
        return state.status == ChatStatus.ready;
      },
    );
  });

  test('ChatBloc honours the contract when opening from a store', () async {
    await runContract(
      label: 'ChatBloc(open)',
      attempt: (api) async {
        final bloc = ChatBloc(apiService: api);
        bloc.add(const ChatOpenedForBusiness('b1'));
        final state = await bloc.stream.firstWhere(
          (s) => s.status == ChatStatus.ready || s.status == ChatStatus.failure,
        );
        await bloc.close();
        return state.status == ChatStatus.ready;
      },
    );
  });

  test('NotificationsBloc honours the centralized session contract', () async {
    await runContract(
      label: 'NotificationsBloc',
      attempt: (api) async {
        final bloc = NotificationsBloc(apiService: api);
        bloc.add(const NotificationsStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == NotificationsStatus.ready ||
              s.status == NotificationsStatus.failure,
        );
        await bloc.close();
        return state.status == NotificationsStatus.ready;
      },
    );
  });

  test('OrderTrackingBloc honours the centralized session contract', () async {
    await runContract(
      label: 'OrderTrackingBloc',
      attempt: (api) async {
        final bloc = OrderTrackingBloc(orderId: 'o1', apiService: api);
        bloc.add(const OrderTrackingStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == OrderTrackingStatus.ready ||
              s.status == OrderTrackingStatus.failure,
        );
        await bloc.close();
        return state.status == OrderTrackingStatus.ready;
      },
    );
  });

  test('BusinessBloc honours the centralized session contract', () async {
    await runContract(
      label: 'BusinessBloc',
      attempt: (api) async {
        final bloc = BusinessBloc(apiService: api);
        bloc.add(const BusinessStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == BusinessStatus.ready ||
              s.status == BusinessStatus.failure,
        );
        await bloc.close();
        return state.status == BusinessStatus.ready;
      },
    );
  });
}
