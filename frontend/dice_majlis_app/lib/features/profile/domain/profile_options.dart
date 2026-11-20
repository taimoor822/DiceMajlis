/// What a profile may hold, as the server allows it.
class ProfileOptions {
  const ProfileOptions({
    required this.avatars,
    required this.languages,
    required this.maxLanguages,
    required this.nameMinLength,
    required this.nameMaxLength,
  });

  factory ProfileOptions.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? list) => [
      for (final item in list is List ? list : const []) item.toString(),
    ];
    int number(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    final languages = strings(json['languages']);
    return ProfileOptions(
      avatars: strings(json['avatars']),
      languages: languages,
      maxLanguages: number(json['max_languages'], languages.length),
      nameMinLength: number(json['name_min_length'], 1),
      nameMaxLength: number(json['name_max_length'], 30),
    );
  }

  /// Keys of the built-in avatar pictures.
  final List<String> avatars;

  /// Spoken-language codes a player can show.
  final List<String> languages;
  final int maxLanguages;
  final int nameMinLength;
  final int nameMaxLength;
}
