import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import '../models/business_models.dart';

sealed class BusinessEvent {
  const BusinessEvent();
}

final class BusinessStarted extends BusinessEvent {
  const BusinessStarted();
}

final class BusinessTabChanged extends BusinessEvent {
  final int index;
  const BusinessTabChanged(this.index);
}

final class BusinessRefreshed extends BusinessEvent {
  const BusinessRefreshed();
}

/// A change to either half of the order filter the browse artboard draws.
///
/// A null [status] means "no status filter" — the state the chip starts in —
/// so the chip and the search field can each move without disturbing the
/// other.
final class BusinessOrderFilterChanged extends BusinessEvent {
  final String? status;
  final String query;

  const BusinessOrderFilterChanged({this.status, this.query = ''});
}

final class BusinessOrderStatusChanged extends BusinessEvent {
  final String orderId;
  final String status;
  const BusinessOrderStatusChanged(this.orderId, this.status);
}

/// Filling in the driver is what makes the courier card appear on the
/// customer's tracking screen.
final class BusinessOrderCourierAssigned extends BusinessEvent {
  final String orderId;
  final String name;
  final String phone;

  const BusinessOrderCourierAssigned({
    required this.orderId,
    required this.name,
    this.phone = '',
  });
}

final class BusinessCourierLocationHandoffConsumed extends BusinessEvent {
  const BusinessCourierLocationHandoffConsumed();
}

final class BusinessProductSaved extends BusinessEvent {
  final String? productId;
  final Map<String, dynamic> values;
  const BusinessProductSaved({this.productId, required this.values});
}

final class BusinessProductDeleted extends BusinessEvent {
  final String productId;
  const BusinessProductDeleted(this.productId);
}

final class BusinessProfileSaved extends BusinessEvent {
  final Map<String, dynamic> values;
  const BusinessProfileSaved(this.values);
}

enum BusinessStatus { initial, loading, ready, saving, failure }

final class CourierLocationHandoff {
  final String orderId;
  final String capabilityToken;
  final DateTime expiresAt;

  const CourierLocationHandoff({
    required this.orderId,
    required this.capabilityToken,
    required this.expiresAt,
  });
}

final class BusinessState {
  final BusinessStatus status;
  final int selectedTab;

  /// The status the chip is showing, or null while it reads "order status".
  final String? orderStatusFilter;

  /// What the merchant typed into the order search field.
  final String orderQuery;

  final OwnerBusiness? business;
  final BusinessDashboardData? dashboard;
  final List<OwnerOrder> orders;
  final Map<String, int> orderCounts;
  final List<OwnerProduct> products;
  final String? errorMessage;
  final int revision;

  /// One-shot memory-only bridge between the successful merchant assignment
  /// response and the system share sheet. It is consumed before presentation
  /// and is never written to AuthSessionService, SharedPreferences or a URL.
  final CourierLocationHandoff? courierLocationHandoff;

  const BusinessState({
    this.status = BusinessStatus.initial,
    this.selectedTab = 0,
    this.orderStatusFilter,
    this.orderQuery = '',
    this.business,
    this.dashboard,
    this.orders = const [],
    this.orderCounts = const {},
    this.products = const [],
    this.errorMessage,
    this.revision = 0,
    this.courierLocationHandoff,
  });

  BusinessState copyWith({
    BusinessStatus? status,
    int? selectedTab,
    String? orderStatusFilter,
    bool clearOrderStatusFilter = false,
    String? orderQuery,
    OwnerBusiness? business,
    BusinessDashboardData? dashboard,
    List<OwnerOrder>? orders,
    Map<String, int>? orderCounts,
    List<OwnerProduct>? products,
    String? errorMessage,
    int? revision,
    CourierLocationHandoff? courierLocationHandoff,
    bool clearCourierLocationHandoff = false,
  }) => BusinessState(
    status: status ?? this.status,
    selectedTab: selectedTab ?? this.selectedTab,
    orderStatusFilter: clearOrderStatusFilter
        ? null
        : orderStatusFilter ?? this.orderStatusFilter,
    orderQuery: orderQuery ?? this.orderQuery,
    business: business ?? this.business,
    dashboard: dashboard ?? this.dashboard,
    orders: orders ?? this.orders,
    orderCounts: orderCounts ?? this.orderCounts,
    products: products ?? this.products,
    errorMessage: errorMessage,
    revision: revision ?? this.revision,
    courierLocationHandoff: clearCourierLocationHandoff
        ? null
        : courierLocationHandoff ?? this.courierLocationHandoff,
  );
}

