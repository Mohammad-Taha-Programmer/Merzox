final RegExp _mongoObjectIdPattern = RegExp(r'^[a-fA-F0-9]{24}$');

bool isMongoBackedEntityId(String value) {
  return _mongoObjectIdPattern.hasMatch(value.trim());
}
