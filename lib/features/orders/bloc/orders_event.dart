enum OrdersGroup { current, completed, cancelled }

extension OrdersGroupValue on OrdersGroup {
  String get apiValue => name;
}

sealed class OrdersEvent {
  const OrdersEvent();
}

final class OrdersStarted extends OrdersEvent {
  const OrdersStarted();
}

final class OrdersGroupChanged extends OrdersEvent {
  final OrdersGroup group;

  const OrdersGroupChanged(this.group);
}

final class OrdersLoadMoreRequested extends OrdersEvent {
  const OrdersLoadMoreRequested();
}

final class OrdersRefreshRequested extends OrdersEvent {
  const OrdersRefreshRequested();
}

final class OrderCancellationRequested extends OrdersEvent {
  final String orderId;
  final String reason;

  const OrderCancellationRequested({
    required this.orderId,
    required this.reason,
  });
}
