import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/about_us/bloc/about_us_bloc.dart';
import 'package:merzox/features/about_us/bloc/about_us_event.dart';
import 'package:merzox/features/about_us/bloc/about_us_state.dart';
import 'package:merzox/services/api_service.dart';

class _FakeApiService extends ApiService {
  String? requestedLanguageCode;

  @override
  Future<AboutUsApiModel> aboutUs({required String languageCode}) async {
    requestedLanguageCode = languageCode;
    return AboutUsApiModel(
      pageTitle: languageCode == 'en' ? 'About us' : 'من نحن',
      appLabel: languageCode == 'en' ? 'Application' : 'تطبيق',
      appName: 'MERZOX',
      introduction: 'Introduction',
      sections: const [
        AboutUsSectionApiModel(
          key: 'how-it-works',
          title: 'How it works',
          content: 'Section content',
        ),
      ],
      updatedAt: null,
    );
  }
}

void main() {
  test('loads localized About Us content through the API service', () async {
    final apiService = _FakeApiService();
    final bloc = AboutUsBloc(apiService: apiService);
    addTearDown(bloc.close);

    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AboutUsState>().having(
          (state) => state.status,
          'status',
          AboutUsStatus.loading,
        ),
        isA<AboutUsState>()
            .having((state) => state.status, 'status', AboutUsStatus.ready)
            .having(
              (state) => state.content?.pageTitle,
              'page title',
              'About us',
            ),
      ]),
    );

    bloc.add(const AboutUsStarted('en'));
    await expectation;
    expect(apiService.requestedLanguageCode, 'en');
  });

  test('toggles accordion expansion in BLoC state', () async {
    final bloc = AboutUsBloc(apiService: _FakeApiService());
    addTearDown(bloc.close);
    bloc.add(const AboutUsStarted('ar'));
    await bloc.stream.firstWhere(
      (state) => state.status == AboutUsStatus.ready,
    );

    final expandedState = bloc.stream.firstWhere(
      (state) => state.expandedSectionKeys.contains('how-it-works'),
    );
    bloc.add(const AboutUsSectionToggled('how-it-works'));
    expect((await expandedState).expandedSectionKeys, contains('how-it-works'));

    final collapsedState = bloc.stream.firstWhere(
      (state) => !state.expandedSectionKeys.contains('how-it-works'),
    );
    bloc.add(const AboutUsSectionToggled('how-it-works'));
    expect(
      (await collapsedState).expandedSectionKeys,
      isNot(contains('how-it-works')),
    );
  });
}
