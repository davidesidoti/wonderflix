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
import '../../ui/dialog_item_poster.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 880.0;

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

/// "17/12/2008" → la data; tutto il resto (anche le date impossibili come il
/// 31/02) → `null`.
DateTime? parseItalianDate(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text.trim());
  if (match == null) return null;
  final [day, month, year] = [
    for (var i = 1; i <= 3; i++) int.parse(match[i]!),
  ];
  final date = DateTime(year, month, day);
  // DateTime sposta le date impossibili (31 febbraio → 2 marzo): si rifiutano.
  return date.day == day && date.month == month ? date : null;
}

/// La data come "07/12/2008".
String formatItalianDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year.toString().padLeft(4, '0')}';

/// Modifica i metadati di un titolo (spec R §7.8). Prende l'id e rilegge da
/// sola, così la apre anche il riquadro delle segnalazioni.
Future<void> showEditMetadataDialog(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) {
  final l = AppLocalizations.of(context);
  final host = GlobalKey();
  return showWfDialog<void>(
    context,
    maxWidth: _dialogWidth,
    semanticLabel: l.editMetadataTitle,
    compactTitle: l.editMetadataTitle,
    builder: (_) => _EditMetadataDialog(key: host, itemId: itemId, kind: kind),
    footer: (_) => WfHostFooter(host: host),
  );
}

class _EditMetadataDialog extends ConsumerStatefulWidget {
  const _EditMetadataDialog({
    super.key,
    required this.itemId,
    required this.kind,
  });

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_EditMetadataDialog> createState() =>
      _EditMetadataDialogState();
}

