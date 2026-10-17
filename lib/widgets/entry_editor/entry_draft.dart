import 'package:flutter/foundation.dart';

import '../../utils/fuzzy_date.dart';
import '../../utils/score_utils.dart';

export '../../utils/fuzzy_date.dart' show FuzzyDate;

/// AniList list statuses, in the order the editor offers them.
const entryStatuses = ['CURRENT', 'COMPLETED', 'PLANNING', 'PAUSED', 'DROPPED', 'REPEATING'];

/// Translation key of an AniList list status, worded for reading on manga.
String entryStatusKey(String status, {required bool manga}) => switch (status) {
      'CURRENT' => manga ? 'reading' : 'watching',
      'REPEATING' => manga ? 'rereading' : 'rewatching',
      'COMPLETED' => 'completed',
      'PAUSED' => 'on_hold',
      'DROPPED' => 'dropped',
      _ => manga ? 'plan_to_read' : 'plan_to_watch',
    };

/// The editable fields of a list entry, named as in AniList's `MediaList`.
enum EntryField {
  status,
  progress,
  progressVolumes,
  score,
  repeat,
  private,
  hiddenFromStatusLists,
  notes,
  customLists,
  startedAt,
  completedAt,
}

/// The arguments for `AniListService.saveListEntry` that changed; null
/// fields are left out so AniList keeps them as they are.
@immutable
class EntryChanges {
  const EntryChanges({
    this.status,
    this.progress,
    this.progressVolumes,
    this.scoreRaw,
    this.repeat,
    this.private,
    this.hiddenFromStatusLists,
    this.notes,
    this.customLists,
    this.startedAt,
    this.completedAt,
  });

  final String? status;
  final int? progress;
  final int? progressVolumes;
  final int? scoreRaw;
  final int? repeat;
  final bool? private;
  final bool? hiddenFromStatusLists;
  final String? notes;
  final List<String>? customLists;
  final Map<String, int?>? startedAt;
  final Map<String, int?>? completedAt;

  bool get isEmpty => toArguments().isEmpty;

  Map<String, Object> toArguments() => {
        'status': ?status,
        'progress': ?progress,
        'progressVolumes': ?progressVolumes,
        'scoreRaw': ?scoreRaw,
        'repeat': ?repeat,
        'private': ?private,
        'hiddenFromStatusLists': ?hiddenFromStatusLists,
        'notes': ?notes,
        'customLists': ?customLists,
        'startedAt': ?startedAt,
        'completedAt': ?completedAt,
      };
}

/// An immutable snapshot of a list entry being edited. The score is kept on
/// AniList's 0–10 scale (as read with `POINT_10_DECIMAL`) whatever the
/// user's score format. Fields in [unknown] weren't in the data the editor
/// opened with; they are shown as unknown and never sent.
@immutable
class EntryDraft {
  const EntryDraft({
    required this.status,
    this.progress = 0,
    this.progressVolumes = 0,
    this.score = 0,
    this.repeat = 0,
    this.private = false,
    this.hiddenFromStatusLists = false,
    this.notes = '',
    this.customLists = const {},
    this.startedAt = FuzzyDate.empty,
    this.completedAt = FuzzyDate.empty,
    this.unknown = const {},
    Map<EntryField, Object> autoFilled = const {},
  }) : _autoFilled = autoFilled;

  /// A media that isn't in the list yet, planned by default like on AniList.
  factory EntryDraft.newEntry({String status = 'PLANNING'}) => EntryDraft(status: status);

  /// Reads an AniList `MediaList` map. Keys the map doesn't have at all
  /// (e.g. data cached before these fields were fetched) become [unknown].
  factory EntryDraft.fromEntry(Map<String, dynamic> entry) {
    final rawLists = entry['customLists'];
    return EntryDraft(
      status: entry['status'] as String? ?? 'PLANNING',
      progress: (entry['progress'] as num?)?.toInt() ?? 0,
      progressVolumes: (entry['progressVolumes'] as num?)?.toInt() ?? 0,
      score: (entry['score'] as num?)?.toDouble() ?? 0,
      repeat: (entry['repeat'] as num?)?.toInt() ?? 0,
      private: entry['private'] == true,
      hiddenFromStatusLists: entry['hiddenFromStatusLists'] == true,
      notes: entry['notes'] as String? ?? '',
      customLists: Set.unmodifiable({
        if (rawLists is Map)
          for (final MapEntry(:key, :value) in rawLists.entries)
            if (value == true) '$key',
      }),
      startedAt: FuzzyDate.fromJson(entry['startedAt']),
      completedAt: FuzzyDate.fromJson(entry['completedAt']),
      unknown: Set.unmodifiable({
        for (final field in EntryField.values)
          if (!entry.containsKey(field.name)) field,
      }),
    );
  }

  final String status;
  final int progress;
  final int progressVolumes;
  final double score;
  final int repeat;
  final bool private;
  final bool hiddenFromStatusLists;
  final String notes;
  final Set<String> customLists;
  final FuzzyDate startedAt;
  final FuzzyDate completedAt;
  final Set<EntryField> unknown;
  // Values a status change replaced, so changing the status again can put
  // them back. A field the user edits afterwards is dropped from here.
  final Map<EntryField, Object> _autoFilled;

  bool isKnown(EntryField field) => !unknown.contains(field);

  EntryDraft copyWith({
    double? score,
    int? repeat,
    bool? private,
    bool? hiddenFromStatusLists,
    String? notes,
    Set<String>? customLists,
  }) =>
      _copy(
        score: score,
        repeat: repeat,
        private: private,
        hiddenFromStatusLists: hiddenFromStatusLists,
        notes: notes,
        customLists: customLists == null ? null : Set.unmodifiable(customLists),
      );

