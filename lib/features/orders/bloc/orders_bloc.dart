import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import 'orders_event.dart';
import 'orders_state.dart';

class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  OrdersBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const OrdersState()) {
    on<OrdersStarted>(_onStarted);
    on<OrdersGroupChanged>(_onGroupChanged);
    on<OrdersLoadMoreRequested>(_onLoadMoreRequested);
    on<OrdersRefreshRequested>(_onRefreshRequested);
    on<OrderCancellationRequested>(_onCancellationRequested);
  }

  Future<void> _onStarted(
    OrdersStarted event,
    Emitter<OrdersState> emit,
  ) async {
    await _loadFirstPage(emit, state.selectedGroup);
  }

  Future<void> _onGroupChanged(
    OrdersGroupChanged event,
    Emitter<OrdersState> emit,
  ) async {
    if (event.group == state.selectedGroup &&
        state.status != OrdersStatus.failure) {
      return;
    }
    await _loadFirstPage(emit, event.group);
  }

  Future<void> _onRefreshRequested(
    OrdersRefreshRequested event,
    Emitter<OrdersState> emit,
  ) async {
    await _loadFirstPage(emit, state.selectedGroup);
  }

  Future<void> _loadFirstPage(
    Emitter<OrdersState> emit,
    OrdersGroup group,
  ) async {
    emit(
      state.copyWith(
        status: OrdersStatus.loading,
        selectedGroup: group,
        orders: const [],
        page: 0,
        hasMore: false,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final response = await _apiService.orders(
        token: await _token(),
        status: group.apiValue,
      );
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          orders: response.orders,
          page: response.page,
          totalOrderCount: response.totalAcrossStatuses,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrdersStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onLoadMoreRequested(
    OrdersLoadMoreRequested event,
    Emitter<OrdersState> emit,
  ) async {
    if (!state.hasMore || state.status != OrdersStatus.ready) return;

    emit(state.copyWith(status: OrdersStatus.loadingMore));
    try {
      final response = await _apiService.orders(
        token: await _token(),
        status: state.selectedGroup.apiValue,
        page: state.page + 1,
      );
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          orders: [...state.orders, ...response.orders],
          page: response.page,
          totalOrderCount: response.totalAcrossStatuses,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onCancellationRequested(
    OrderCancellationRequested event,
    Emitter<OrdersState> emit,
  ) async {
    if (state.status == OrdersStatus.cancelling) return;

    emit(
      state.copyWith(
        status: OrdersStatus.cancelling,
        cancellingOrderId: event.orderId,
        messageCode: '',
        errorMessage: '',
      ),
    );
    try {
      await _apiService.cancelOrder(
        token: await _token(),
        orderId: event.orderId,
        reason: event.reason,
      );
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          orders: state.orders
              .where((order) => order.id != event.orderId)
              .toList(),
          cancellingOrderId: '',
          messageCode: 'orders.cancelSuccess',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          cancellingOrderId: '',
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// Session truth lives in [AuthSessionService]: a stale token left behind
  /// after logout, or a blank one, resolves to unauthenticated here rather
  /// than being re-interpreted per bloc.
  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    return token;
  }
}
