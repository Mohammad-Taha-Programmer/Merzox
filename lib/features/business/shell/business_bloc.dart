import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
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

final class BusinessOrderGroupChanged extends BusinessEvent {
  final String group;
  const BusinessOrderGroupChanged(this.group);
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

final class BusinessState {
  final BusinessStatus status;
  final int selectedTab;
  final String orderGroup;
  final OwnerBusiness? business;
  final BusinessDashboardData? dashboard;
  final List<OwnerOrder> orders;
  final Map<String, int> orderCounts;
  final List<BusinessProductApiModel> products;
  final String? errorMessage;
  final int revision;

  const BusinessState({
    this.status = BusinessStatus.initial,
    this.selectedTab = 0,
    this.orderGroup = 'current',
    this.business,
    this.dashboard,
    this.orders = const [],
    this.orderCounts = const {},
    this.products = const [],
    this.errorMessage,
    this.revision = 0,
  });

  BusinessState copyWith({
    BusinessStatus? status,
    int? selectedTab,
    String? orderGroup,
    OwnerBusiness? business,
    BusinessDashboardData? dashboard,
    List<OwnerOrder>? orders,
    Map<String, int>? orderCounts,
    List<BusinessProductApiModel>? products,
    String? errorMessage,
    int? revision,
  }) => BusinessState(
    status: status ?? this.status,
    selectedTab: selectedTab ?? this.selectedTab,
    orderGroup: orderGroup ?? this.orderGroup,
    business: business ?? this.business,
    dashboard: dashboard ?? this.dashboard,
    orders: orders ?? this.orders,
    orderCounts: orderCounts ?? this.orderCounts,
    products: products ?? this.products,
    errorMessage: errorMessage,
    revision: revision ?? this.revision,
  );
}

class BusinessBloc extends Bloc<BusinessEvent, BusinessState> {
  final ApiService _apiService;

  BusinessBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const BusinessState()) {
    on<BusinessStarted>(_onStarted);
    on<BusinessTabChanged>((event, emit) {
      emit(state.copyWith(selectedTab: event.index));
    });
    on<BusinessRefreshed>(_onRefreshed);
    on<BusinessOrderGroupChanged>(_onOrderGroupChanged);
    on<BusinessOrderStatusChanged>(_onOrderStatusChanged);
    on<BusinessOrderCourierAssigned>(_onOrderCourierAssigned);
    on<BusinessProductSaved>(_onProductSaved);
    on<BusinessProductDeleted>(_onProductDeleted);
    on<BusinessProfileSaved>(_onProfileSaved);
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthBloc.tokenKey);
    if (token == null || token.isEmpty) {
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
        _apiService.ownerOrders(token: token, statusGroup: state.orderGroup),
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
          products: results[3] as List<BusinessProductApiModel>,
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

  Future<void> _onOrderGroupChanged(
    BusinessOrderGroupChanged event,
    Emitter<BusinessState> emit,
  ) async {
    emit(
      state.copyWith(orderGroup: event.group, status: BusinessStatus.loading),
    );
    try {
      final list = await _apiService.ownerOrders(
        token: await _token(),
        statusGroup: event.group,
      );
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
      final list = await _apiService.ownerOrders(
        token: await _token(),
        statusGroup: state.orderGroup,
      );
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
      await _apiService.assignOrderCourier(
        token: await _token(),
        orderId: event.orderId,
        name: event.name,
        phone: event.phone,
      );
      final list = await _apiService.ownerOrders(
        token: await _token(),
        statusGroup: state.orderGroup,
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: list.orders,
          orderCounts: list.counts,
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
