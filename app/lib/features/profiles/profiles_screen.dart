import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../app/tv_back.dart';
import '../../core/platform/device_kind.dart';
import '../../core/storage/profile_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/profiles_state.dart';
import '../auth/session_controller.dart';
import 'avatar_dialog.dart';

/// Diametro dell'avatar di un profilo in "Chi guarda?" su desktop (spec
/// §9.1).
const profileAvatarSize = 132.0;

/// Le misure di "Chi guarda?" per forma: lato del logo (è quadrato), misura
/// del titolo, diametro dell'avatar, larghezza di una carta e spazio tra le
/// carte.
typedef _Sizes = ({
  double logo,
  double title,
  double avatar,
  double card,
  double spacing,
});

const _Sizes _desktop = (
  logo: 140,
  title: 56,
  avatar: profileAvatarSize,
  card: 150,
  spacing: 24,
);

/// Due colonne a 390 px.
const _Sizes _phone =
    (logo: 96, title: 40, avatar: 96, card: 140, spacing: 16);

const _Sizes _tv = (logo: 96, title: 44, avatar: 100, card: 128, spacing: 24);

/// Opacità dell'avatar di un profilo scaduto.
const _expiredOpacity = 0.45;

/// Opacità del velo scuro sull'avatar del profilo che si apre: sull'oro lo
/// spinner non si vedrebbe.
const _openingScrimAlpha = 0.55;

// Misure verticali: con queste "Chi guarda?" sta tutta nella finestra più
// piccola (1024×640, circa 600 px utili) senza scorrere, anche con un
// profilo scaduto ("Accedi di nuovo" sotto il nome).

/// Margine intorno al contenuto.
const _padding = 24.0;

/// Distanza tra il logo e il titolo, e tra le card e "Gestisci profili".
const _gap = 24.0;

/// Distanza tra il titolo e le card.
const _titleGap = 28.0;

/// Il nome da mostrare: un profilo migrato il cui primo `/Users/Me` non è
/// riuscito non ha ancora un nome.
String _displayName(AppLocalizations l, StoredProfile profile) =>
    profile.name.isEmpty ? l.profilesUnnamed : profile.name;

/// In TV il titolo resta su una riga (si rimpicciolisce col testo di sistema
/// grande): due righe non lascerebbero posto alle carte in 540.
Widget _fitOnTv(bool tv, Widget title) =>
    tv ? FittedBox(fit: BoxFit.scaleDown, child: title) : title;

