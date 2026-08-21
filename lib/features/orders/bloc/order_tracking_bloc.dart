import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import 'order_tracking_event.dart';
import 'order_tracking_state.dart';

class OrderTrackingBloc extends Bloc<OrderTrackingEvent, OrderTrackingState> {
  final ApiService _apiService;
  final String orderId;

  OrderTrackingBloc({required this.orderId, ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const OrderTrackingState()) {
    on<OrderTrackingStarted>(_onStarted);
    on<OrderTrackingRefreshRequested>(_onRefreshRequested);
    on<OrderTrackingCancelRequested>(_onCancelRequested);
    on<OrderTrackingAddressChanged>(_onAddressChanged);
    on<OrderTrackingReviewSubmitted>(_onReviewSubmitted);
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

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthBloc.tokenKey);
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    return token;
  }
}
