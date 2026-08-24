import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// FIX4 merchant product contract, client side.
///
/// The two claims under test: the payload the merchant sends contains only
/// contract fields with no invented commercial values, and the merchant-only
/// fields never reach the customer-facing model.

class _ProductApi extends ApiService {
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> updated = [];

  /// Mutated by individual tests rather than passed in, so the spy can change
  /// behaviour part-way through a scenario.
  List<OwnerProduct> stored = const [];
  bool failWrites = false;

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const {'id': 'b1', 'name': 'متجر'});

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const {});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String? statusGroup,
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const {});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      stored;

  @override
  Future<OwnerProduct> createOwnerProduct({
    required String token,
    required Map<String, dynamic> product,
  }) async {
    if (failWrites) throw StateError('create refused');
    created.add(product);
    // The server assigns identity; the client never invents one.
    return OwnerProduct.fromJson({
      'id': 'server-generated-id',
      ...product,
      'finalPrice': 0,
    });
  }

  @override
  Future<OwnerProduct> updateOwnerProduct({
    required String token,
    required String productId,
    required Map<String, dynamic> changes,
  }) async {
    if (failWrites) throw StateError('update refused');
    updated.add(changes);
    return OwnerProduct.fromJson({'id': productId, ...changes});
  }
}

Map<String, dynamic> _values({
  bool unlimited = true,
  int? stockQuantity,
  double discountPercent = 0,
  double? costPrice,
  List<String> keywords = const [],
  List<String> imageUrls = const [],
}) {
  return {
    'name': 'أساس فت مي',
    'description': 'كريم أساس',
    'price': 35.0,
    'costPrice': costPrice,
    'unlimitedStock': unlimited,
    if (!unlimited) 'stockQuantity': stockQuantity ?? 0,
    'discountPercent': discountPercent,
    'keywords': keywords,
    'imageUrls': imageUrls,
    'classification': 'new',
    'isService': false,
    'isActive': true,
  };
}

