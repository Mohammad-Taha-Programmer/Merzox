import '../../../services/api_service.dart';
import 'orders_event.dart';

enum OrdersStatus { initial, loading, ready, loadingMore, cancelling, failure }

final class OrdersState {
  final OrdersStatus status;
  final OrdersGroup selectedGroup;
  final List<OrderApiModel> orders;
  final int page;
  final int totalOrderCount;
  final bool hasMore;
  final String cancellingOrderId;
  final String messageCode;
  final String errorMessage;

  const OrdersState({
    this.status = OrdersStatus.initial,
    this.selectedGroup = OrdersGroup.current,
    this.orders = const [],
    this.page = 0,
    this.totalOrderCount = 0,
    this.hasMore = false,
    this.cancellingOrderId = '',
    this.messageCode = '',
    this.errorMessage = '',
  });

  OrdersState copyWith({
    OrdersStatus? status,
    OrdersGroup? selectedGroup,
    List<OrderApiModel>? orders,
    int? page,
    int? totalOrderCount,
    bool? hasMore,
    String? cancellingOrderId,
    String? messageCode,
    String? errorMessage,
  }) {
    return OrdersState(
      status: status ?? this.status,
      selectedGroup: selectedGroup ?? this.selectedGroup,
      orders: orders ?? this.orders,
      page: page ?? this.page,
      totalOrderCount: totalOrderCount ?? this.totalOrderCount,
      hasMore: hasMore ?? this.hasMore,
      cancellingOrderId: cancellingOrderId ?? this.cancellingOrderId,
      messageCode: messageCode ?? this.messageCode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
