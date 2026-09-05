import 'dart:typed_data';

import 'package:merzox/features/business/models/dashboard_period.dart';
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

/// A change to the order filter the browse artboard and its sheet draw.
///
/// The whole filter travels together so a caller can move one field without
/// having to restate the others; [MerchantOrderFilter.copyWith] is how the
/// widgets build the next one.
final class BusinessOrderFilterChanged extends BusinessEvent {
  final MerchantOrderFilter filter;

  const BusinessOrderFilterChanged(this.filter);
}

/// The merchant chose a new picture for the account.
final class BusinessAvatarPicked extends BusinessEvent {
  final Uint8List bytes;

  const BusinessAvatarPicked(this.bytes);
}

/// The dashboard's period control moved.
final class BusinessDashboardPeriodChanged extends BusinessEvent {
  final DashboardPeriod period;

  const BusinessDashboardPeriodChanged(this.period);
}

/// The dashboard's search field settled on a needle.
final class BusinessDashboardSearchChanged extends BusinessEvent {
  final String query;

  const BusinessDashboardSearchChanged(this.query);
}

/// A page of the dashboard's orders table was asked for.
final class BusinessDashboardPageChanged extends BusinessEvent {
  final int page;

  const BusinessDashboardPageChanged(this.page);
}

final class BusinessOrderStatusChanged extends BusinessEvent {
  final String orderId;
  final String status;
  const BusinessOrderStatusChanged(this.orderId, this.status);
}

/// `إرسال إشعار` on `تفاصيل الطلب`: tell the customer the status again,
/// unchanged. The server rate-limits it; nothing here needs to.
final class BusinessOrderCustomerNotified extends BusinessEvent {
  final String orderId;
  const BusinessOrderCustomerNotified(this.orderId);
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

final class BusinessCourierLocationRevoked extends BusinessEvent {
  final String orderId;

  const BusinessCourierLocationRevoked(this.orderId);
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

/// `الرئيسية – 13` offers "show on the storefront" and "hide from the
/// storefront" as one pair of menu items, which is one flag on the product.
final class BusinessProductVisibilityChanged extends BusinessEvent {
  final String productId;
  final bool visible;

  const BusinessProductVisibilityChanged({
    required this.productId,
    required this.visible,
  });
}

/// The menu's "duplicate product": a new product built from an existing one.
final class BusinessProductDuplicated extends BusinessEvent {
  final OwnerProduct product;

  const BusinessProductDuplicated(this.product);
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

  /// Everything narrowing the order list: the chip, the search field and the
  /// filter sheet.
  final MerchantOrderFilter orderFilter;

  /// What the dashboard is reporting on: the period its control names, the
  /// needle its search field holds, and the page of the table below them.
  final DashboardPeriod dashboardPeriod;
  final String dashboardQuery;
  final int dashboardPage;

  /// The dashboard's own table. Separate from [orders], which belongs to the
  /// orders tab and answers to a different filter.
  final List<OwnerOrder> dashboardOrders;
  final int dashboardOrderTotal;
  final bool dashboardBusy;

  /// The signed-in account. The shell shows its picture in the bar, which is
  /// the account's, not the shop's - a shop already has its own logo
  /// elsewhere.
  final AuthApiUser? account;

  final OwnerBusiness? business;
  final BusinessDashboardData? dashboard;
  final List<OwnerOrder> orders;
  final Map<String, int> orderCounts;
  final List<OwnerProduct> products;
  final String? errorMessage;

  /// A one-shot translation key for something that went right, read once by
  /// whatever is on screen. It travels like `errorMessage` — set by the emit
  /// that earned it and cleared by the next one — so a notice can never be
  /// shown twice for one action.
  final String? noticeCode;

  final int revision;

  /// One-shot memory-only bridge between the successful merchant assignment
  /// response and the system share sheet. It is consumed before presentation
  /// and is never written to AuthSessionService, SharedPreferences or a URL.
  final CourierLocationHandoff? courierLocationHandoff;

