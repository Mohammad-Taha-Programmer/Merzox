import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import 'about_us_event.dart';
import 'about_us_state.dart';

class AboutUsBloc extends Bloc<AboutUsEvent, AboutUsState> {
  final ApiService _apiService;

  AboutUsBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const AboutUsState()) {
    on<AboutUsStarted>(_onStarted);
    on<AboutUsRefreshRequested>(_onRefreshRequested);
    on<AboutUsSectionToggled>(_onSectionToggled);
  }

  Future<void> _onStarted(
    AboutUsStarted event,
    Emitter<AboutUsState> emit,
  ) async {
    final languageCode = event.languageCode == 'en' ? 'en' : 'ar';
    if (state.status == AboutUsStatus.ready &&
        state.languageCode == languageCode) {
      return;
    }

    await _load(emit, languageCode);
  }

  Future<void> _onRefreshRequested(
    AboutUsRefreshRequested event,
    Emitter<AboutUsState> emit,
  ) async {
    await _load(emit, state.languageCode);
  }

  void _onSectionToggled(
    AboutUsSectionToggled event,
    Emitter<AboutUsState> emit,
  ) {
    final sectionExists = state.content?.sections.any(
      (section) => section.key == event.sectionKey,
    );
    if (sectionExists != true) return;

    final expanded = {...state.expandedSectionKeys};
    if (!expanded.add(event.sectionKey)) {
      expanded.remove(event.sectionKey);
    }

    emit(state.copyWith(expandedSectionKeys: expanded));
  }

  Future<void> _load(Emitter<AboutUsState> emit, String languageCode) async {
    emit(
      state.copyWith(
        status: AboutUsStatus.loading,
        languageCode: languageCode,
        errorMessage: '',
      ),
    );

    try {
      final content = await _apiService.aboutUs(languageCode: languageCode);
      emit(
        state.copyWith(
          status: AboutUsStatus.ready,
          content: content,
          languageCode: languageCode,
          errorMessage: '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AboutUsStatus.failure,
          languageCode: languageCode,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }
}
