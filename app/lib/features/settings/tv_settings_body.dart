import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/tv_focusable.dart';
import '../player/player_settings.dart';
import '../update/update_controller.dart';
import 'language_preferences.dart';
import 'language_settings_section.dart';
import 'locale_controller.dart';
import 'player_settings_section.dart';
import 'subtitle_preview.dart';
import 'tv_choice_panel.dart';

/// Larghezza dell'elenco delle righe sulla TV.
const _listWidth = 440.0;

/// Una riga dell'elenco: [value] a destra, "›" se [choices] apre il pannello,
/// un interruttore se [toggle] non è `null`. [hint] e [scope] vanno a destra
/// quando ha il focus.
class _Row {
  const _Row({
    required this.id,
    required this.label,
    required this.hint,
    this.scope,
    this.value,
    this.toggle,
    this.onActivate,
    this.choices = false,
    this.preview = false,
    this.update = false,
  });

  final String id;
  final String label;
  final String hint;
  final String? scope;
  final String? value;
  final bool? toggle;
  final VoidCallback? onActivate;
  final bool choices;

  /// La piccola anteprima dei sottotitoli a destra.
  final bool preview;

  /// La riga dell'aggiornamento: bordo e testo oro.
  final bool update;
}

/// Il corpo di Impostazioni sulla TV (decisione 8): a sinistra le righe per
/// gruppi, a destra nome, spiegazione e "dove si salva" della riga col focus.
/// Su e Giù si muovono solo nell'elenco; le scelte si fanno nel pannello di
/// [showTvChoicePanel].
class TvSettingsBody extends ConsumerStatefulWidget {
  const TvSettingsBody({super.key});

  @override
  ConsumerState<TvSettingsBody> createState() => _TvSettingsBodyState();
}

class _TvSettingsBodyState extends ConsumerState<TvSettingsBody> {
  final _nodes = <String, FocusNode>{};