/// "Chi guarda?" (spec K §9.4): i profili del PC, "Aggiungi profilo" e
/// "Gestisci profili". La lingua è quella dell'ultimo profilo usato.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  bool _managing = false;

  /// Il profilo che si sta aprendo: intanto gli altri clic non fanno niente.
  /// Le card restano attive (il fuoco resta dov'è): è [_open] a ignorarli.
  String? _opening;

  SessionController get _session =>
      ref.read(sessionControllerProvider.notifier);

  Future<void> _open(StoredProfile profile) async {
    if (_opening != null || _managing) return;
    if (profile.expired) {
      _session.relogin(profile.userId);
      return;
    }
    setState(() => _opening = profile.userId);
    try {
      await _session.openProfile(profile.userId);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _remove(StoredProfile profile) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.profilesRemoveTitle(
          _displayName(l, profile), ref.read(deviceKindProvider).name),
      message: l.profilesRemoveBody,
      confirmLabel: l.profilesRemove,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !mounted) return;
    // In TV il focus era sul Rimuovi che sparisce: va a quello della carta
    // accanto, o a "Fine".
    final profiles = ref.read(profilesProvider).book.profiles;
    final at = profiles.indexWhere((p) => p.userId == profile.userId);
    final next = (profiles.elementAtOrNull(at + 1) ??
            (at > 0 ? profiles[at - 1] : null))
        ?.userId;
    await _session.removeProfile(profile.userId);
    if (!mounted || !FormFactor.of(context).tv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusNode? button(Key key) => _scope.traversalDescendants
          .where((n) =>
              n.context?.findAncestorWidgetOfExactType<WfButton>()?.key == key)
          .firstOrNull;
      (button(ValueKey('profile-remove-$next')) ??
              button(const ValueKey('profiles-manage-button')))
          ?.requestFocus();
    });
    // La carta può essere già sparita: un frame serve lo stesso.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  final _scope = FocusScopeNode(debugLabel: 'profiles');

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _setManaging(bool managing) {
    // Le frecce ricordano da dove si è arrivati: Su da "Fine" tornerebbe
    // alla carta di prima, che in "Gestisci profili" non prende il focus, e
    // il tasto andrebbe perso.
    FocusTraversalGroup.maybeOf(context)?.invalidateScopeData(_scope);
    setState(() => _managing = managing);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final idle = _opening == null;
    final device = ref.watch(deviceKindProvider).name;
    final form = FormFactor.of(context);
    final sizes = form.tv ? _tv : (form.compact ? _phone : _desktop);
    // Il fuoco parte dall'ultimo profilo usato, altrimenti dal primo: Invio
    // lo apre subito.
    final last = book.lastUserId;
    final focusUserId = (last == null ? null : book.byId(last)?.userId) ??
        book.profiles.firstOrNull?.userId;
    // Esc in "Gestisci profili" fa come "Fine". Un tasto, non `DismissIntent`:
    // le `Actions` dello `Scaffold` lo fermerebbero con il fuoco su "Fine" o
    // su Rimuovi.
    final page = CallbackShortcuts(
      bindings: {
        if (_managing)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _setManaging(false),
      },
      // Il fuoco resta nella schermata: la card che lo aveva si spegne in
      // "Gestisci profili", ed Esc deve arrivare lo stesso.
      child: FocusScope(
        node: _scope,
        child: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_padding),
              // Il logo, il titolo, le card e "Gestisci profili", uno dopo
              // l'altro come nel login (spec C §11.3).
              child: StaggerGroup(
                count: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // In TV 5 carte con due pulsanti non starebbero in 540
                    // col logo.
                    if (!(form.tv && _managing)) ...[
                      StaggerItem(
                        index: 0,
                        // Con l'altezza fissa niente scatto quando l'immagine
                        // arriva.
                        child: Image.asset('assets/brand/logo.png',
                            width: sizes.logo, height: sizes.logo),
                      ),
                      const SizedBox(height: _gap),
                    ],
                    // Con le chiavi, quando il logo sparisce il resto non
                    // si ricrea: il focus resta su "Fine".
                    StaggerItem(
                      key: const ValueKey('profiles-title'),
                      index: 1,
                      child: _fitOnTv(
                          form.tv,
                          Text(_managing ? l.profilesManage : l.profilesTitle,
                              maxLines: form.tv ? 1 : null,
                              style: WfText.display(sizes.title))),
                    ),
                    // In TV in gestione anche col testo di sistema a 1,3.
                    SizedBox(height: form.tv && _managing ? 12 : _titleGap),
                    StaggerItem(
                      key: const ValueKey('profiles-cards'),
                      index: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            spacing: sizes.spacing,
                            runSpacing: sizes.spacing,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final profile in book.profiles)
                                _ProfileCard(
                                  key: ValueKey('profile-${profile.userId}'),
                                  profile: profile,
                                  sizes: sizes,
                                  managing: _managing,
                                  opening: _opening == profile.userId,
                                  autofocus: !_managing &&
                                      profile.userId == focusUserId,
                                  onOpen: _managing
                                      ? null
                                      : () => unawaited(_open(profile)),
                                  onRemove: () => unawaited(_remove(profile)),
                                ),
                              if (!book.isFull && !_managing)
                                _AddProfileCard(
                                    key: const ValueKey('profile-add'),
                                    sizes: sizes,
                                    onTap: idle ? _session.addProfile : null),
                            ],
                          ),
                          if (book.isFull)
                            _LimitNote(l.profilesFull(
                                ProfileBook.maxProfiles, device))
                          else if (!book.isEmpty)
                            Padding(
                              padding:
                                  EdgeInsets.only(top: form.compact ? 16 : 28),
                              child: Text(
                                  l.profilesCount(book.profiles.length,
                                      ProfileBook.maxProfiles, device),
                                  style: const TextStyle(
                                      color: WfColors.creamMuted,
                                      fontSize: 12.5,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ])),
                            ),
                        ],
                      ),
                    ),
                    if (!book.isEmpty) ...[
                      const SizedBox(height: _gap),
                      StaggerItem(
                        key: const ValueKey('profiles-manage'),
                        index: 3,
                        child: WfButton.secondary(
                          key: const ValueKey('profiles-manage-button'),
                          label: _managing ? l.profilesDone : l.profilesManage,
                          icon:
                              _managing ? LucideIcons.check : LucideIcons.pencil,
                          onPressed:
                              idle ? () => _setManaging(!_managing) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Sulla TV Indietro non chiude l'app: fa come "Fine" in "Gestisci
    // profili", non fa niente mentre un profilo si apre, altrimenti serve il
    // doppio Indietro.
    return TvBackGuard(
      onBack: () {
        if (!_managing) return _opening != null;
        _setManaging(false);
        return true;
      },
      child: page,
    );
  }
}

/// Un profilo: avatar e nome. Si apre con il clic o con Invio.
/// Per lo screen reader è un pulsante con il nome.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.sizes,
    required this.managing,
    required this.opening,
    required this.autofocus,
    required this.onOpen,
    required this.onRemove,
  });

  final StoredProfile profile;
  final _Sizes sizes;
  final bool managing;
  final bool opening;
  final bool autofocus;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = _displayName(l, profile);
    final tv = FormFactor.of(context).tv;
    return Semantics(
      container: true,
      // In "Gestisci profili" la card non si apre.
      button: !managing,
      label: name,
      hint: profile.expired ? l.profilesSignInAgain : null,
      child: SizedBox(
        width: sizes.card,
        // In TV il focus è di TvFocusable; in "Gestisci profili" (`onOpen`
        // null) la carta non lo prende, i pulsanti sì.
        child: TvFocusable(
          autofocus: autofocus,
          onActivate: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onOpen,
            canRequestFocus: !tv,
            autofocus: !tv && autofocus,
            borderRadius: BorderRadius.circular(12),
            focusColor: tv ? null : WfColors.gold.withValues(alpha: 0.18),
            hoverColor: WfColors.gold.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Il nome lo dice già la card.
                      ExcludeSemantics(
                        child: Opacity(
                          opacity:
                              profile.expired || managing ? _expiredOpacity : 1,
                          child: UserAvatar(
                            userId: profile.userId,
                            name: profile.name,
                            size: sizes.avatar,
                            imageTag: profile.imageTag,
                          ),
                        ),
                      ),
                      if (opening) ...[
                        Container(
                          key: ValueKey('profile-opening-${profile.userId}'),
                          width: sizes.avatar,
                          height: sizes.avatar,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: WfColors.bg
                                .withValues(alpha: _openingScrimAlpha),
                          ),
                        ),
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: WfColors.cream),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        if (profile.expired)
                          Text(l.profilesSignInAgain,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: WfColors.gold, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (managing) ...[
                    const SizedBox(height: 8),
                    _CardButton(
                      buttonKey: ValueKey('profile-image-${profile.userId}'),
                      label: l.profilesEdit,
                      semanticsLabel: l.profilesEditNamed(name),
                      icon: LucideIcons.pencil,
                      // Un profilo scaduto non ha un token valido.
                      onPressed: profile.expired
                          ? null
                          : () => unawaited(showAvatarDialog(context,
                              userId: profile.userId,
                              name: name,
                              imageTag: profile.imageTag)),
                    ),
                    const SizedBox(height: 8),
                    _CardButton(
                      buttonKey: ValueKey('profile-remove-${profile.userId}'),
                      label: l.profilesRemove,
                      semanticsLabel: l.profilesRemoveNamed(name),
                      icon: LucideIcons.trash2,
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Modifica" o "Rimuovi" sotto il nome, larghi quanto la carta e su una
/// riga (ellissi con un testo di sistema grande). Lo screen reader sente
/// anche il nome ([semanticsLabel]): cinque "Rimuovi" uguali non dicono di
/// chi.
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.buttonKey,
    required this.label,
    required this.semanticsLabel,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final String semanticsLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    Widget button = SizedBox(
      width: double.infinity,
      child: WfButton.secondary(
        key: buttonKey,
        small: true,
        dense: true,
        label: label,
        icon: icon,
        onPressed: onPressed,
      ),
    );
    // In TV non si tocca: senza i 48 px del tocco cinque carte con due
    // pulsanti stanno in 540.
    if (FormFactor.of(context).tv) {
      button = Theme(
        data: Theme.of(context).copyWith(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: button,
      );
    }
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// "Aggiungi profilo": un cerchio con il più.
class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard(
      {super.key, required this.sizes, required this.onTap});

  final _Sizes sizes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).profilesAdd;
    final tv = FormFactor.of(context).tv;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: SizedBox(
        width: sizes.card,
        child: TvFocusable(
          onActivate: onTap,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            canRequestFocus: !tv,
            borderRadius: BorderRadius.circular(12),
            focusColor: tv ? null : WfColors.gold.withValues(alpha: 0.18),
            hoverColor: WfColors.gold.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: sizes.avatar,
                      height: sizes.avatar,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.border, width: 2),
                      ),
                      child: const Icon(LucideIcons.plus,
                          size: 40, color: WfColors.creamMuted),
                    ),
                    const SizedBox(height: 12),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: WfColors.creamMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Con 5 profili, al posto del "+": perché non se ne aggiungono altri.
class _LimitNote extends StatelessWidget {
  const _LimitNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(top: FormFactor.of(context).compact ? 16 : 28),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: WfColors.surface,
          border: Border.all(color: WfColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.info, size: 17, color: WfColors.gold),
            const SizedBox(width: 9),
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
