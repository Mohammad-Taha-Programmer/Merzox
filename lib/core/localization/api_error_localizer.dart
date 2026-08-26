import 'package:easy_localization/easy_localization.dart';

const apiErrorLocalizationPrefix = 'apiErrors.';

String localizeApiErrorOrRaw(String message) {
  if (!message.startsWith(apiErrorLocalizationPrefix)) {
    return message;
  }

  return message.tr();
}
