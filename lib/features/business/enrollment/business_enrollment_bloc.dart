import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';

sealed class BusinessEnrollmentEvent {
  const BusinessEnrollmentEvent();
}

final class BusinessEnrollmentFirstStepSaved extends BusinessEnrollmentEvent {
  final String phone;
  final String email;
  final String password;

  const BusinessEnrollmentFirstStepSaved({
    required this.phone,
    required this.email,
    required this.password,
  });
}

final class BusinessEnrollmentBackPressed extends BusinessEnrollmentEvent {
  const BusinessEnrollmentBackPressed();
}

final class BusinessEnrollmentSubmitted extends BusinessEnrollmentEvent {
  final String name;
  final String englishName;
  final String description;
  final String category;
  final String address;
  final String attachmentUrl;

  const BusinessEnrollmentSubmitted({
    required this.name,
    required this.englishName,
    required this.description,
    required this.category,
    required this.address,
    required this.attachmentUrl,
  });
}

enum BusinessEnrollmentStatus { editing, submitting, success, failure }

final class BusinessEnrollmentState {
  final int step;
  final BusinessEnrollmentStatus status;
  final String phone;
  final String email;
  final String password;
  final String? errorMessage;

  const BusinessEnrollmentState({
    this.step = 0,
    this.status = BusinessEnrollmentStatus.editing,
    this.phone = '',
    this.email = '',
    this.password = '',
    this.errorMessage,
  });

  BusinessEnrollmentState copyWith({
    int? step,
    BusinessEnrollmentStatus? status,
    String? phone,
    String? email,
    String? password,
    String? errorMessage,
  }) => BusinessEnrollmentState(
    step: step ?? this.step,
    status: status ?? this.status,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    password: password ?? this.password,
    errorMessage: errorMessage,
  );
}

class BusinessEnrollmentBloc
    extends Bloc<BusinessEnrollmentEvent, BusinessEnrollmentState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  BusinessEnrollmentBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const BusinessEnrollmentState()) {
    on<BusinessEnrollmentFirstStepSaved>((event, emit) {
      emit(
        state.copyWith(
          step: 1,
          phone: event.phone.trim(),
          email: event.email.trim().toLowerCase(),
          password: event.password,
          status: BusinessEnrollmentStatus.editing,
        ),
      );
    });
    on<BusinessEnrollmentBackPressed>(
      (_, emit) => emit(state.copyWith(step: 0)),
    );
    on<BusinessEnrollmentSubmitted>(_onSubmitted);
  }

  Future<void> _onSubmitted(
    BusinessEnrollmentSubmitted event,
    Emitter<BusinessEnrollmentState> emit,
  ) async {
    emit(state.copyWith(status: BusinessEnrollmentStatus.submitting));
    try {
      // Enrollment upgrades the signed-in account, so it must run against a
      // genuinely active session rather than a leftover token.
      final session = await _authSessionService.read();
      final token = session.token;
      if (token == null) {
        throw StateError('Authentication required');
      }
      await _apiService.enrollBusiness(
        token: token,
        phone: state.phone,
        email: state.email,
        currentPassword: state.password,
        name: event.name.trim(),
        englishName: event.englishName.trim(),
        description: event.description.trim(),
        category: event.category.trim(),
        address: event.address.trim(),
        attachmentUrl: event.attachmentUrl.trim(),
      );
      await AuthBloc.clearStoredSession();
      emit(state.copyWith(status: BusinessEnrollmentStatus.success));
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessEnrollmentStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }
}
