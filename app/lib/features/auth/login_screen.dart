import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/tv_back.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
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
    final reloginName = reloginId == null ? null : book.byId(reloginId)?.name;
    // "Annulla" torna a "Chi guarda?": solo se c'è un altro profilo da
    // scegliere.
    final canCancel = ((signedOut?.adding ?? false) && !book.isEmpty) ||
        (reloginId != null && book.profiles.length > 1);
    // Un profilo migrato senza nome (il primo `/Users/Me` non è riuscito):
    // il nome si scrive, e il fuoco resta lì. Tornando dal recupero, il
    // nome scritto lì.
    final form = PasswordLoginForm(
      initialUsername: _nonEmpty(_typedUsername) ?? _nonEmpty(reloginName),
      onForgotPassword: (username) => setState(() {
        _recovering = true;
        _typedUsername = username;
      }),
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
                            onBack: (username) => setState(() {
                              _recovering = false;
                              _backToPassword = true;
                              _typedUsername = username;
                            }),
                          )
                        else ...[
                          if (expired) ...[
                            ErrorBanner(l.sessionExpired),
                            const SizedBox(height: 12),
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
                              // Sulla TV si parte da Quick Connect: con il
                              // telecomando la password è scomoda.
                              initialIndex:
                                  FormFactor.of(context).tv && !_backToPassword
                                      ? 1
                                      : 0,
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
                                  if (compact)
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
                                    })
                                  else
                                    SizedBox(
                                      height: 300,
                                      child: TabBarView(children: [
                                        form,
                                        const QuickConnectPanel(),
                                      ]),
                                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
    // Sulla TV Indietro non chiude l'app: chiude il recupero, da Quick
    // Connect torna alla password, aggiungendo un account torna a "Chi
    // guarda?", altrimenti serve il doppio Indietro.
    return TvBackGuard(
      onBack: () {
        final tabs = _tabs;
        if (_recovering) {
          setState(() {
            _recovering = false;
            _backToPassword = true;
          });
        } else if (tabs != null && tabs.index != 0) {
          tabs.animateTo(0);
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
