import 'package:merzox/services/api_service.dart';

sealed class ProfileEditEvent {
  const ProfileEditEvent();
}

final class ProfileEditStarted extends ProfileEditEvent {
  const ProfileEditStarted();
}

final class ProfileEditSubmitted extends ProfileEditEvent {
  final String? name;
  final String? gender;
  final String address;
  final List<ContactEmail> emails;
  final List<ContactPhone> phones;

  const ProfileEditSubmitted({
    required this.name,
    required this.gender,
    required this.address,
    required this.emails,
    required this.phones,
  });
}
