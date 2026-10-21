import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_edit_models.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 640.0;

/// Lato della rotella di caricamento.
const _spinnerSize = 28.0;

/// I campi che l'utente ha cambiato; `null` = non toccato (spec R §7.8).
class MetadataEdits {
  const MetadataEdits({
    this.name,
    this.originalTitle,
    this.sortName,
    this.tagline,
    this.overview,
    this.year,
    this.premiereDate,
    this.genres,
    this.rating,
    this.lockedFields = const {},
    this.unlockedFields = const {},
    this.lockAll = false,
  });

  final String? name;
  final String? originalTitle;
  final String? sortName;
  final String? tagline;
  final String? overview;
  final int? year;

  /// Solo la data: si scrive a mezzanotte UTC.
  final DateTime? premiereDate;
  final List<String>? genres;

  /// Il nome della classificazione; `''` = nessuna.
  final String? rating;

  /// I campi da bloccare, oltre a quelli già bloccati e a quelli cambiati.
  final Set<String> lockedFields;

  /// I campi sbloccati a mano: escono da `LockedFields` anche se cambiati.
  final Set<String> unlockedFields;
  final bool lockAll;
}

/// La `Map` da rimandare a Jellyfin: una copia di [original] con le sole chiavi
/// cambiate, perché `UpdateItem` riscrive anche `Tags`, `People`,
/// `ProviderIds`… e una `Map` parziale li cancellerebbe. [original] e le sue
/// liste non si toccano.
Map<String, dynamic> applyMetadataEdits(
  Map<String, dynamic> original,
  MetadataEdits edits,
) {
  final out = Map<String, dynamic>.of(original);
  final changed = <String>{};
  void put(String key, Object? value) {
    // Un campo bloccabile cambiato si blocca da sé.
    if (lockableFields.contains(key) &&
        jsonEncode(out[key]) != jsonEncode(value)) {
      changed.add(key);
    }
    out[key] = value;
  }

  if (edits.name != null) put('Name', edits.name);
  if (edits.originalTitle != null) put('OriginalTitle', edits.originalTitle);
  if (edits.sortName != null) put('ForcedSortName', edits.sortName);
  if (edits.tagline != null) {
    put('Taglines', edits.tagline!.isEmpty ? <String>[] : [edits.tagline!]);
  }
  if (edits.overview != null) put('Overview', edits.overview);
  if (edits.year != null) put('ProductionYear', edits.year);
  if (edits.premiereDate case final date?) {
    put(
      'PremiereDate',
      DateTime.utc(date.year, date.month, date.day).toIso8601String(),
    );
  }
  if (edits.genres != null) put('Genres', List<String>.of(edits.genres!));
  if (edits.rating != null) {
    put('OfficialRating', edits.rating!.isEmpty ? null : edits.rating);
  }
  final before = (original['LockedFields'] as List?)?.cast<String>() ?? const [];
  out['LockedFields'] = [
    for (final field in {...before, ...edits.lockedFields, ...changed})
      if (!edits.unlockedFields.contains(field)) field,
  ];
  out['LockData'] = edits.lockAll;
  return out;
}

/// Modifica i metadati di un titolo (spec R §7.8). Prende l'id e rilegge da
/// sola, così la apre anche il riquadro delle segnalazioni.
Future<void> showEditMetadataDialog(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) => showWfDialog<void>(
  context,
  maxWidth: _dialogWidth,
  semanticLabel: AppLocalizations.of(context).editMetadataTitle,
  builder: (_) => _EditMetadataDialog(itemId: itemId, kind: kind),
);

class _EditMetadataDialog extends ConsumerStatefulWidget {
  const _EditMetadataDialog({required this.itemId, required this.kind});

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_EditMetadataDialog> createState() =>
      _EditMetadataDialogState();
}

class _EditMetadataDialogState extends ConsumerState<_EditMetadataDialog> {
  final _name = TextEditingController();
  final _originalTitle = TextEditingController();
  final _sortName = TextEditingController();
  final _tagline = TextEditingController();
  final _overview = TextEditingController();
  final _year = TextEditingController();
  final _date = TextEditingController();
  final _newGenre = TextEditingController();

  Map<String, dynamic>? _original;
  List<ParentalRatingOption> _ratings = const [];
  List<String> _genres = [];
  String _rating = '';
  Set<String> _locks = {};

  /// I lucchetti girati a mano: la modifica del campo non li cambia più.
  final _manual = <String>{};
  bool _lockAll = false;
  bool _busy = false;
  String? _error;
  Object? _loadError;

