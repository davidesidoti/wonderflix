import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'auth_providers.dart';
import 'password_login_form.dart';
import 'quick_connect_panel.dart';
import 'session_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final quickConnect = ref.watch(quickConnectEnabledProvider).value ?? false;
    final expired = session is SessionSignedOut && session.expired;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/logo.png', width: 280),
              const SizedBox(width: 56),
              Container(
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
                    if (expired) ...[
                      ErrorBanner(l.sessionExpired),
                      const SizedBox(height: 12),
                    ],
                    if (quickConnect)
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
                            const SizedBox(
                              height: 300,
                              child: TabBarView(children: [
                                PasswordLoginForm(),
                                QuickConnectPanel(),
                              ]),
                            ),
                          ],
                        ),
                      )
                    else
                      const PasswordLoginForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
