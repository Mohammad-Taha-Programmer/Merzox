import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/merchant_filter_sheets.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// The five actions `الرئيسية – 13` offers on one product, and the sheet
/// `الرئيسية – 16` filters the catalogue with.
///
/// Hiding and deleting used to be the same call. They are now different, and
/// the difference is what most of this file is about: a hidden product stays
/// in the merchant's own list so the menu's "show" half can reach it again.

Map<String, dynamic> _product(
  String id, {
  String name = 'أساس فت مي',
  String classification = 'new',
  bool isActive = true,
  bool unlimitedStock = false,
  List<Map<String, dynamic>> variants = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'description': 'وصف',
  'price': 35,
  'costPrice': 20,
  'stockQuantity': 40,
  'unlimitedStock': unlimitedStock,
  'discountPercent': 10,
  'finalPrice': 31.5,
  'inStock': true,
  'keywords': const <String>['مكياج'],
  'imageUrls': const <String>['https://example.test/a.png'],
  'classification': classification,
  'isService': false,
  'isActive': isActive,
  'variants': variants,
};

class _ProductApi extends ApiService {
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> patched = <Map<String, dynamic>>[];
  final List<String> deleted = <String>[];

  List<OwnerProduct> stored = const <OwnerProduct>[];

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
      });

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      stored;

  @override
  Future<OwnerProduct> createOwnerProduct({
    required String token,
    required Map<String, dynamic> product,
  }) async {
    created.add(product);
    return OwnerProduct.fromJson(<String, dynamic>{
      ..._product('copy-1'),
      ...product,
      'id': 'copy-1',
    });
  }

  @override
  Future<OwnerProduct> updateOwnerProduct({
    required String token,
    required String productId,
    required Map<String, dynamic> changes,
  }) async {
    patched.add(<String, dynamic>{'id': productId, ...changes});
    final OwnerProduct current = stored.firstWhere(
      (OwnerProduct item) => item.id == productId,
    );

    return OwnerProduct.fromJson(<String, dynamic>{
      ..._product(current.id, isActive: current.isActive),
      ...changes,
      'id': current.id,
    });
  }

  @override
  Future<void> deleteOwnerProduct({
    required String token,
    required String productId,
  }) async => deleted.add(productId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ProductApi api;

  setUp(() {
    api = _ProductApi();
    useAuthenticatedSession(business: true);
  });

  Future<BusinessBloc> started(List<Map<String, dynamic>> products) async {
    api.stored = products.map(OwnerProduct.fromJson).toList();

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;

    return bloc;
  }

  Future<BusinessState> settle(BusinessBloc bloc) => bloc.stream.firstWhere(
    (BusinessState state) => state.status != BusinessStatus.saving,
  );

  group('hiding and showing', () {
    test('hiding sends only the visibility flag', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1'),
      ]);

      bloc.add(
        const BusinessProductVisibilityChanged(productId: 'p1', visible: false),
      );
      await settle(bloc);

      expect(api.patched.single, <String, dynamic>{
        'id': 'p1',
        'isActive': false,
      });
    });

    test('a hidden product stays in the merchant list', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1'),
      ]);

      bloc.add(
        const BusinessProductVisibilityChanged(productId: 'p1', visible: false),
      );
      await settle(bloc);

      // Whoever can hide a product must be able to find it again.
      expect(bloc.state.products, hasLength(1));
      expect(bloc.state.products.single.isActive, isFalse);
    });

    test('showing puts it back on the storefront', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1', isActive: false),
      ]);

      bloc.add(
        const BusinessProductVisibilityChanged(productId: 'p1', visible: true),
      );
      await settle(bloc);

      expect(api.patched.single['isActive'], isTrue);
      expect(bloc.state.products.single.isActive, isTrue);
    });

    test('deleting is a different call from hiding', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1'),
      ]);

      bloc.add(const BusinessProductDeleted('p1'));
      await settle(bloc);

      expect(api.deleted, <String>['p1']);
      expect(api.patched, isEmpty);
      expect(bloc.state.products, isEmpty);
    });
  });

  group('duplicating', () {
    test('the copy carries the merchant fields and no server ones', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1'),
      ]);

      bloc.add(BusinessProductDuplicated(bloc.state.products.single));
      await settle(bloc);

      final Map<String, dynamic> payload = api.created.single;
      expect(payload['name'], 'أساس فت مي');
      expect(payload['price'], 35);
      expect(payload['costPrice'], 20);
      expect(payload['discountPercent'], 10);
      expect(payload['stockQuantity'], 40);
      expect(payload['classification'], 'new');
      expect(payload['keywords'], <String>['مكياج']);

      // Server-owned values must not be dictated by a duplicate.
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('finalPrice'), isFalse);
      expect(payload.containsKey('inStock'), isFalse);
    });

    test('the copy arrives hidden', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1'),
      ]);

      bloc.add(BusinessProductDuplicated(bloc.state.products.single));
      await settle(bloc);

      // An unedited second listing must not reach customers on its own.
      expect(api.created.single['isActive'], isFalse);
      expect(bloc.state.products.first.id, 'copy-1');
      expect(bloc.state.products, hasLength(2));
    });

    test('an unlimited-stock product sends no quantity', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product('p1', unlimitedStock: true),
      ]);

      bloc.add(BusinessProductDuplicated(bloc.state.products.single));
      await settle(bloc);

      expect(api.created.single['unlimitedStock'], isTrue);
      expect(api.created.single.containsKey('stockQuantity'), isFalse);
    });

    test('variants are copied without their ids', () async {
      final BusinessBloc bloc = await started(<Map<String, dynamic>>[
        _product(
          'p1',
          variants: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': '64c000000000000000000001',
              'label': 'حجم كبير',
              'priceOverride': 40,
              'stockQuantity': 5,
              'unlimitedStock': false,
              'isActive': true,
              'price': 40,
              'finalPrice': 36,
              'inStock': true,
            },
          ],
        ),
      ]);

      bloc.add(BusinessProductDuplicated(bloc.state.products.single));
      await settle(bloc);

      final List<dynamic> variants =
          api.created.single['variants'] as List<dynamic>;
      final Map<String, dynamic> variant =
          variants.single as Map<String, dynamic>;

      // Keeping the id would have the server edit the original's variant.
      expect(variant.containsKey('id'), isFalse);
      expect(variant['label'], 'حجم كبير');
      expect(variant['priceOverride'], 40);
    });
  });

  group('the product filter sheet', () {
    List<OwnerProduct> catalogue() => <OwnerProduct>[
      OwnerProduct.fromJson(_product('p1', name: 'أساس فت مي')),
      OwnerProduct.fromJson(
        _product('p2', name: 'أحمر شفاه', classification: 'offers'),
      ),
      OwnerProduct.fromJson(_product('p3', name: 'ماسكارا', isActive: false)),
    ];

    test('an empty filter keeps everything', () {
      expect(const MerchantProductFilter().apply(catalogue()), hasLength(3));
      expect(const MerchantProductFilter().isEmpty, isTrue);
    });

    test('a name narrows to what contains it', () {
      final List<OwnerProduct> found = const MerchantProductFilter(
        name: 'شفاه',
      ).apply(catalogue());

      expect(found.map((OwnerProduct p) => p.id), <String>['p2']);
    });

    test('a classification narrows to that classification', () {
      final List<OwnerProduct> found = const MerchantProductFilter(
        classification: 'offers',
      ).apply(catalogue());

      expect(found.map((OwnerProduct p) => p.id), <String>['p2']);
    });

    test('the state field separates hidden products from live ones', () {
      expect(
        const MerchantProductFilter(
          visible: false,
        ).apply(catalogue()).map((OwnerProduct p) => p.id),
        <String>['p3'],
      );
      expect(
        const MerchantProductFilter(
          visible: true,
        ).apply(catalogue()).map((OwnerProduct p) => p.id),
        <String>['p1', 'p2'],
      );
    });

    test('the sheet and the browse search box intersect', () {
      // The sheet says "offers", the box says "أساس": nothing is both.
      expect(
        const MerchantProductFilter(
          classification: 'offers',
        ).apply(catalogue(), search: 'أساس'),
        isEmpty,
      );
    });
  });
}
