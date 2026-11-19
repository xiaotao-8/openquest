import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One user goal with simple numeric progress (current / target).
/// Goals are created by the user only — the store starts empty.
class GoalItem {
  final String id;
  final String title;
  final double current;
  final double target;

  /// Optional link to the group chat / conversation this goal belongs
  /// to. Progress rows name that conversation in small text and tapping
  /// the row opens it. Null = not linked.
  final String? conversationId;

  const GoalItem({
    required this.id,
    required this.title,
    required this.current,
    required this.target,
    this.conversationId,
  });

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0).toDouble();

  GoalItem copyWith({
    String? title,
    double? current,
    double? target,
    String? conversationId,
    bool clearConversation = false,
  }) {
    return GoalItem(
      id: id,
      title: title ?? this.title,
      current: current ?? this.current,
      target: target ?? this.target,
      conversationId: clearConversation
          ? null
          : (conversationId ?? this.conversationId),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'current': current,
    'target': target,
    if (conversationId != null) 'conversationId': conversationId,
  };

  factory GoalItem.fromJson(Map<String, dynamic> json) => GoalItem(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    current: (json['current'] as num?)?.toDouble() ?? 0,
    target: (json['target'] as num?)?.toDouble() ?? 1,
    conversationId: json['conversationId']?.toString(),
  );
}

/// User goals, persisted locally. Feeds both the Goals tab and the
/// sidebar goal section — one store, one source of truth.
class GoalsStore extends ChangeNotifier {
  static const _prefsKey = 'openquest.goals.v1';

  List<GoalItem> _goals = const [];
  bool _loaded = false;

  List<GoalItem> get goals => _goals;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _goals = [
            for (final e in list)
              if (e is Map) GoalItem.fromJson(e.cast<String, dynamic>()),
          ];
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final g in _goals) g.toJson()]),
      );
    } catch (_) {}
  }

  Future<void> addGoal({
    required String title,
    required double target,
    String? conversationId,
  }) async {
    final goal = GoalItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      current: 0,
      target: target <= 0 ? 1 : target,
      conversationId: conversationId,
    );
    _goals = [..._goals, goal];
    notifyListeners();
    await _persist();
  }

  Future<void> updateGoal(
    String id, {
    String? title,
    double? current,
    double? target,
    String? conversationId,
    bool clearConversation = false,
  }) async {
    _goals = [
      for (final g in _goals)
        if (g.id == id)
          g.copyWith(
            title: title,
            current: current,
            target: target,
            conversationId: conversationId,
            clearConversation: clearConversation,
          )
        else
          g,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> removeGoal(String id) async {
    _goals = [
      for (final g in _goals)
        if (g.id != id) g,
    ];
    notifyListeners();
    await _persist();
  }
}
