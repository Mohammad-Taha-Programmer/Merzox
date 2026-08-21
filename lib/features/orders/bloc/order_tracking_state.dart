import '../../../services/api_service.dart';

enum OrderTrackingStatus { initial, loading, ready, working, failure }

final class OrderTrackingState {
  final OrderTrackingStatus status;
  final OrderApiModel? order;
  final bool reviewSubmitted;
  final String messageCode;
  final String errorMessage;

  const OrderTrackingState({
    this.status = OrderTrackingStatus.initial,
    this.order,
    this.reviewSubmitted = false,
    this.messageCode = '',
    this.errorMessage = '',
  });

  OrderTrackingApiModel? get tracking => order?.tracking;

  bool get isBusy => status == OrderTrackingStatus.working;

  OrderTrackingState copyWith({
    OrderTrackingStatus? status,
    OrderApiModel? order,
    bool? reviewSubmitted,
    String? messageCode,
    String? errorMessage,
  }) {
    return OrderTrackingState(
      status: status ?? this.status,
      order: order ?? this.order,
      reviewSubmitted: reviewSubmitted ?? this.reviewSubmitted,
      messageCode: messageCode ?? this.messageCode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
