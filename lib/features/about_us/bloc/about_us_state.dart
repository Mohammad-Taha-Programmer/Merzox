import '../../../services/api_service.dart';

enum AboutUsStatus { initial, loading, ready, failure }

final class AboutUsState {
  final AboutUsStatus status;
  final AboutUsApiModel? content;
  final String languageCode;
  final Set<String> expandedSectionKeys;
  final String errorMessage;

  const AboutUsState({
    this.status = AboutUsStatus.initial,
    this.content,
    this.languageCode = 'ar',
    this.expandedSectionKeys = const {},
    this.errorMessage = '',
  });

  AboutUsState copyWith({
    AboutUsStatus? status,
    AboutUsApiModel? content,
    String? languageCode,
    Set<String>? expandedSectionKeys,
    String? errorMessage,
  }) {
    return AboutUsState(
      status: status ?? this.status,
      content: content ?? this.content,
      languageCode: languageCode ?? this.languageCode,
      expandedSectionKeys: expandedSectionKeys ?? this.expandedSectionKeys,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