  bool get _hasTagline =>
      widget.kind != ItemKind.episode && widget.kind != ItemKind.season;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _originalTitle,
      _sortName,
      _tagline,
      _overview,
      _year,
      _date,
      _newGenre,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(itemEditApiProvider);
    final userId = ref.read(currentUserIdProvider);
    try {
      final raw = await api.rawItem(userId, widget.itemId);
      final ratings = await api.parentalRatings(widget.itemId);
      if (!mounted) return;
      setState(() {
        _original = raw;
        _ratings = ratings;
        _name.text = raw['Name'] as String? ?? '';
        _originalTitle.text = raw['OriginalTitle'] as String? ?? '';
        _sortName.text = raw['ForcedSortName'] as String? ?? '';
        _tagline.text = _originalTagline(raw);
        _overview.text = raw['Overview'] as String? ?? '';
        _year.text = '${raw['ProductionYear'] ?? ''}';
        _date.text = _originalDate(raw);
        _genres = [...?(raw['Genres'] as List?)?.cast<String>()];
        _rating = raw['OfficialRating'] as String? ?? '';
        _locks = {...?(raw['LockedFields'] as List?)?.cast<String>()};
        _lockAll = raw['LockData'] == true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  static String _originalTagline(Map<String, dynamic> raw) {
    final taglines = raw['Taglines'];
    return taglines is List && taglines.isNotEmpty ? '${taglines.first}' : '';
  }

  static String _originalDate(Map<String, dynamic> raw) {
    final date = raw['PremiereDate'];
    return date is String && date.length >= 10 ? date.substring(0, 10) : '';
  }

  /// Un campo bloccabile cambiato si blocca, salvo che l'utente abbia girato
  /// a mano il suo lucchetto.
  void _touched(String key) {
    if (_manual.contains(key)) return;
    setState(() => _locks.add(key));
  }

  void _toggleLock(String key) => setState(() {
    _manual.add(key);
    if (!_locks.remove(key)) _locks.add(key);
  });

  void _addGenre() {
    final genre = _newGenre.text.trim();
    if (genre.isEmpty) return;
    _newGenre.clear();
    if (_genres.contains(genre)) return;
    setState(() => _genres = [..._genres, genre]);
    _touched('Genres');
  }

  /// L'anno e la data vuoti o non validi non si salvano (si lasciano com'erano).
  int? get _yearValue => int.tryParse(_year.text.trim());
  DateTime? get _dateValue {
    final text = _date.text.trim();
    final date = DateTime.tryParse(text);
    // tryParse sposta le date impossibili (30 febbraio -> 1 marzo): si rifiutano.
    if (date == null ||
        text.length < 10 ||
        text.substring(0, 10) !=
            '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}') {
      return null;
    }
    return date;
  }

  bool get _inputValid =>
      _name.text.trim().isNotEmpty &&
      (_year.text.trim().isEmpty || _yearValue != null) &&
      (_date.text.trim().isEmpty || _dateValue != null);

  MetadataEdits _edits(Map<String, dynamic> o) {
    String? text(TextEditingController c, String before) =>
        c.text == before ? null : c.text;
    final year = _yearValue;
    final date = _dateValue;
    final genres = (o['Genres'] as List?)?.cast<String>() ?? const [];
    return MetadataEdits(
      name: text(_name, o['Name'] as String? ?? ''),
      originalTitle: text(_originalTitle, o['OriginalTitle'] as String? ?? ''),
      sortName: text(_sortName, o['ForcedSortName'] as String? ?? ''),
      tagline: _hasTagline ? text(_tagline, _originalTagline(o)) : null,
      overview: text(_overview, o['Overview'] as String? ?? ''),
      year: year == o['ProductionYear'] ? null : year,
      premiereDate: _date.text.trim() == _originalDate(o) ? null : date,
      genres: jsonEncode(_genres) == jsonEncode(genres) ? null : _genres,
      rating: _rating == (o['OfficialRating'] as String? ?? '') ? null : _rating,
      lockedFields: _locks,
      unlockedFields: _manual.difference(_locks),
      lockAll: _lockAll,
    );
  }

  Future<void> _save() async {
    final original = _original;
    if (_busy || original == null || !_inputValid) return;
    final api = ref.read(itemEditApiProvider);
    // Letti prima dell'attesa: la finestra può chiudersi nel frattempo.
    final session = ref.read(sessionControllerProvider.notifier);
    final revision = ref.read(libraryRevisionProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.updateItem(
        widget.itemId,
        applyMetadataEdits(original, _edits(original)),
      );
      revision.bump();
      messenger?.showSnackBar(SnackBar(content: Text(l.editSaved)));
      if (mounted) navigator.pop();
    } on ForbiddenException {
      // Il permesso è cambiato: l'utente si rilegge.
      unawaited(session.refreshUser());
      if (mounted) setState(() => _error = l.editNoPermission);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _lock(AppLocalizations l, String key) {
    final locked = _locks.contains(key);
    return IconButton(
      tooltip: locked ? l.editUnlockField : l.editLockField,
      onPressed: _busy ? null : () => _toggleLock(key),
      icon: Icon(
        locked ? LucideIcons.lock : LucideIcons.lockOpen,
        size: 18,
        color: locked ? WfColors.cream : WfColors.creamMuted,
      ),
    );
  }

  Widget _row(Widget field, [Widget? lock]) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: field),
      // Allinea il lucchetto a quelli dei campi con l'etichetta.
      SizedBox(width: 40, child: lock),
    ],
  );

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? lockKey,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _row(
      TextField(
        controller: controller,
        enabled: !_busy,
        minLines: maxLines > 1 ? 3 : 1,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) {
          if (lockKey != null) _touched(lockKey);
          setState(() {});
        },
      ),
      lockKey == null
          ? null
          : _lock(AppLocalizations.of(context), lockKey),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final original = _original;
    final Widget body;
    if (original != null) {
      body = _form(l);
    } else if (_loadError != null) {
      body = ErrorBanner(describeError(l, _loadError!));
    } else {
      body = const Center(
        child: SizedBox.square(
          dimension: _spinnerSize,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.editMetadataTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            body,
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                if (original != null)
                  WfButton.primary(
                    label: l.editSave,
                    icon: LucideIcons.check,
                    onPressed: _busy || !_inputValid
                        ? null
                        : () => unawaited(_save()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l) {
    // Le classificazioni del server, più quella attuale se non ci fosse.
    final ratingNames = [
      '',
      for (final option in _ratings)
        if (option.value != null && option.name.isNotEmpty) option.name,
    ];
    if (!ratingNames.contains(_rating)) ratingNames.add(_rating);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _textField(_name, l.editFieldName, lockKey: 'Name'),
        _textField(_originalTitle, l.editFieldOriginalTitle),
        _textField(_sortName, l.editFieldSortName),
        if (_hasTagline) _textField(_tagline, l.editFieldTagline),
        _textField(
          _overview,
          l.editFieldOverview,
          lockKey: 'Overview',
          maxLines: 6,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _textField(_year, l.editFieldYear)),
            const SizedBox(width: 12),
            Expanded(child: _textField(_date, l.editFieldPremiereDate)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            l.editFieldGenres,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
          ),
        ),
        _row(
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final genre in _genres)
                InputChip(
                  label: Text(genre),
                  deleteIcon: const Icon(LucideIcons.x, size: 14),
                  onDeleted: _busy
                      ? null
                      : () {
                          setState(() => _genres = [
                            for (final g in _genres)
                              if (g != genre) g,
                          ]);
                          _touched('Genres');
                        },
                ),
            ],
          ),
          _lock(l, 'Genres'),
        ),
        const SizedBox(height: 8),
        _row(
          TextField(
            controller: _newGenre,
            enabled: !_busy,
            decoration: InputDecoration(labelText: l.editFieldAddGenre),
            onSubmitted: (_) => _addGenre(),
          ),
        ),
        const SizedBox(height: 12),
        _row(
          DropdownButtonFormField<String>(
            initialValue: _rating,
            dropdownColor: WfColors.surfaceHigh,
            decoration: InputDecoration(labelText: l.editFieldRating),
            onChanged: _busy
                ? null
                : (value) {
                    setState(() => _rating = value ?? '');
                    _touched('OfficialRating');
                  },
            items: [
              for (final name in ratingNames)
                DropdownMenuItem(
                  value: name,
                  child: Text(name.isEmpty ? l.editRatingNone : name),
                ),
            ],
          ),
          _lock(l, 'OfficialRating'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.editLockAll),
          // Su serie e stagioni Jellyfin propaga il blocco a tutti i figli.
          subtitle: Text(
            widget.kind == ItemKind.series || widget.kind == ItemKind.season
                ? l.editLockAllHintFolder
                : l.editLockAllHint,
          ),
          value: _lockAll,
          onChanged: _busy ? null : (value) => setState(() => _lockAll = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(_error!),
        ],
      ],
    );
  }
}
