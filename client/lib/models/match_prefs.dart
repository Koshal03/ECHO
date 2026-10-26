/// One selectable option (a language, an interest or a region). The server owns the list.
class MatchOption {
  final String id;
  final String name;
  const MatchOption(this.id, this.name);

  factory MatchOption.fromJson(Map<String, dynamic> j) => MatchOption(j['id'].toString(), (j['name'] ?? j['id']).toString());
}

/// What the person shares about themselves, and (once Premium Filters are unlocked) what
/// the matchmaker should look for. Language and region are strict filters; interests only
/// give priority. A match is never guaranteed.
class MatchPrefs {
  final List<String> languages;
  final List<String> interests;
  final String region; // 'any' or a 2-letter country code
  final bool filtersOn;

  const MatchPrefs({
    this.languages = const [],
    this.interests = const [],
    this.region = 'any',
    this.filtersOn = true,
  });

  factory MatchPrefs.fromJson(Map<String, dynamic> j) => MatchPrefs(
        languages: List<String>.from((j['languages'] as List? ?? const []).map((e) => e.toString())),
        interests: List<String>.from((j['interests'] as List? ?? const []).map((e) => e.toString())),
        region: (j['region'] ?? 'any').toString(),
        filtersOn: j['filtersOn'] != false,
      );

  Map<String, dynamic> toJson() => {
        'languages': languages,
        'interests': interests,
        'region': region,
        'filtersOn': filtersOn,
      };

  MatchPrefs copyWith({List<String>? languages, List<String>? interests, String? region, bool? filtersOn}) => MatchPrefs(
        languages: languages ?? this.languages,
        interests: interests ?? this.interests,
        region: region ?? this.region,
        filtersOn: filtersOn ?? this.filtersOn,
      );
}
