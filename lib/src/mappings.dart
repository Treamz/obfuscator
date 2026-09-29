/// Record of an obfuscated declaration or reference, written to the `mappings.json` file.
///
class Mapping {
  /// Creates a mapping of the [id] declaration or reference to its [replacementId].
  ///
  Mapping({
    required this.filePath,
    required this.id,
    required this.replacementId,
    required this.parentId,
    required this.offset,
    required this.referenceMappings,
  });

  /// Path of the file containing the declaration or reference.
  ///
  final String filePath;

  /// Original identifier.
  ///
  final String? id;

  /// Obfuscated identifier.
  ///
  final String replacementId;

  /// Name of the class declaring the field, if the mapping describes a field.
  ///
  final String? parentId;

  /// Offset of the identifier within the original file contents.
  ///
  final int offset;

  /// Mappings of the references to the declaration, or `null` if this mapping describes a reference.
  ///
  final List<Mapping>? referenceMappings;

  /// Converts the mapping to a JSON-encodable map.
  ///
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'id': id,
      'replacementId': replacementId,
      'parentId': parentId,
      'offset': offset,
      'referenceMappings': referenceMappings?.map(
        (referenceMapping) {
          return referenceMapping.toJson();
        },
      ).toList(),
    };
  }
}
