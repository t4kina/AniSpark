import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/media_list_store.dart';
import '../../providers/settings_provider.dart';
import '../../services/anilist_service.dart';
import '../../services/api_cache.dart';
import '../../services/auth_service.dart';
import '../../utils/score_utils.dart';
import '../../utils/translations.dart';
import 'entry_draft.dart';
import 'entry_editor_api.dart';
import 'entry_editor_fields.dart';
import 'score_scale.dart';

export 'entry_editor_api.dart' show EditorMedia;

/// What the entry editor changed, for callers that refresh their own data.
enum EntryEditorResult { saved, removed }

/// Opens the full list entry editor for [media].
///
/// [entry] is the viewer's AniList `MediaList` map when the caller has one;
/// fields it lacks are looked up first (or, if that fails, shown as unknown
/// and left as they are). Set [entryKnown] to false when the caller doesn't
/// know whether the media is in the list (e.g. Discover): the editor looks
/// it up and opens a media that isn't listed as a new Planning entry.
///
/// Saving sends only the changed fields and updates the shared
/// [MediaListStore]; [onChanged] then runs even if the sheet was closed
/// meanwhile, so callers can refresh their own data.
Future<void> showEntryEditor(
  BuildContext context, {
  required EditorMedia media,
  Map<String, dynamic>? entry,
  bool entryKnown = true,
  ValueChanged<EntryEditorResult>? onChanged,
  AniListService? service,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => EntryEditorSheet(
        media: media,
        entry: entry,
        entryKnown: entryKnown,
        onChanged: onChanged,
        service: service ?? AniListService(),
      ),
    );

/// Asks before deleting a list entry.
Future<bool> confirmEntryRemoval(BuildContext context, String lang) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('remove_from_list', lang)),
      content: Text(tr('remove_from_list_confirm', lang)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(tr('cancel', lang)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(tr('remove', lang), style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The editor's content; open it with [showEntryEditor].
class EntryEditorSheet extends StatefulWidget {
  const EntryEditorSheet({
    super.key,
    required this.media,
    required this.service,
    this.entry,
    this.entryKnown = true,
    this.onChanged,
    this.today = DateTime.now,
  });

  final EditorMedia media;
  final AniListService service;
  final Map<String, dynamic>? entry;
  final bool entryKnown;
  final ValueChanged<EntryEditorResult>? onChanged;

  /// The day status changes fill in as start or finish date.
  final DateTime Function() today;

  @override
  State<EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends State<EntryEditorSheet> {
  late EditorMedia _media = widget.media;
  final _notes = TextEditingController();
  EntryDraft? _initial;
  EntryDraft? _draft;
  int? _entryId;
  bool _lookingUp = false;
  bool _lookupFailed = false;
  bool _busy = false;
  String? _error;
  List<String> _customListNames = const [];
  String? _customListsType;

  bool get _isNew => _entryId == null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null || widget.entryKnown) _useEntry(entry);
    final incomplete = _initial?.unknown.isNotEmpty ?? true;
    if (incomplete && context.read<AuthService>().token != null) {
      _lookingUp = true;
      unawaited(_lookUp());
    } else {
      _lookupFailed = _initial == null;
    }
    _loadCustomListNames();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _useEntry(Map<String, dynamic>? entry) {
    final draft = entry == null ? EntryDraft.newEntry() : EntryDraft.fromEntry(entry);
    _initial = draft;
    _draft = draft;
    _entryId = (entry?['id'] as num?)?.toInt();
    _notes.text = draft.notes;
  }

  /// Reads the current entry so every field starts from AniList's values.
  Future<void> _lookUp() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;
    try {
      final (media, entry) = await fetchEditorEntry(widget.service, _media, token);
      if (!mounted) return;
      setState(() {
        _media = media;
        _useEntry(entry);
        _lookingUp = false;
        _lookupFailed = false;
      });
      _loadCustomListNames();
    } on Exception catch (e) {
      debugPrint('[EntryEditor] Looking up ${_media.id} failed: $e');
      if (!mounted) return;
      // What the caller passed is still editable; unknown fields stay locked.
      setState(() {
        _lookingUp = false;
        _lookupFailed = _initial == null;
      });
    }
  }

  void _retryLookUp() {
    setState(() {
      _lookingUp = true;
      _lookupFailed = false;
    });
    unawaited(_lookUp());
  }

  void _loadCustomListNames() {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    final token = auth.token;
    final type = _media.type;
    if (userId == null || token == null || _customListsType == type) return;
    _customListsType = type;
    unawaited(loadCustomListNames(
      cache: context.read<ApiCache>(),
      service: widget.service,
      userId: userId,
      type: type,
      token: token,
      onData: (names) {
        if (mounted && _customListsType == type) setState(() => _customListNames = names);
      },
    ));
  }

  void _update(EntryDraft Function(EntryDraft draft) change) {
    final draft = _draft;
    if (draft == null || !mounted) return;
    setState(() {
      _draft = change(draft);
      _error = null;
    });
  }

  void _changeStatus(String status) => _update((draft) => draft.withStatus(
        status,
        today: widget.today(),
        totalProgress: _media.totalProgress,
        totalVolumes: _media.totalVolumes,
      ));

  Future<void> _save() async {
    final draft = _draft;
    final initial = _initial;
    if (draft == null || initial == null || _busy) return;
    final settings = context.read<SettingsProvider>();
    final lang = settings.language;
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (token == null) {
      setState(() => _error = tr('connect_anilist', lang));
      return;
    }
    final navigator = Navigator.of(context);
    final changes = draft.copyWith(notes: _notes.text).changesFrom(initial, isNew: _isNew);
    if (changes.isEmpty) {
      navigator.pop();
      return;
    }
    final store = context.read<MediaListStore>();
    final messenger = ScaffoldMessenger.of(context);
    final title = settings.resolveTitle(_media.title);
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await saveEntryChanges(
      service: widget.service,
      store: store,
      media: _media,
      changes: changes,
      token: token,
      userId: auth.user?['id'] as int?,
    );
    if (saved == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('save_failed', lang);
        });
      }
      return;
    }
    widget.onChanged?.call(EntryEditorResult.saved);
    if (mounted) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(trf('detail_saved', lang, {'title': title}))));
  }

  Future<void> _remove() async {
    final entryId = _entryId;
    if (entryId == null || _busy) return;
    final lang = context.read<SettingsProvider>().language;
    final token = context.read<AuthService>().token;
    if (token == null) return;
    final store = context.read<MediaListStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!await confirmEntryRemoval(context, lang) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await removeEntry(
      service: widget.service,
      store: store,
      media: _media,
      entryId: entryId,
      token: token,
    );
    if (!ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('remove_failed', lang);
        });
      }
      return;
    }
    widget.onChanged?.call(EntryEditorResult.removed);
    if (mounted) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(tr('removed_from_list', lang))));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    final title = context.select<SettingsProvider, String>((s) => s.resolveTitle(_media.title));
    final scale = ScoreScale.of(context.select<AuthService, String?>((a) => scoreFormatOf(a.user)));
    final draft = _draft;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final Widget body;
    if (_lookingUp) {
      body = const Padding(
        key: ValueKey('entry-editor-loading'),
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_lookupFailed || draft == null) {
      body = _LookupError(lang: lang, onRetry: _retryLookUp);
    } else {
      body = _form(draft, lang, scale);
    }
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            _Header(
              title: title,
              coverUrl: _media.coverUrl,
              // Unknown until the lookup says whether the media is listed.
              subtitle: draft == null || _lookingUp
                  ? ''
                  : tr(_isNew ? 'add_to_list' : 'tooltip_edit_entry', lang),
            ),
            const Divider(height: 1),
            Flexible(child: body),
            if (draft != null && !_lookingUp && !_lookupFailed)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 12 + (keyboardOpen ? 0 : MediaQuery.paddingOf(context).bottom)),
                child: _actions(lang),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actions(String lang) {
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Text(error, key: const ValueKey('entry-editor-error'), style: const TextStyle(color: Colors.red, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('entry-editor-save'),
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(tr('save', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (!_isNew) ...[
              const SizedBox(width: 12),
              IconButton(
                key: const ValueKey('entry-editor-remove'),
                tooltip: tr('remove_from_list', lang),
                onPressed: _busy ? null : _remove,
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _form(EntryDraft draft, String lang, ScoreScale scale) {
    final manga = _media.isManga;
    final total = _media.totalProgress;
    final totalVolumes = _media.totalVolumes;
    final unit = tr(manga ? 'detail_unit_ch' : 'detail_unit_ep', lang);
    final listNames = [
      ..._customListNames,
      for (final name in _initial?.customLists ?? const <String>{})
        if (!_customListNames.contains(name)) name,
    ];
    Widget ifKnown(EntryField field, Widget child) => draft.isKnown(field) ? child : const UnknownValue();
    const gap = SizedBox(height: 18);
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('entry-editor-form'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabel(tr('status', lang)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final status in entryStatuses)
                ChoiceChip(
                  key: ValueKey('entry-editor-status-$status'),
                  label: Text(tr(entryStatusKey(status, manga: manga), lang)),
                  selected: draft.status == status,
                  showCheckmark: false,
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(fontSize: 12, color: draft.status == status ? Colors.white : null),
                  onSelected: draft.isKnown(EntryField.status) ? (_) => _changeStatus(status) : null,
                ),
            ],
          ),
          gap,
          EditorLabel(tr('progress', lang)),
          ifKnown(
            EntryField.progress,
            NumberStepper(
              key: const ValueKey('entry-editor-progress'),
              value: draft.progress,
              max: total,
              suffix: total != null ? '/ $total $unit' : unit,
              lang: lang,
              onChanged: (value) => _update((d) => d.withProgress(value.toInt())),
            ),
          ),
          if (manga) ...[
            gap,
            EditorLabel(tr('editor_volumes', lang)),
            ifKnown(
              EntryField.progressVolumes,
              NumberStepper(
                key: const ValueKey('entry-editor-volumes'),
                value: draft.progressVolumes,
                max: totalVolumes,
                suffix: totalVolumes != null ? '/ $totalVolumes' : null,
                lang: lang,
                onChanged: (value) => _update((d) => d.withProgressVolumes(value.toInt())),
              ),
            ),
          ],
          gap,
          EditorLabel(tr('list_score', lang)),
          ifKnown(
            EntryField.score,
            ScoreInput(
              key: const ValueKey('entry-editor-score'),
              scale: scale,
              score: draft.score,
              lang: lang,
              onChanged: (score) => _update((d) => d.copyWith(score: score)),
            ),
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EntryDateField(
                  key: const ValueKey('entry-editor-started'),
                  label: tr('editor_start_date', lang),
                  date: draft.startedAt,
                  enabled: draft.isKnown(EntryField.startedAt),
                  lang: lang,
                  onChanged: (date) => _update((d) => d.withStartedAt(date)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EntryDateField(
                  key: const ValueKey('entry-editor-completed'),
                  label: tr('editor_finish_date', lang),
                  date: draft.completedAt,
                  enabled: draft.isKnown(EntryField.completedAt),
                  lang: lang,
                  onChanged: (date) => _update((d) => d.withCompletedAt(date)),
                ),
              ),
            ],
          ),
          gap,
          EditorLabel(tr(manga ? 'editor_rereads' : 'editor_rewatches', lang)),
          ifKnown(
            EntryField.repeat,
            NumberStepper(
              key: const ValueKey('entry-editor-repeat'),
              value: draft.repeat,
              lang: lang,
              onChanged: (value) => _update((d) => d.copyWith(repeat: value.toInt())),
            ),
          ),
          if (listNames.isNotEmpty) ...[
            gap,
            EditorLabel(tr('detail_custom_lists', lang)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in listNames)
                  FilterChip(
                    key: ValueKey('entry-editor-list-$name'),
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    selected: draft.customLists.contains(name),
                    onSelected: draft.isKnown(EntryField.customLists)
                        ? (selected) => _update((d) => d.copyWith(
                              customLists: selected
                                  ? {...d.customLists, name}
                                  : {...d.customLists}.difference({name}),
                            ))
                        : null,
                  ),
              ],
            ),
          ],
          gap,
          EditorLabel(tr('detail_notes', lang)),
          TextField(
            key: const ValueKey('entry-editor-notes'),
            controller: _notes,
            enabled: draft.isKnown(EntryField.notes),
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: tr('detail_notes_hint', lang),
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          EntrySwitchRow(
            key: const ValueKey('entry-editor-private'),
            label: tr('editor_private', lang),
            hint: tr('editor_private_hint', lang),
            value: draft.private,
            onChanged: draft.isKnown(EntryField.private)
                ? (value) => _update((d) => d.copyWith(private: value))
                : null,
          ),
          EntrySwitchRow(
            key: const ValueKey('entry-editor-hidden'),
            label: tr('editor_hidden', lang),
            hint: tr('editor_hidden_hint', lang),
            value: draft.hiddenFromStatusLists,
            onChanged: draft.isKnown(EntryField.hiddenFromStatusLists)
                ? (value) => _update((d) => d.copyWith(hiddenFromStatusLists: value))
                : null,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, required this.coverUrl});

  final String title;
  final String subtitle;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final cover = coverUrl;
    final placeholder = Container(
      width: 44,
      height: 62,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: cover == null
                ? placeholder
                : CachedNetworkImage(
                    imageUrl: cover,
                    width: 44,
                    height: 62,
                    fit: BoxFit.cover,
                    memCacheWidth: 88,
                    placeholder: (_, _) => placeholder,
                    errorWidget: (_, _, _) => placeholder,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LookupError extends StatelessWidget {
  const _LookupError({required this.lang, required this.onRetry});

  final String lang;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('entry-editor-lookup-error'),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(tr('load_error', lang), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );
}
