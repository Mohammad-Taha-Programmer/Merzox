import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import '../../../core/auth/auth_session_service.dart';
import 'order_tracking_event.dart';
import 'order_tracking_state.dart';

class OrderTrackingBloc extends Bloc<OrderTrackingEvent, OrderTrackingState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;
  final String orderId;

  StreamSubscription<RealtimeOrderTrackingInvalidation>? _realtimeSubscription;

  OrderTrackingBloc({
    required this.orderId,
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeOrderTrackingInvalidation>?
    realtimeOrderTrackingInvalidations,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const OrderTrackingState()) {
    on<OrderTrackingStarted>(_onStarted);
    on<OrderTrackingRefreshRequested>(_onRefreshRequested);
    on<OrderTrackingCancelRequested>(_onCancelRequested);
    on<OrderTrackingAddressChanged>(_onAddressChanged);
    on<OrderTrackingReviewSubmitted>(_onReviewSubmitted);

    _realtimeSubscription = realtimeOrderTrackingInvalidations
        ?.where((invalidation) => invalidation.orderId == orderId)
        .listen((_) {
          if (!isClosed) {
            add(const OrderTrackingRefreshRequested());
          }
        });
  }

  Future<void> _onStarted(
    OrderTrackingStarted event,
    Emitter<OrderTrackingState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _onRefreshRequested(
    OrderTrackingRefreshRequested event,
    Emitter<OrderTrackingState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<OrderTrackingState> emit) async {
    emit(
      state.copyWith(
        status: OrderTrackingStatus.loading,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final order = await _apiService.order(
        token: await _token(),
        orderId: orderId,
      );
      emit(state.copyWith(status: OrderTrackingStatus.ready, order: order));
    } catch (error) {
      emit(
        state.copyWith(
          status: OrderTrackingStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onCancelRequested(
    OrderTrackingCancelRequested event,
    Emitter<OrderTrackingState> emit,
  ) async {
    if (state.isBusy) return;

    emit(
      state.copyWith(
        status: OrderTrackingStatus.working,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final order = await _apiService.cancelOrder(
        token: await _token(),
        orderId: orderId,
        reason: event.reason,
      );
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          order: order,
          messageCode: 'orders.cancelSuccess',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onAddressChanged(
    OrderTrackingAddressChanged event,
    Emitter<OrderTrackingState> emit,
  ) async {
    if (state.isBusy) return;

    final address = event.deliveryAddress.trim();
    if (address.length < 5) {
      emit(state.copyWith(errorMessage: 'tracking.addressTooShort'));
      return;
    }

    emit(
      state.copyWith(
        status: OrderTrackingStatus.working,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final order = await _apiService.updateOrderAddress(
        token: await _token(),
        orderId: orderId,
        deliveryAddress: address,
      );
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          order: order,
          messageCode: 'tracking.addressUpdated',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onReviewSubmitted(
    OrderTrackingReviewSubmitted event,
    Emitter<OrderTrackingState> emit,
  ) async {
    final businessId = state.order?.business.id ?? '';
    if (state.isBusy || businessId.isEmpty) return;

    emit(
      state.copyWith(
        status: OrderTrackingStatus.working,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      await _apiService.submitBusinessReview(
        token: await _token(),
        businessId: businessId,
        rating: event.rating,
        comment: event.comment.trim(),
      );
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          reviewSubmitted: true,
          messageCode: 'tracking.reviewSaved',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: OrderTrackingStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _realtimeSubscription?.cancel();
    return super.close();
  }

  /// Session truth lives in [AuthSessionService]: a stale token without an
  /// active session, or a blank one, resolves to unauthenticated here rather
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