  EntryDraft withProgress(int progress) =>
      _copy(progress: progress, autoFilled: _without(EntryField.progress));

  EntryDraft withProgressVolumes(int volumes) =>
      _copy(progressVolumes: volumes, autoFilled: _without(EntryField.progressVolumes));

  EntryDraft withStartedAt(FuzzyDate date) =>
      _copy(startedAt: date, autoFilled: _without(EntryField.startedAt));

  EntryDraft withCompletedAt(FuzzyDate date) =>
      _copy(completedAt: date, autoFilled: _without(EntryField.completedAt));

  /// Changes the status the way AniList does: watching/reading something
  /// without a start date starts it [today], and completing it finishes it
  /// today with the progress (and volumes) at the totals. Dates the user
  /// already has are never replaced, and whatever the previous status
  /// filled in is undone first.
  EntryDraft withStatus(
    String status, {
    required DateTime today,
    int? totalProgress,
    int? totalVolumes,
  }) {
    if (status == this.status) return this;
    final base = _undoAutoFill();
    final todayDate = FuzzyDate.fromDateTime(today);
    final filled = <EntryField, Object>{};
    var startedAt = base.startedAt;
    var completedAt = base.completedAt;
    var progress = base.progress;
    var volumes = base.progressVolumes;
    if (status == 'CURRENT' && isKnown(EntryField.startedAt) && startedAt.isEmpty) {
      filled[EntryField.startedAt] = startedAt;
      startedAt = todayDate;
    }
    if (status == 'COMPLETED') {
      if (isKnown(EntryField.completedAt) && completedAt.isEmpty) {
        filled[EntryField.completedAt] = completedAt;
        completedAt = todayDate;
      }
      if (totalProgress != null && isKnown(EntryField.progress) && progress < totalProgress) {
        filled[EntryField.progress] = progress;
        progress = totalProgress;
      }
      if (totalVolumes != null && isKnown(EntryField.progressVolumes) && volumes < totalVolumes) {
        filled[EntryField.progressVolumes] = volumes;
        volumes = totalVolumes;
      }
    }
    return base._copy(
      status: status,
      startedAt: startedAt,
      completedAt: completedAt,
      progress: progress,
      progressVolumes: volumes,
      autoFilled: filled,
    );
  }

  /// What changed since [initial]. A [isNew] entry always sends its status,
  /// since AniList has nothing to keep yet.
  EntryChanges changesFrom(EntryDraft initial, {required bool isNew}) {
    bool changed(EntryField field, Object a, Object b) => isKnown(field) && a != b;
    final trimmedNotes = notes.trim();
    final sortedLists = customLists.toList()..sort();
    return EntryChanges(
      status: isNew || changed(EntryField.status, status, initial.status) ? status : null,
      progress: changed(EntryField.progress, progress, initial.progress) ? progress : null,
      progressVolumes: changed(EntryField.progressVolumes, progressVolumes, initial.progressVolumes)
          ? progressVolumes
          : null,
      scoreRaw: changed(EntryField.score, toRawScore(score), toRawScore(initial.score))
          ? toRawScore(score)
          : null,
      repeat: changed(EntryField.repeat, repeat, initial.repeat) ? repeat : null,
      private: changed(EntryField.private, private, initial.private) ? private : null,
      hiddenFromStatusLists: changed(EntryField.hiddenFromStatusLists, hiddenFromStatusLists,
              initial.hiddenFromStatusLists)
          ? hiddenFromStatusLists
          : null,
      notes: changed(EntryField.notes, trimmedNotes, initial.notes.trim()) ? trimmedNotes : null,
      customLists: isKnown(EntryField.customLists) && !setEquals(customLists, initial.customLists)
          ? sortedLists
          : null,
      startedAt: changed(EntryField.startedAt, startedAt, initial.startedAt) ? startedAt.toInput() : null,
      completedAt:
          changed(EntryField.completedAt, completedAt, initial.completedAt) ? completedAt.toInput() : null,
    );
  }

  EntryDraft _undoAutoFill() {
    if (_autoFilled.isEmpty) return this;
    return _copy(
      startedAt: _autoFilled[EntryField.startedAt] as FuzzyDate?,
      completedAt: _autoFilled[EntryField.completedAt] as FuzzyDate?,
      progress: _autoFilled[EntryField.progress] as int?,
      progressVolumes: _autoFilled[EntryField.progressVolumes] as int?,
      autoFilled: const {},
    );
  }

  Map<EntryField, Object> _without(EntryField field) =>
      Map.unmodifiable({..._autoFilled}..remove(field));

  EntryDraft _copy({
    String? status,
    int? progress,
    int? progressVolumes,
    double? score,
    int? repeat,
    bool? private,
    bool? hiddenFromStatusLists,
    String? notes,
    Set<String>? customLists,
    FuzzyDate? startedAt,
    FuzzyDate? completedAt,
    Map<EntryField, Object>? autoFilled,
  }) =>
      EntryDraft(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        progressVolumes: progressVolumes ?? this.progressVolumes,
        score: score ?? this.score,
        repeat: repeat ?? this.repeat,
        private: private ?? this.private,
        hiddenFromStatusLists: hiddenFromStatusLists ?? this.hiddenFromStatusLists,
        notes: notes ?? this.notes,
        customLists: customLists ?? this.customLists,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        unknown: unknown,
        autoFilled: autoFilled ?? _autoFilled,
      );
}