  const BusinessState({
    this.status = BusinessStatus.initial,
    this.selectedTab = 0,
    this.orderFilter = const MerchantOrderFilter(),
    this.dashboardPeriod = DashboardPeriod.initial,
    this.dashboardQuery = '',
    this.dashboardPage = 1,
    this.dashboardOrders = const [],
    this.dashboardOrderTotal = 0,
    this.dashboardBusy = false,
    this.account,
    this.business,
    this.dashboard,
    this.orders = const [],
    this.orderCounts = const {},
    this.products = const [],
    this.errorMessage,
    this.noticeCode,
    this.revision = 0,
    this.courierLocationHandoff,
  });

  BusinessState copyWith({
    BusinessStatus? status,
    int? selectedTab,
    MerchantOrderFilter? orderFilter,
    DashboardPeriod? dashboardPeriod,
    String? dashboardQuery,
    int? dashboardPage,
    List<OwnerOrder>? dashboardOrders,
    int? dashboardOrderTotal,
    bool? dashboardBusy,
    AuthApiUser? account,
    OwnerBusiness? business,
    BusinessDashboardData? dashboard,
    List<OwnerOrder>? orders,
    Map<String, int>? orderCounts,
    List<OwnerProduct>? products,
    String? errorMessage,
    String? noticeCode,
    int? revision,
    CourierLocationHandoff? courierLocationHandoff,
    bool clearCourierLocationHandoff = false,
  }) => BusinessState(
    status: status ?? this.status,
    selectedTab: selectedTab ?? this.selectedTab,
    orderFilter: orderFilter ?? this.orderFilter,
    dashboardPeriod: dashboardPeriod ?? this.dashboardPeriod,
    dashboardQuery: dashboardQuery ?? this.dashboardQuery,
    dashboardPage: dashboardPage ?? this.dashboardPage,
    dashboardOrders: dashboardOrders ?? this.dashboardOrders,
    dashboardOrderTotal: dashboardOrderTotal ?? this.dashboardOrderTotal,
    dashboardBusy: dashboardBusy ?? this.dashboardBusy,
    account: account ?? this.account,
    business: business ?? this.business,
    dashboard: dashboard ?? this.dashboard,
    orders: orders ?? this.orders,
    orderCounts: orderCounts ?? this.orderCounts,
    products: products ?? this.products,
    errorMessage: errorMessage,
    noticeCode: noticeCode,
    revision: revision ?? this.revision,
    courierLocationHandoff: clearCourierLocationHandoff
        ? null
        : courierLocationHandoff ?? this.courierLocationHandoff,
  );

  /// How many pages the dashboard's table has, never fewer than one so the
  /// counter reads `1 / 1` on an empty period rather than `1 / 0`.
  int get dashboardPageCount {
    if (dashboardOrderTotal <= 0) return 1;
    return (dashboardOrderTotal + BusinessBloc.dashboardPageSize - 1) ~/
        BusinessBloc.dashboardPageSize;
  }
}

class BusinessBloc extends Bloc<BusinessEvent, BusinessState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// Read rather than called directly so a test can say what day it is, which
  /// is the only way to state what `this month` resolves to.
  final DateTime Function() _now;

  /// The server's own ceiling. Asking for more is refused, not truncated.
  static const int dashboardPageSize = 50;

  BusinessBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    DateTime Function()? now,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       _now = now ?? DateTime.now,
       super(const BusinessState()) {
    on<BusinessStarted>(_onStarted);
    on<BusinessTabChanged>((event, emit) {
      emit(state.copyWith(selectedTab: event.index));
    });
    on<BusinessRefreshed>(_onRefreshed);
    on<BusinessOrderFilterChanged>(_onOrderFilterChanged);
    on<BusinessDashboardPeriodChanged>(_onDashboardPeriodChanged);
    on<BusinessDashboardSearchChanged>(_onDashboardSearchChanged);
    on<BusinessDashboardPageChanged>(_onDashboardPageChanged);
    on<BusinessAvatarPicked>(_onAvatarPicked);
    on<BusinessOrderStatusChanged>(_onOrderStatusChanged);
    on<BusinessOrderCustomerNotified>(_onOrderCustomerNotified);
    on<BusinessOrderCourierAssigned>(_onOrderCourierAssigned);
    on<BusinessCourierLocationRevoked>(_onCourierLocationRevoked);
    on<BusinessCourierLocationHandoffConsumed>((event, emit) {
      emit(state.copyWith(clearCourierLocationHandoff: true));
    });
    on<BusinessProductSaved>(_onProductSaved);
    on<BusinessProductDeleted>(_onProductDeleted);
    on<BusinessProductVisibilityChanged>(_onProductVisibilityChanged);
    on<BusinessProductDuplicated>(_onProductDuplicated);
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
      // The dashboard opens on its own period rather than on everything the
      // shop has ever sold, so its figures and its table agree from the first
      // frame instead of jumping when the control is first touched.
      final MerchantOrderFilter dashboard = _dashboardFilter();

      final results = await Future.wait<dynamic>([
        _apiService.ownerBusiness(token: token),
        // The account is read for its picture, which is decoration. A shell
        // that would not open because a portrait could not be fetched would
        // be a worse screen than one with a placeholder on it, so this arm
        // cannot sink the load.
        _apiService
            .me(token: token)
            .then<AuthApiUser?>((AuthApiUser user) => user)
            .onError((_, _) => null),
        _apiService.businessDashboard(
          token: token,
          from: dashboard.from,
          to: dashboard.to,
        ),
        _ownerOrders(token),
        _apiService.ownerProducts(token: token),
        _apiService.ownerOrders(
          token: token,
          filter: dashboard,
          page: 1,
          limit: dashboardPageSize,
        ),
      ]);
      final orderList = results[3] as OwnerOrderList;
      final dashboardOrders = results[5] as OwnerOrderList;
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          business: results[0] as OwnerBusiness,
          account: results[1] as AuthApiUser?,
          dashboard: results[2] as BusinessDashboardData,
          orders: orderList.orders,
          orderCounts: orderList.counts,
          products: results[4] as List<OwnerProduct>,
          dashboardOrders: dashboardOrders.orders,
          dashboardOrderTotal: dashboardOrders.total,
          dashboardPage: 1,
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
  Future<OwnerOrderList> _ownerOrders(String token) =>
      _apiService.ownerOrders(token: token, filter: state.orderFilter);

  /// What the dashboard is asking the server for: the period its control
  /// names, plus whatever its search field holds.
  MerchantOrderFilter _dashboardFilter([
    DashboardPeriod? period,
    String? query,
  ]) {
    final DayRange days = (period ?? state.dashboardPeriod).boundsOn(_now());
    return MerchantOrderFilter(
      query: (query ?? state.dashboardQuery).trim(),
      from: days.from,
      to: days.to,
    );
  }

  /// Re-reads the dashboard: the three figures and the page of the table.
  ///
  /// Both go in one request pair against the same period, so the figures can
  /// never describe a period the rows below them do not.
  Future<void> _loadDashboard(
    Emitter<BusinessState> emit, {
    DashboardPeriod? period,
    String? query,
    int? page,
  }) async {
    final DashboardPeriod nextPeriod = period ?? state.dashboardPeriod;
    final String nextQuery = query ?? state.dashboardQuery;
    // Narrowing the period or the needle puts the reader back on the first
    // page: page nine of the old result is not page nine of the new one.
    final int nextPage = page ?? 1;

    emit(
      state.copyWith(
        dashboardPeriod: nextPeriod,
        dashboardQuery: nextQuery,
        dashboardPage: nextPage,
        dashboardBusy: true,
      ),
    );

    try {
      final String token = await _token();
      final MerchantOrderFilter filter = _dashboardFilter(
        nextPeriod,
        nextQuery,
      );

      final List<dynamic> results =
          await Future.wait<dynamic>(<Future<dynamic>>[
            _apiService.ownerOrders(
              token: token,
              filter: filter,
              page: nextPage,
              limit: dashboardPageSize,
            ),
            _apiService.businessDashboard(
              token: token,
              from: filter.from,
              to: filter.to,
            ),
          ]);
      final OwnerOrderList list = results[0] as OwnerOrderList;

      emit(
        state.copyWith(
          dashboardBusy: false,
          dashboardOrders: list.orders,
          dashboardOrderTotal: list.total,
          dashboard: results[1] as BusinessDashboardData,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          dashboardBusy: false,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// Sends the chosen picture and keeps whatever the server says it is now.
  ///
  /// The URL is read back from the response rather than guessed at, because
  /// the image host - not this app - decides where the picture ends up.
  Future<void> _onAvatarPicked(
    BusinessAvatarPicked event,
    Emitter<BusinessState> emit,
  ) async {
    try {
      final AuthApiUser account = await _apiService.uploadMyAvatar(
        token: await _token(),
        bytes: event.bytes,
      );

      emit(
        state.copyWith(
          account: account,
          noticeCode: 'profileEdit.avatarUpdated',
        ),
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: ApiService.messageFromError(error)));
    }
  }

  Future<void> _onDashboardPeriodChanged(
    BusinessDashboardPeriodChanged event,
    Emitter<BusinessState> emit,
  ) => _loadDashboard(emit, period: event.period);

  Future<void> _onDashboardSearchChanged(
    BusinessDashboardSearchChanged event,
    Emitter<BusinessState> emit,
  ) => _loadDashboard(emit, query: event.query);

  Future<void> _onDashboardPageChanged(
    BusinessDashboardPageChanged event,
    Emitter<BusinessState> emit,
  ) {
    final int page = event.page.clamp(1, state.dashboardPageCount);
    if (page == state.dashboardPage) return Future<void>.value();
    return _loadDashboard(emit, page: page);
  }

  Future<void> _onOrderFilterChanged(
    BusinessOrderFilterChanged event,
    Emitter<BusinessState> emit,
  ) async {
    emit(
      state.copyWith(status: BusinessStatus.loading, orderFilter: event.filter),
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
          // The server notifies the customer as part of the same request, so
          // the merchant is told both things happened. Without this the list
          // simply redrew and nothing said the customer had been informed.
          noticeCode: 'merchantOrder.statusUpdated',
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

  Future<void> _onOrderCustomerNotified(
    BusinessOrderCustomerNotified event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));

    try {
      final order = await _apiService.notifyOrderCustomer(
        token: await _token(),
        orderId: event.orderId,
      );

      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: state.orders
              .map((candidate) => candidate.id == order.id ? order : candidate)
              .toList(),
          noticeCode: 'merchantOrder.notificationSent',
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

  /// The kill switch behind `تجاهل الرمز`.
  ///
  /// The label always promised the credential was discarded; until this it only
  /// closed the dialog. Revoking is idempotent server-side, so the worst case
  /// of a double tap is a second success.
  Future<void> _onCourierLocationRevoked(
    BusinessCourierLocationRevoked event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));

    try {
      final order = await _apiService.revokeOrderCourierLocation(
        token: await _token(),
        orderId: event.orderId,
      );

      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          orders: state.orders
              .map((candidate) => candidate.id == order.id ? order : candidate)
              .toList(growable: false),
          revision: state.revision + 1,
          noticeCode: 'courierLocation.accessRevoked',
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

  /// Hiding a product takes it off the storefront and leaves it in the
  /// merchant's own list, which is the only reason the "show" half of the
  /// menu pair is reachable at all.
  Future<void> _onProductVisibilityChanged(
    BusinessProductVisibilityChanged event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      final updated = await _apiService.updateOwnerProduct(
        token: await _token(),
        productId: event.productId,
        changes: <String, dynamic>{'isActive': event.visible},
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          products: state.products
              .map((item) => item.id == event.productId ? updated : item)
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

  /// A duplicate is a create, assembled from fields the merchant may already
  /// write. It deliberately carries no server-owned value across — no id, no
  /// derived price, no review or sales history — so the copy is a new product
  /// and not a second reference to the old one.
  Future<void> _onProductDuplicated(
    BusinessProductDuplicated event,
    Emitter<BusinessState> emit,
  ) async {
    emit(state.copyWith(status: BusinessStatus.saving));
    try {
      final created = await _apiService.createOwnerProduct(
        token: await _token(),
        product: duplicateProductPayload(event.product),
      );
      emit(
        state.copyWith(
          status: BusinessStatus.ready,
          products: <OwnerProduct>[created, ...state.products],
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