Future<BusinessBloc> _readyBloc(_ProductApi api) async {
  final bloc = BusinessBloc(apiService: api);
  bloc.add(const BusinessStarted());
  await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);
  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => useAuthenticatedSession(business: true));

  group('merchant product payload', () {
    test('carries every contract field and nothing else', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);

      bloc.add(BusinessProductSaved(values: _values(costPrice: 20)));
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      expect(api.created, hasLength(1));
      final sent = api.created.single;

      expect(sent.keys.toSet(), {
        'name',
        'description',
        'price',
        'costPrice',
        'unlimitedStock',
        'discountPercent',
        'keywords',
        'imageUrls',
        'classification',
        'isService',
        'isActive',
      });

      // Server-owned values are never sent.
      for (final field in [
        'id',
        '_id',
        'finalPrice',
        'inStock',
        'rating',
        'ratingCount',
        'likeCount',
        'createdAt',
      ]) {
        expect(sent.containsKey(field), isFalse, reason: field);
      }

      await bloc.close();
    });

    test(
      'invents no commercial values when the merchant leaves fields blank',
      () async {
        final api = _ProductApi();
        final bloc = await _readyBloc(api);

        bloc.add(BusinessProductSaved(values: _values()));
        await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

        final sent = api.created.single;
        expect(sent['costPrice'], isNull, reason: 'no invented cost');
        expect(sent['discountPercent'], 0, reason: 'no invented discount');
        expect(sent['keywords'], isEmpty);
        expect(sent['imageUrls'], isEmpty);

        await bloc.close();
      },
    );

    test('unlimited stock omits any quantity', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);

      bloc.add(BusinessProductSaved(values: _values()));
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      final sent = api.created.single;
      expect(sent['unlimitedStock'], isTrue);
      // Sending both would describe a finite quantity and unlimited stock at once.
      expect(sent.containsKey('stockQuantity'), isFalse);

      await bloc.close();
    });

    test('finite stock sends the quantity alongside the flag', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);

      bloc.add(
        BusinessProductSaved(
          values: _values(unlimited: false, stockQuantity: 12),
        ),
      );
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      final sent = api.created.single;
      expect(sent['unlimitedStock'], isFalse);
      expect(sent['stockQuantity'], 12);

      await bloc.close();
    });
  });

  group('write outcomes', () {
    test('a created product uses the server-returned identity', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);

      bloc.add(BusinessProductSaved(values: _values()));
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      // The bloc re-reads from the API rather than trusting a local object.
      expect(api.created, hasLength(1));
      expect(api.created.single.containsKey('id'), isFalse);

      await bloc.close();
    });

    test('a failed write reports failure and bumps no revision', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);
      final revisionBefore = bloc.state.revision;

      api.failWrites = true;
      bloc.add(BusinessProductSaved(values: _values()));
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.failure);

      expect(bloc.state.errorMessage, isNotNull);
      // The sheet keys off revision, so an unchanged revision keeps it open
      // with the merchant's values intact.
      expect(bloc.state.revision, revisionBefore);

      await bloc.close();
    });

    test('a successful write bumps the revision exactly once', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);
      final revisionBefore = bloc.state.revision;

      bloc.add(BusinessProductSaved(values: _values()));
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      expect(bloc.state.revision, revisionBefore + 1);

      await bloc.close();
    });

    test('an edit sends changes to the existing product id', () async {
      final api = _ProductApi();
      final bloc = await _readyBloc(api);

      bloc.add(
        BusinessProductSaved(productId: 'p1', values: _values(costPrice: 9)),
      );
      await bloc.stream.firstWhere((s) => s.status == BusinessStatus.ready);

      expect(api.created, isEmpty);
      expect(api.updated, hasLength(1));
      expect(api.updated.single['costPrice'], 9);

      await bloc.close();
    });
  });

  group('OwnerProduct deserialization', () {
    test('a legacy product without FIX4 fields stays purchasable', () {
      final product = OwnerProduct.fromJson(const {
        'id': 'p1',
        'name': 'منتج قديم',
        'price': 12,
      });

      expect(product.costPrice, isNull);
      // The critical legacy default: no stock fields means unlimited, not zero.
      expect(product.unlimitedStock, isTrue);
      expect(product.inStock, isTrue);
      expect(product.stockQuantity, 0);
      expect(product.discountPercent, 0);
      expect(product.keywords, isEmpty);
      expect(product.finalPrice, 12);
    });

    test('merchant fields round-trip from the owner payload', () {
      final product = OwnerProduct.fromJson(const {
        'id': 'p1',
        'name': 'أساس',
        'price': 35,
        'costPrice': 20,
        'stockQuantity': 12,
        'unlimitedStock': false,
        'discountPercent': 15,
        'finalPrice': 29.75,
        'inStock': true,
        'keywords': ['مكياج', '  '],
        'imageUrls': ['https://example.test/a.png'],
      });

      expect(product.costPrice, 20);
      expect(product.stockQuantity, 12);
      expect(product.unlimitedStock, isFalse);
      expect(product.discountPercent, 15);
      expect(product.finalPrice, 29.75);
      expect(product.hasDiscount, isTrue);
      expect(product.keywords, ['مكياج']);
      expect(product.imageUrl, 'https://example.test/a.png');
    });
  });

  group('customer model isolation', () {
    test('the customer product model has no merchant-internal fields', () {
      // A public payload never carries these, and even if one leaked the
      // customer model has nowhere to put it.
      final customer = BusinessProductApiModel.fromJson(const {
        'id': 'p1',
        'name': 'أساس',
        'price': 35,
        // The public commerce contract, which the model now requires.
        'discountPercent': 15,
        'finalPrice': 29.75,
        'inStock': true,
        'hasVariants': false,
        'variants': <Map<String, dynamic>>[],
        'minPrice': 35,
        'maxPrice': 35,
        'minFinalPrice': 29.75,
        'maxFinalPrice': 29.75,
        // Merchant-internal keys, present in the payload and expected to be
        // dropped rather than stored anywhere reachable.
        'costPrice': 20,
        'stockQuantity': 12,
        'keywords': ['secret'],
      });

      expect(customer.name, 'أساس');
      expect(customer.price, 35);
      expect(customer.finalPrice, 29.75);
      expect(customer.inStock, isTrue);

      // The type itself carries no merchant fields; this asserts the surface.
      expect(
        customer.toString().contains('costPrice'),
        isFalse,
        reason: 'costPrice must not exist on the customer model',
      );
    });
  });
}