class BusinessBloc extends Bloc<BusinessEvent, BusinessState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  BusinessBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const BusinessState()) {
    on<BusinessStarted>(_onStarted);
    on<BusinessTabChanged>((event, emit) {
      emit(state.copyWith(selectedTab: event.index));
    });
    on<BusinessRefreshed>(_onRefreshed);
    on<BusinessOrderFilterChanged>(_onOrderFilterChanged);
    on<BusinessOrderStatusChanged>(_onOrderStatusChanged);
    on<BusinessOrderCourierAssigned>(_onOrderCourierAssigned);
    on<BusinessCourierLocationHandoffConsumed>((event, emit) {
      emit(state.copyWith(clearCourierLocationHandoff: true));
    });
    on<BusinessProductSaved>(_onProductSaved);
    on<BusinessProductDeleted>(_onProductDeleted);
    on<BusinessProfileSaved>(_onProfileSaved);
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

  Future<void> _onStarted(BusinessStarted event, Emitter<BusinessState> emit) =>
      _load(emit, showLoading: true);

  Future<void> _onRefreshed(
    BusinessRefreshed event,
    Emitter<BusinessState> emit,
  ) => _load(emit, showLoading: false);

  Future<void> _load(
    Emitter<BusinessState> emit, {
    required bool showLoading,
  }) async {
    if (showLoading) emit(state.copyWith(status: BusinessStatus.loading));
    try {
      final token = await _token();
      final results = await Future.wait<dynamic>([
        _apiService.ownerBusiness(token: token),
        _apiService.businessDashboard(token: token),
        _ownerOrders(token),
        _apiService.ownerProducts(token: token),
      ]);
      final orderList = results[2] as OwnerOrderList;
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          business: results[0] as OwnerBusiness,
          dashboard: results[1] as BusinessDashboardData,
          orders: orderList.orders,
          orderCounts: orderList.counts,
          products: results[3] as List<OwnerProduct>,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// The one place that builds the order request, so the mutually exclusive
  /// `status` and `statusGroup` pair can never both be sent.
  Future<OwnerOrderList> _ownerOrders(String token) => _apiService.ownerOrders(
    token: token,
    status: state.orderStatusFilter ?? '',
    query: state.orderQuery,
  );

  Future<void> _onOrderFilterChanged(
    BusinessOrderFilterChanged event,
    Emitter<BusinessState> emit,
  ) async {
    emit(
      state.copyWith(
        status: BusinessStatus.loading,
        orderStatusFilter: event.status,
        clearOrderStatusFilter: event.status == null,
        orderQuery: event.query,
      ),
    );
    try {
      final list = await _ownerOrders(await _token());
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: list.orders,
          orderCounts: list.counts,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onOrderStatusChanged(
    BusinessOrderStatusChanged event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      await _apiService.updateOwnerOrderStatus(
        token: await _token(),
        orderId: event.orderId,
        status: event.status,
      );
      final list = await _ownerOrders(await _token());
      final dashboard = await _apiService.businessDashboard(
        token: await _token(),
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: list.orders,
          orderCounts: list.counts,
          dashboard: dashboard,
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onOrderCourierAssigned(
    BusinessOrderCourierAssigned event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));

    try {
      final assignment = await _apiService.assignOrderCourier(
        token: await _token(),
        orderId: event.orderId,
        name: event.name,
        phone: event.phone,
      );

      final updatedOrders = state.orders
          .map(
            (order) =>
                order.id == assignment.order.id ? assignment.order : order,
          )
          .toList(growable: false);

      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: updatedOrders,
          revision: state.revision + 1,
          courierLocationHandoff: CourierLocationHandoff(
            orderId: assignment.order.id,
            capabilityToken: assignment.capability.token,
            expiresAt: assignment.capability.expiresAt,
          ),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onProductSaved(
    BusinessProductSaved event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      final token = await _token();
      if (event.productId == null) {
        await _apiService.createOwnerProduct(
          token: token,
          product: event.values,
        );
      } else {
        await _apiService.updateOwnerProduct(
          token: token,
          productId: event.productId!,
          changes: event.values,
        );
      }
      final products = await _apiService.ownerProducts(token: token);
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          products: products,
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onProductDeleted(
    BusinessProductDeleted event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      final token = await _token();
      await _apiService.deleteOwnerProduct(
        token: token,
        productId: event.productId,
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          products: state.products
              .where((item) => item.id != event.productId)
              .toList(),
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onProfileSaved(
    BusinessProfileSaved event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      final business = await _apiService.updateOwnerBusiness(
        token: await _token(),
        changes: event.values,
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          business: business,
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }
}
