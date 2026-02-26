/// Night ("Sleep Vacation") window and behavior level.
/// Stored in SharedPreferences; shared with Sleep Lock UI.
class NightModeConfig {
  final bool enabled;
  final String startTime; // "HH:mm" 24h
  final String endTime;   // "HH:mm" 24h
  final NightBehaviorLevel behaviorLevel;
  final int excellentMaxRequests;

  const NightModeConfig({
    this.enabled = false,
    this.startTime = '22:00',
    this.endTime = '07:00',
    this.behaviorLevel = NightBehaviorLevel.good,
    this.excellentMaxRequests = 3,
  });

  NightModeConfig copyWith({
    bool? enabled,
    String? startTime,
    String? endTime,
    NightBehaviorLevel? behaviorLevel,
    int? excellentMaxRequests,
  }) {
    return NightModeConfig(
      enabled: enabled ?? this.enabled,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      behaviorLevel: behaviorLevel ?? this.behaviorLevel,
      excellentMaxRequests: excellentMaxRequests ?? this.excellentMaxRequests,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'startTime': startTime,
        'endTime': endTime,
        'behaviorLevel': behaviorLevel.name,
        'excellentMaxRequests': excellentMaxRequests,
      };

  static NightModeConfig fromJson(Map<String, dynamic> json) {
    return NightModeConfig(
      enabled: json['enabled'] as bool? ?? false,
      startTime: json['startTime'] as String? ?? '22:00',
      endTime: json['endTime'] as String? ?? '07:00',
      behaviorLevel: _parseBehavior(json['behaviorLevel'] as String?),
      excellentMaxRequests: json['excellentMaxRequests'] as int? ?? 3,
    );
  }

  static NightBehaviorLevel _parseBehavior(String? s) {
    switch (s) {
      case 'disruptive':
        return NightBehaviorLevel.disruptive;
      case 'excellent':
        return NightBehaviorLevel.excellent;
      case 'good':
      default:
        return NightBehaviorLevel.good;
    }
  }
}

enum NightBehaviorLevel {
  disruptive, // 0 requests
  good,       // 1 request
  excellent,  // configurable (default 3)
}