class _EditMetadataDialogState extends ConsumerState<_EditMetadataDialog>
    with WfFooterHost<_EditMetadataDialog> {
  final _name = TextEditingController();
  final _originalTitle = TextEditingController();
  final _sortName = TextEditingController();
  final _tagline = TextEditingController();
  final _overview = TextEditingController();
  final _year = TextEditingController();
  final _date = TextEditingController();
  final _newGenre = TextEditingController();
  final _nameFocus = FocusNode();
  final _yearFocus = FocusNode();
  final _dateFocus = FocusNode();

  Map<String, dynamic>? _original;
  JellyfinItem? _item;
  List<ParentalRatingOption> _ratings = const [];
  List<String> _genres = [];
  String _rating = '';
  Set<String> _locks = {};

  /// I lucchetti girati a mano: la modifica del campo non li cambia più.
  final _manual = <String>{};
  bool _lockAll = false;
  bool _busy = false;

  /// Gli errori dei campi si mostrano solo dopo il primo "Salva".
  bool _submitted = false;
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
    for (final f in [_nameFocus, _yearFocus, _dateFocus]) {
      f.dispose();
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
        _item = JellyfinItem.fromJson(raw);
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
        _locks = _originalLocks(raw);
        _lockAll = raw['LockData'] == true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  void _retry() {
    setState(() => _loadError = null);
    unawaited(_load());
  }

  static String _originalTagline(Map<String, dynamic> raw) {
    final taglines = raw['Taglines'];
    return taglines is List && taglines.isNotEmpty ? '${taglines.first}' : '';
  }

  static String _originalDate(Map<String, dynamic> raw) {
    final date = raw['PremiereDate'];
    final parsed = date is String && date.length >= 10
        ? DateTime.tryParse(date.substring(0, 10))
        : null;
    return parsed == null ? '' : formatItalianDate(parsed);
  }

  static Set<String> _originalLocks(Map<String, dynamic> raw) => {
    ...?(raw['LockedFields'] as List?)?.cast<String>(),
  };

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
    if (_genres.contains(genre)) {
      setState(() {});
      return;
    }
    setState(() => _genres = [..._genres, genre]);
    _touched('Genres');
  }

  Future<void> _pickDate() async {
    final first = DateTime(1850);
    final last = DateTime(2200);
    final written = parseItalianDate(_date.text);
    // showDatePicker non accetta una data fuori dal suo intervallo.
    final inRange =
        written != null && !written.isBefore(first) && !written.isAfter(last);
    final picked = await showDatePicker(
      context: context,
      initialDate: inRange ? written : DateTime.now(),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() => _date.text = formatItalianDate(picked));
  }

  /// L'anno e la data vuoti non si salvano (si lasciano com'erano).
  int? get _yearValue => _yearValid ? int.tryParse(_year.text.trim()) : null;
  bool get _yearValid =>
      _year.text.trim().isEmpty ||
      RegExp(r'^\d{4}$').hasMatch(_year.text.trim());
  bool get _dateValid =>
      _date.text.trim().isEmpty || parseItalianDate(_date.text) != null;
  bool get _nameValid => _name.text.trim().isNotEmpty;

  /// I campi di testo con il valore letto, per il conteggio.
  List<(TextEditingController, String)> _texts(Map<String, dynamic> o) => [
    (_name, o['Name'] as String? ?? ''),
    (_originalTitle, o['OriginalTitle'] as String? ?? ''),
    (_sortName, o['ForcedSortName'] as String? ?? ''),
    if (_hasTagline) (_tagline, _originalTagline(o)),
    (_overview, o['Overview'] as String? ?? ''),
    (_year, '${o['ProductionYear'] ?? ''}'),
    (_date, _originalDate(o)),
  ];

  /// Le modifiche contate nel piede e da `WfDiscardGuard`.
  int get _changes {
    final o = _original;
    if (o == null) return 0;
    final genres = (o['Genres'] as List?)?.cast<String>() ?? const [];
    final locks = _originalLocks(o);
    final pending = _newGenre.text.trim();
    return [
      for (final (controller, before) in _texts(o))
        // Anno e data svuotati non si mandano: restano com'erano.
        controller.text != before &&
            !((controller == _year || controller == _date) &&
                controller.text.trim().isEmpty),
      (pending.isNotEmpty && !_genres.contains(pending)) ||
          jsonEncode(_genres) != jsonEncode(genres),
      _rating != (o['OfficialRating'] as String? ?? ''),
      _lockAll != (o['LockData'] == true),
      for (final key in _manual) _locks.contains(key) != locks.contains(key),
    ].where((changed) => changed).length;
  }

  MetadataEdits _edits(Map<String, dynamic> o) {
    String? text(TextEditingController c, String before) =>
        c.text == before ? null : c.text;
    final year = _yearValue;
    final date = parseItalianDate(_date.text);
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
      rating: _rating == (o['OfficialRating'] as String? ?? '')
          ? null
          : _rating,
      lockedFields: _locks,
      unlockedFields: _manual.difference(_locks),
      lockAll: _lockAll,
    );
  }

  Future<void> _save() async {
    final original = _original;
    if (_busy || original == null) return;
    // Il primo campo sbagliato prende il focus e non si chiama Jellyfin.
    final wrong = [
      if (!_nameValid) _nameFocus,
      if (!_yearValid) _yearFocus,
      if (!_dateValid) _dateFocus,
    ];
    if (wrong.isNotEmpty) {
      setState(() => _submitted = true);
      wrong.first.requestFocus();
      return;
    }
    // Un genere scritto e non aggiunto entra ora.
    _addGenre();
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

  @override
  Widget buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    final changes = _changes;
    final loadError = _loadError;
    return WfDialogFooter(
      noteIsError: _error != null || loadError != null,
      // Gli errori restano visibili anche con il corpo scorso.
      note:
          _error ??
          (loadError != null
              ? describeError(l, loadError)
              : changes > 0
              ? l.editChanges(changes)
              : null),
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
      primary: WfButton.primary(
        label: l.editSave,
        icon: LucideIcons.check,
        onPressed: _busy || changes == 0 ? null : () => unawaited(_save()),
      ),
    );
  }

  /// Lo stato del lucchetto a parole, sopra il campo a destra; un tocco lo gira.
  Widget _lock(AppLocalizations l, String key) {
    final locked = _locks.contains(key);
    final color = locked ? WfColors.gold : WfColors.creamMuted;
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: locked ? l.editUnlockField : l.editLockField,
        child: TextButton.icon(
          onPressed: _busy ? null : () => _toggleLock(key),
          style: TextButton.styleFrom(
            foregroundColor: color,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(fontSize: 12.5),
          ),
          icon: Icon(
            locked ? LucideIcons.lock : LucideIcons.lockOpen,
            size: 14,
            color: color,
          ),
          label: Text(locked ? l.editLocked : l.editAutoUpdates),
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? lockKey,
    int maxLines = 1,
    FocusNode? focusNode,
    String? error,
    String? hint,
    Widget? suffix,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lockKey != null) _lock(AppLocalizations.of(context), lockKey),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_busy,
          minLines: maxLines > 1 ? 3 : 1,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: _submitted ? error : null,
            errorMaxLines: 2,
            suffixIcon: suffix,
          ),
          onChanged: (_) {
            if (lockKey != null) _touched(lockKey);
            setState(() {});
          },
        ),
      ],
    ),
  );

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: WfText.display(20)),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = _item;
    final Widget body;
    if (_original != null) {
      body = _form(l);
    } else if (_loadError != null) {
      // L'errore è nel piede; qui si rilegge.
      body = Align(
        alignment: Alignment.centerLeft,
        child: WfButton.secondary(
          label: l.retry,
          icon: LucideIcons.refreshCw,
          onPressed: _retry,
        ),
      );
    } else {
      body = const Center(
        child: SizedBox.square(
          dimension: _spinnerSize,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Esc e il clic fuori non chiudono la finestra durante il salvataggio.
    // Durante il salvataggio Esc non chiede niente: il PopScope lo blocca.
    return WfDiscardGuard(
      changes: _busy ? 0 : _changes,
      child: PopScope(
        canPop: !_busy,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WfDialogHeader(
              title: l.editMetadataTitle,
              subtitle: item == null ? null : itemContextLine(l, item),
              leading: DialogItemPoster(itemId: widget.itemId),
            ),
            const SizedBox(height: 20),
            body,
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
    final pendingGenre = _newGenre.text.trim().isNotEmpty;
    final left = [
      _group(l.editGroupTitles, [
        _textField(
          _name,
          l.editFieldName,
          lockKey: 'Name',
          focusNode: _nameFocus,
          error: _nameValid ? null : l.editErrorName,
        ),
        _textField(_originalTitle, l.editFieldOriginalTitle),
        _textField(_sortName, l.editFieldSortName),
      ]),
      _group(l.editGroupOverview, [
        _textField(
          _overview,
          l.editFieldOverview,
          lockKey: 'Overview',
          maxLines: 6,
        ),
        if (_hasTagline) _textField(_tagline, l.editFieldTagline),
      ]),
    ];
    final right = [
      _group(l.editGroupDates, [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _textField(
                _year,
                l.editFieldYear,
                focusNode: _yearFocus,
                keyboardType: TextInputType.number,
                error: _yearValid ? null : l.editErrorYear,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _textField(
                _date,
                l.editFieldPremiereDate,
                focusNode: _dateFocus,
                hint: l.editDateHint,
                keyboardType: TextInputType.datetime,
                error: _dateValid ? null : l.editErrorDate,
                suffix: IconButton(
                  tooltip: l.editPickDate,
                  icon: const Icon(LucideIcons.calendar, size: 18),
                  onPressed: _busy ? null : () => unawaited(_pickDate()),
                ),
              ),
            ),
          ],
        ),
      ]),
      _group(l.editFieldGenres, [
        _lock(l, 'Genres'),
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
                        setState(
                          () => _genres = [
                            for (final g in _genres)
                              if (g != genre) g,
                          ],
                        );
                        _touched('Genres');
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _newGenre,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l.editFieldAddGenre,
                  helperText: pendingGenre ? l.editGenrePendingHint : null,
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _addGenre(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: WfButton.secondary(
                label: l.editAddGenre,
                icon: LucideIcons.plus,
                onPressed: _busy || !pendingGenre ? null : _addGenre,
              ),
            ),
          ],
        ),
      ]),
      _group(l.editGroupRating, [
        _lock(l, 'OfficialRating'),
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
      ]),
      _group(l.editGroupLockAll, [
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
      ]),
    ];
    final explain = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        l.editLockExplain,
        style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
      ),
    );
    if (FormFactor.of(context).compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [explain, ...left, ...right],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        explain,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
