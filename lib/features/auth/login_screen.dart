import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
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

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          // Il logo, poi il pannello (spec C §11.3).
          child: StaggerGroup(
            count: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StaggerItem(
                  index: 0,
                  child: Image.asset('assets/brand/logo.png', width: 280),
                ),
                const SizedBox(width: 56),
                StaggerItem(
                  index: 1,
                  child: Container(
                    width: 380,
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
                                  const SizedBox(height: 16),
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
  }
}
