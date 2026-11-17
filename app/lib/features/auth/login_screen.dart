import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../app/tv_back.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/tv_text_field_frame.dart';
import '../../ui/user_avatar.dart';
import 'auth_providers.dart';
import 'password_login_form.dart';
import 'profiles_state.dart';
import 'quick_connect_panel.dart';
import 'recovery_panel.dart';
import 'session_controller.dart';

/// [name] se c'è scritto qualcosa, altrimenti `null`.
String? _nonEmpty(String? name) =>
    name == null || name.trim().isEmpty ? null : name;

/// Accesso (spec K §9.3): il primo, un profilo nuovo ("Aggiungi profilo") o
/// uno scaduto ("Accedi di nuovo", con il nome già scritto).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// "Password dimenticata?" aperto (spec L §9.3): il pannello mostra il
  /// recupero al posto dell'accesso, anche con Quick Connect.
  bool _recovering = false;

  /// Il nome scritto nell'accesso o nel recupero: passa da uno all'altro.
  String? _typedUsername;

  /// Le schede Password/Quick Connect, se ci sono (per Indietro sulla TV).
  TabController? _tabs;

  /// Tornando dal recupero si riparte dalla password (da lì si era aperto),
  /// anche sulla TV.
  bool _backToPassword = false;

  /// "Non sei tu?" premuto: niente "Ciao" né avviso, il nome si riscrive.
  bool _notYou = false;

  /// Attorno al pannello: per rimettere il focus su una scheda.
  final _panelFocus = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// La scheda da cui si parte: sulla TV Quick Connect, con il telecomando
  /// la password è scomoda.
  int _firstTab(BuildContext context) => FormFactor.of(context).tv ? 1 : 0;

  /// Dopo la prossima costruzione il focus va alla scheda [index] o, senza
  /// schede, al primo controllo del pannello che non sia un campo di testo
  /// (aprirebbe la tastiera): mai invisibile sulla pagina.
  void _focusTab(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = _panelFocus.traversalDescendants.toList();
      bool inside<T extends Widget>(FocusNode node) =>
          node.context?.findAncestorWidgetOfExactType<T>() != null;
      final tabs = nodes.where(inside<TabBar>).toList();
      (tabs.elementAtOrNull(index) ??
              nodes.where((n) => !inside<EditableText>(n)).firstOrNull ??
              nodes.firstOrNull)
          ?.requestFocus();
    });
  }

  /// Dopo la prossima costruzione il focus va alla cornice del nome utente
  /// (la prima del pannello), non al campo: aprirebbe la tastiera.
  void _focusUsernameFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _panelFocus.traversalDescendants
          .where((n) =>
              n.context?.findAncestorWidgetOfExactType<TvTextFieldFrame>() !=
                  null &&
              n.context?.findAncestorWidgetOfExactType<EditableText>() == null)
          .firstOrNull
          ?.requestFocus();
    });
  }

  @override
  void dispose() {
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Prima dei figli: Quick Connect chiede il codice con il DeviceId del
    // profilo (spec K §9.2).
    ref.read(sessionControllerProvider.notifier).prepareLogin();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final quickConnectAsync = ref.watch(quickConnectEnabledProvider);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final signedOut = session is SessionSignedOut ? session : null;
    final expired = signedOut?.expired ?? false;
    final reloginId = signedOut?.reloginUserId;
    final relogin = reloginId == null ? null : book.byId(reloginId);
    final reloginName = relogin?.name;
    // "Ciao, {nome}" (spec §9.2): solo con un nome salvato da salutare.
    final hello = expired && !_notYou ? _nonEmpty(reloginName) : null;
    // "Annulla" torna a "Chi guarda?": solo se c'è un altro profilo da
    // scegliere.
    final canCancel = ((signedOut?.adding ?? false) && !book.isEmpty) ||
        (reloginId != null && book.profiles.length > 1);
    // Un profilo migrato senza nome (il primo `/Users/Me` non è riuscito):
    // il nome si scrive, e il fuoco resta lì. Tornando dal recupero, il
    // nome scritto lì.
    // "Non sei tu?" lo ricrea vuoto (e fuori dalla TV il fuoco va al nome).
    final form = PasswordLoginForm(
      key: ValueKey(_notYou),
      initialUsername: _nonEmpty(_typedUsername) ??
          (_notYou ? null : _nonEmpty(reloginName)),
      onForgotPassword: (username) => setState(() {
        _recovering = true;
        _typedUsername = username;
      }),
      onNotYou: hello == null
          ? null
          : () {
              setState(() {
                _notYou = true;
                _typedUsername = null;
              });
              // Il link sparisce col fuoco: in TV va alla cornice del nome
              // (fuori dalla TV ci pensa l'autofocus del campo).
              if (FormFactor.of(context).tv) _focusUsernameFrame();
            },
    );

    // Nello stretto il logo sta sopra il pannello, che prende tutta la
    // larghezza: affiancati servirebbero 716 punti.
    final compact = FormFactor.of(context).compact;
    // Lo rimette la scheda qui sotto, se c'è.
    _tabs = null;

    final page = Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 32),
          // Il logo, poi il pannello (spec C §11.3).
          child: StaggerGroup(
            count: 2,
            child: Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                StaggerItem(
                  index: 0,
                  child: Align(
                    child: Image.asset('assets/brand/logo.png',
                        width: compact ? 200 : 280),
                  ),
                ),
                const SizedBox(width: 56, height: 24),
                StaggerItem(
                  index: 1,
                  // Il nodo per rimettere il focus nel pannello (`_focusTab`).
                  child: Focus(
                    focusNode: _panelFocus,
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: Container(
                    key: const Key('login-panel'),
                    width: compact ? null : 380,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: WfColors.surface,
                      border: Border.all(color: WfColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_recovering)
                          RecoveryPanel(
                            initialUsername: _typedUsername,
                            onBack: (username) {
                              setState(() {
                                _recovering = false;
                                _backToPassword = true;
                                _typedUsername = username;
                              });
                              if (FormFactor.of(context).tv) _focusTab(0);
                            },
                          )
                        else ...[
                          if (hello != null)
                            Row(
                              children: [
                                UserAvatar(
                                    userId: reloginId!,
                                    name: hello,
                                    imageTag: relogin?.imageTag,
                                    size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(l.loginWelcomeBack(hello),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: WfText.display(34)),
                                ),
                              ],
                            )
                          else
                            Text(l.loginTitle, style: WfText.display(34)),
                          const SizedBox(height: 18),
                          if (expired && !_notYou) ...[
                            _ExpiredNotice(l.sessionExpired),
                            const SizedBox(height: 18),
                          ],
                          if (quickConnectAsync.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5),
                                ),
                              ),
                            )
                          else if (quickConnectAsync.value ?? false)
                            DefaultTabController(
                              length: 2,
                              // La scheda iniziale; tornando dal recupero la
                              // password, da cui si era aperto.
                              initialIndex:
                                  _backToPassword ? 0 : _firstTab(context),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TabBar(
                                    isScrollable: true,
                                    tabAlignment: TabAlignment.start,
                                    tabs: [
                                      Tab(text: l.loginTabPassword),
                                      Tab(text: l.loginTabQuickConnect),
                                    ],
                                  ),
                                  // Lo spazio sotto le schede, e intanto il
                                  // loro controller per Indietro.
                                  Builder(builder: (context) {
                                    _tabs = DefaultTabController.of(context);
                                    return const SizedBox(height: 16);
                                  }),
                                  // Senza altezza fissa: una scheda alla
                                  // volta, entrambe vive (il nome scritto
                                  // resta).
                                  Builder(builder: (context) {
                                    final tabs =
                                        DefaultTabController.of(context);
                                    return ListenableBuilder(
                                      listenable: tabs,
                                      builder: (context, _) => IndexedStack(
                                        index: tabs.index,
                                        children: [
                                          form,
                                          const QuickConnectPanel(),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            )
                          else
                            form,
                          if (canCancel) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              key: const Key('login-cancel'),
                              onPressed: ref
                                  .read(sessionControllerProvider.notifier)
                                  .cancelLogin,
                              child: Text(l.profilesCancel),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Sulla TV Indietro non chiude l'app: chiude il recupero, da un'altra
    // scheda torna a quella iniziale, aggiungendo un account torna a "Chi
    // guarda?", altrimenti serve il doppio Indietro.
    return TvBackGuard(
      onBack: () {
        final tabs = _tabs;
        final first = _firstTab(context);
        if (_recovering) {
          setState(() {
            _recovering = false;
            _backToPassword = true;
          });
          _focusTab(0);
        } else if (tabs != null && tabs.index != first) {
          tabs.animateTo(first);
          _focusTab(first);
        } else if (canCancel) {
          ref.read(sessionControllerProvider.notifier).cancelLogin();
        } else {
          return false;
        }
        return true;
      },
      child: page,
    );
  }
}

/// La sessione scaduta: un avviso neutro, non un errore (spec §9.2).
class _ExpiredNotice extends StatelessWidget {
  const _ExpiredNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.clock, size: 16, color: WfColors.cream),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: WfColors.creamMuted, fontSize: 13, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