  FocusNode _node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'tv-settings-$id'));

  /// Le righe dall'alto: Su e Giù si muovono solo tra queste.
  var _order = <String>[];

  /// La riga col focus, per il riquadro a destra.
  String? _focused;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Come nella barra laterale: la ricerca geometrica uscirebbe dall'elenco.
  /// Mai `goBack` qui: Indietro chiude la rotta con il pop normale del navigatore
  /// radice.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    final i = _order.indexWhere((id) => _node(id).hasPrimaryFocus);
    if (i < 0) return KeyEventResult.ignored;
    _node(_order[(i + step).clamp(0, _order.length - 1)]).requestFocus();
    return KeyEventResult.handled;
  }

  /// Apre il pannello e, a scelta fatta e diversa, la salva con [save]. Il
  /// focus torna sulla riga [id].
  Future<void> _choose<T>(
    String id, {
    required String title,
    required List<(T, String)> options,
    required T current,
    required void Function(T value) save,
    Widget Function(T focused)? background,
  }) async {
    final picked = await showTvChoicePanel<T>(
      context,
      title: title,
      options: options,
      current: current,
      background: background,
    );
    if (!mounted) return;
    _node(id).requestFocus();
    if (picked != null && picked != current) save(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = <(String, List<_Row>)>[
      (l.tvSettingsUpdate, _updateRows(l)),
      (l.settingsSectionApp, [_appLanguageRow(l)]),
      (l.settingsSectionPlayback, _playbackRows(l)),
      (l.settingsSectionSubtitles, [..._languageRows(l), _sizeRow(l)]),
      (
        l.tvSettingsGroupInfo,
        [
          _Row(
            id: 'version',
            label: l.tvSettingsVersion,
            hint: l.tvSettingsVersionHint,
            value: ref.watch(clientInfoProvider).version,
            // Una riga vera: prende il focus, OK non fa niente.
            onActivate: () {},
          ),
        ],
      ),
    ].where((group) => group.$2.isNotEmpty).toList();
    final all = [for (final group in rows) ...group.$2];
    _order = [for (final row in all) row.id];
    final focused = all.where((row) => row.id == _focused).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 40, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _listWidth,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              // Non una ListView: le righe fuori schermo non avrebbero il nodo.
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 34, bottom: 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(l.menuSettings, style: WfText.display(34)),
                    ),
                    for (final (label, group) in rows) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 0, 6),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: WfColors.creamMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      for (final row in group)
                        _row(row, autofocus: row == all.first),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 36),
          Expanded(child: focused == null ? const SizedBox() : _info(focused)),
        ],
      ),
    );
  }

  Widget _row(_Row row, {required bool autofocus}) {
    final focused = row.id == _focused;
    final gold = focused || row.update;
    final toggle = row.toggle;
    return TvFocusable(
      key: ValueKey('tv-settings-${row.id}'),
      focusNode: _node(row.id),
      autofocus: autofocus,
      onActivate: row.onActivate,
      onFocusChange: (on) {
        if (on) {
          setState(() => _focused = row.id);
        } else if (_focused == row.id) {
          setState(() => _focused = null);
        }
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: focused
              ? WfColors.surfaceHigh
              : row.update
              ? WfColors.gold.withValues(alpha: 0.08)
              : null,
          border: row.update
              ? Border.all(color: WfColors.gold.withValues(alpha: 0.5))
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: row.update
                    ? const TextStyle(
                        color: WfColors.gold,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
            ),
            if (row.value case final value?) ...[
              const SizedBox(width: 14),
              Text(
                value,
                style: TextStyle(
                  color: gold ? WfColors.gold : WfColors.creamMuted,
                  fontWeight: row.update ? FontWeight.w600 : null,
                ),
              ),
            ],
            if (row.choices) ...[
              const SizedBox(width: 8),
              const Text(
                '›',
                style: TextStyle(color: WfColors.creamMuted, fontSize: 20),
              ),
            ],
            if (toggle != null)
              // Lo cambia OK sulla riga: l'interruttore non prende il focus.
              ExcludeFocus(
                child: Switch(
                  value: toggle,
                  onChanged: (_) => row.onActivate?.call(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _info(_Row row) {
    final scale = ref.watch(playerSettingsProvider).subtitleScale;
    // Scorrevole solo perché una spiegazione lunga non sbordi.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 92, bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label, style: WfText.display(26)),
          const SizedBox(height: 14),
          Text(row.hint, style: const TextStyle(fontSize: 18, height: 1.5)),
          if (row.scope case final scope?) ...[
            const SizedBox(height: 14),
            Text(
              scope,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 15),
            ),
          ],
          if (row.preview) ...[
            const SizedBox(height: 20),
            SubtitlePreview(scale: scale),
          ],
        ],
      ),
    );
  }

  List<_Row> _updateRows(AppLocalizations l) {
    final update = ref.watch(updateControllerProvider);
    final release = update.release;
    if (release == null) return const [];
    // Mentre scarica OK non fa niente: il testo non lo promette.
    final updateHint = update.ready
        ? l.tvSettingsUpdateHint
        : l.tvSettingsUpdateDownloadingHint;
    return [
      _Row(
        id: 'update',
        label: l.tvUpdateAvailable(release.version.toString()),
        hint: update.installPermissionNeeded
            ? '$updateHint\n${l.tvUpdatePermission}'
            : updateHint,
        value: update.ready
            ? l.tvUpdateInstall
            : '${((update.progress ?? 0) * 100).round()}%',
        update: true,
        onActivate: update.ready
            ? () => unawaited(
                ref.read(updateControllerProvider.notifier).install(),
              )
            // In download OK non fa niente, ma la riga resta raggiungibile.
            : () {},
      ),
    ];
  }

  _Row _appLanguageRow(AppLocalizations l) {
    final current = ref.watch(localeProvider)?.languageCode ?? 'system';
    final options = [
      ('system', l.settingsLanguageSystem),
      ('it', 'Italiano'),
      ('en', 'English'),
    ];
    return _Row(
      id: 'app-language',
      label: l.settingsLanguageApp,
      hint: l.tvSettingsLanguageAppHint,
      scope: l.tvSettingsScopeDevice,
      value: _labelOf(options, current),
      choices: true,
      onActivate: () => unawaited(
        _choose(
          'app-language',
          title: l.settingsLanguageApp,
          options: options,
          current: current,
          save: (code) => unawaited(
            ref
                .read(localeProvider.notifier)
                .set(code == 'system' ? null : Locale(code)),
          ),
        ),
      ),
    );
  }

  List<_Row> _playbackRows(AppLocalizations l) {
    final settings = ref.watch(playerSettingsProvider);
    void save(PlayerSettings next) =>
        unawaited(ref.read(playerSettingsProvider.notifier).update(next));
    final qualities = [
      for (final quality in StreamQuality.values)
        (quality, qualityLabel(l, quality)),
    ];
    // Niente decodifica hardware: la TV decodifica sempre in hardware (Media3).
    return [
      _Row(
        id: 'quality',
        label: l.settingsQuality,
        hint: l.tvSettingsQualityHint,
        scope: l.tvSettingsScopeDevice,
        value: qualityLabel(l, settings.quality),
        choices: true,
        onActivate: () => unawaited(
          _choose(
            'quality',
            title: l.settingsQuality,
            options: qualities,
            current: settings.quality,
            save: (quality) => save(
              ref.read(playerSettingsProvider).copyWith(quality: quality),
            ),
          ),
        ),
      ),
      _Row(
        id: 'autoplay-next',
        label: l.tvSettingsAutoplayNext,
        hint: l.tvSettingsAutoplayNextHint,
        scope: l.tvSettingsScopeDevice,
        toggle: settings.autoplayNext,
        onActivate: () =>
            save(settings.copyWith(autoplayNext: !settings.autoplayNext)),
      ),
      _Row(
        id: 'auto-skip-intro',
        label: l.tvSettingsAutoSkipIntro,
        hint: l.tvSettingsAutoSkipIntroHint,
        scope: l.tvSettingsScopeDevice,
        toggle: settings.autoSkipIntro,
        onActivate: () =>
            save(settings.copyWith(autoSkipIntro: !settings.autoSkipIntro)),
      ),
    ];
  }

  /// Le tre righe delle lingue (sul server): "…" mentre caricano, una riga
  /// "Non caricate, riprova" se non si leggono.
  List<_Row> _languageRows(AppLocalizations l) {
    final scope = l.tvSettingsScopeAccount;
    final async = ref.watch(languagePreferencesProvider);
    if (async case AsyncError(:final error) when !async.hasValue) {
      return [
        _Row(
          // Lo stesso id della prima riga delle lingue: riletta, il focus
          // resta lì invece di perdersi con la riga che sparisce.
          id: 'audio-language',
          label: l.tvSettingsNotLoaded,
          hint: describeError(l, error),
          scope: scope,
          onActivate: () => ref.invalidate(languagePreferencesProvider),
        ),
      ];
    }
    final preferences = async.value;
    List<(String, String)> languages(String current) => [
      ('', l.settingsLanguageAny),
      for (final entry in playbackLanguages.entries) (entry.key, entry.value),
      if (current.isNotEmpty && !playbackLanguages.containsKey(current))
        (current, current),
    ];
    final modes = [
      ('Default', l.settingsSubtitleModeDefault),
      ('Always', l.settingsSubtitleModeAlways),
      ('OnlyForced', l.settingsSubtitleModeOnlyForced),
      ('None', l.settingsSubtitleModeNone),
      ('Smart', l.settingsSubtitleModeSmart),
    ];
    _Row row(
      String id,
      String label,
      String hint,
      List<(String, String)> Function(LanguagePreferences p) options,
      String Function(LanguagePreferences p) current,
      LanguagePreferences Function(LanguagePreferences p, String value) apply, {
      bool preview = false,
    }) {
      final p = preferences;
      return _Row(
        id: id,
        label: label,
        hint: hint,
        scope: scope,
        value: p == null ? '…' : _labelOf(options(p), current(p)),
        choices: true,
        preview: preview,
        // Mentre caricano OK non fa niente.
        onActivate: p == null
            ? () {}
            : () => unawaited(
                _choose(
                  id,
                  title: label,
                  options: options(p),
                  current: current(p),
                  save: (value) => unawaited(
                    LanguageSettingsSection.save(context, ref, apply(p, value)),
                  ),
                ),
              ),
      );
    }

    return [
      row(
        'audio-language',
        l.settingsAudioLanguage,
        l.tvSettingsAudioLanguageHint,
        (p) => languages(p.audioLanguage),
        (p) => p.audioLanguage,
        (p, value) => p.copyWith(audioLanguage: value),
      ),
      row(
        'subtitle-language',
        l.settingsSubtitleLanguage,
        l.tvSettingsSubtitleLanguageHint,
        (p) => languages(p.subtitleLanguage),
        (p) => p.subtitleLanguage,
        (p, value) => p.copyWith(subtitleLanguage: value),
        preview: true,
      ),
      row(
        'subtitle-mode',
        l.tvSettingsSubtitleMode,
        l.tvSettingsSubtitleModeHint,
        (_) => modes,
        (p) =>
            subtitleModes.contains(p.subtitleMode) ? p.subtitleMode : 'Default',
        (p, value) => p.copyWith(subtitleMode: value),
        preview: true,
      ),
    ];
  }

  _Row _sizeRow(AppLocalizations l) {
    final settings = ref.watch(playerSettingsProvider);
    final options = [
      for (final scale in subtitleScaleOptions)
        (scale, subtitleScaleLabel(l, scale)),
    ];
    return _Row(
      id: 'subtitle-size',
      label: l.settingsSubtitleSize,
      hint: l.tvSettingsSubtitleSizeHint,
      // Salvata nelle preferenze di questo dispositivo.
      scope: l.tvSettingsScopeDevice,
      value: subtitleScaleLabel(l, settings.subtitleScale),
      choices: true,
      preview: true,
      onActivate: () => unawaited(
        _choose(
          'subtitle-size',
          title: l.settingsSubtitleSize,
          options: options,
          current: settings.subtitleScale,
          save: (scale) => unawaited(
            ref
                .read(playerSettingsProvider.notifier)
                .update(
                  ref
                      .read(playerSettingsProvider)
                      .copyWith(subtitleScale: scale),
                ),
          ),
          // Il resto dello schermo è l'anteprima, che segue l'opzione col
          // focus.
          background: (scale) => SubtitlePreview(scale: scale),
        ),
      ),
    );
  }

  static String _labelOf<T>(List<(T, String)> options, T value) => options
      .firstWhere((o) => o.$1 == value, orElse: () => (value, '$value'))
      .$2;
}
