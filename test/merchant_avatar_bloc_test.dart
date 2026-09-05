import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// Setting the account's picture.
///
/// The bytes go to the server, which spends the image host's key on the app's
/// behalf, and the URL comes back. The app must keep what it is told rather
/// than guess: where a picture ends up is the host's decision, not this one's.

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

class _AvatarApi extends ApiService {
  final List<Uint8List> uploaded = <Uint8List>[];

  /// What the server says the picture is now. Null makes the upload fail.
  String? url = 'https://i.ibb.co/x/pic.png';

  String initialAvatar = '';

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
      });

  @override
  Future<AuthApiUser> me({required String token}) async =>
      AuthApiUser.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'بتول طه',
        'avatarUrl': initialAvatar,
      });

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
    DateTime? from,
    DateTime? to,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<AuthApiUser> uploadMyAvatar({
    required String token,
    required Uint8List bytes,
  }) async {
    uploaded.add(bytes);

    if (url == null) throw StateError('the image host refused');

    return AuthApiUser.fromJson(<String, dynamic>{
      'id': 'u1',
      'name': 'بتول طه',
      'avatarUrl': url,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AvatarApi api;

  setUp(() {
    api = _AvatarApi();
    useAuthenticatedSession(business: true);
  });

  Future<BusinessBloc> started() async {
    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;

    return bloc;
  }

  test('the shell knows the account it is signed in as', () async {
    api.initialAvatar = 'https://i.ibb.co/x/old.png';
    final BusinessBloc bloc = await started();

    // The bar shows the account's picture, not the shop's logo: a shop's logo
    // is a separate thing with its own place on its own screen.
    expect(bloc.state.account?.avatarUrl, 'https://i.ibb.co/x/old.png');
    expect(bloc.state.account?.name, 'بتول طه');
  });

  test(
    'a chosen picture is sent, and the URL is kept from the reply',
    () async {
      final BusinessBloc bloc = await started();
      expect(bloc.state.account?.avatarUrl, '');

      final Future<BusinessState> done = bloc.stream.firstWhere(
        (BusinessState state) => state.account?.avatarUrl.isNotEmpty ?? false,
      );
      bloc.add(BusinessAvatarPicked(_bytes));
      await done;

      expect(api.uploaded, <Uint8List>[_bytes]);
      expect(bloc.state.account?.avatarUrl, 'https://i.ibb.co/x/pic.png');
    },
  );

  test('a successful change says so', () async {
    final BusinessBloc bloc = await started();

    final Future<BusinessState> done = bloc.stream.firstWhere(
      (BusinessState state) => state.noticeCode != null,
    );
    bloc.add(BusinessAvatarPicked(_bytes));

    expect((await done).noticeCode, 'profileEdit.avatarUpdated');
  });

  test('a refused upload is reported, and keeps the old picture', () async {
    api.initialAvatar = 'https://i.ibb.co/x/old.png';
    api.url = null;

    final BusinessBloc bloc = await started();

    final Future<BusinessState> failed = bloc.stream.firstWhere(
      (BusinessState state) => state.errorMessage != null,
    );
    bloc.add(BusinessAvatarPicked(_bytes));
    await failed;

    // A failed upload must not blank the picture the account already had.
    expect(bloc.state.account?.avatarUrl, 'https://i.ibb.co/x/old.png');
    expect(bloc.state.errorMessage, isNotNull);
  });
}
