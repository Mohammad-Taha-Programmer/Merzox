import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBusinessApiService extends ApiService {
  String? receivedToken;
  String? receivedPhone;
  String? receivedName;

  @override
  Future<BusinessEnrollmentResult> enrollBusiness({
    required String token,
    required String phone,
    required String email,
    required String currentPassword,
    required String name,
    required String englishName,
    required String description,
    required String category,
    required String address,
    required String attachmentUrl,
  }) async {
    receivedToken = token;
    receivedPhone = phone;
    receivedName = name;
    return const BusinessEnrollmentResult(
      business: OwnerBusiness(
        id: 'business-1',
        name: 'متجر الحي',
        englishName: 'Neighborhood Store',
        description: 'Description',
        category: 'Groceries',
        address: 'Ramallah',
        attachmentUrl: 'https://example.test/document.pdf',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'enrolls the signed-in normal user and clears the old session',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'normal-user-token',
        AuthBloc.userTypeKey: 'normal',
      });
      final api = _FakeBusinessApiService();
      final bloc = BusinessEnrollmentBloc(apiService: api);
      addTearDown(bloc.close);

      final firstStep = bloc.stream.firstWhere((state) => state.step == 1);
      bloc.add(
        const BusinessEnrollmentFirstStepSaved(
          phone: '+972590000001',
          email: 'owner@example.test',
          password: 'Password123',
        ),
      );
      await firstStep;

      final completed = bloc.stream.firstWhere(
        (state) => state.status == BusinessEnrollmentStatus.success,
      );
      bloc.add(
        const BusinessEnrollmentSubmitted(
          name: 'متجر الحي',
          englishName: 'Neighborhood Store',
          description: 'Description',
          category: 'Groceries',
          address: 'Ramallah',
          attachmentUrl: 'https://example.test/document.pdf',
        ),
      );
      await completed;

      expect(api.receivedToken, 'normal-user-token');
      expect(api.receivedPhone, '+972590000001');
      expect(api.receivedName, 'متجر الحي');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AuthBloc.sessionKey), isFalse);
      expect(prefs.getString(AuthBloc.tokenKey), isNull);
      expect(prefs.getString(AuthBloc.userTypeKey), isNull);
    },
  );
}
