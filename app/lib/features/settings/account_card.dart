import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/user_avatar.dart';
import '../profiles/avatar_dialog.dart';

/// Larghezza del tagliando a sinistra, e altezza nello stretto.
const _stubWidth = 120.0;
const _stubHeightCompact = 110.0;
const _avatarSize = 76.0;

/// La tessera dell'account (spec Impostazioni, decisione 7): a sinistra il
/// tagliando con l'avatar (tocco = dialogo dell'immagine), a destra nome, tag
/// "Admin" e [actions]. Nello stretto il tagliando va sopra.
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.userId,
    required this.name,
    required this.imageTag,
    required this.isAdministrator,
    required this.actions,
  });

  final String userId;
  final String name;
  final String? imageTag;
  final bool isAdministrator;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = FormFactor.of(context).compact;
    final stub = _Stub(
      compact: compact,
      userId: userId,
      name: name,
      imageTag: imageTag,
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(name, style: WfText.display(30)),
              if (isAdministrator) const _AdminTag(),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: _stubHeightCompact, child: stub),
                  body,
                ],
              )
            // Il tagliando segue l'altezza del corpo senza misurarlo "a
            // secco" (l'avatar non lo regge): sta sotto, in uno `Stack`.
            : Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: _stubWidth),
                    child: SizedBox(width: double.infinity, child: body),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _stubWidth,
                    child: stub,
                  ),
                ],
              ),
      ),
    );
  }
}

class _AdminTag extends StatelessWidget {
  const _AdminTag();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WfColors.gold.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Text(
        AppLocalizations.of(context).adminUsersAdmin,
        style: const TextStyle(
          color: WfColors.gold,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Stub extends StatelessWidget {
  const _Stub({
    required this.compact,
    required this.userId,
    required this.name,
    required this.imageTag,
  });

  final bool compact;
  final String userId;
  final String name;
  final String? imageTag;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CustomPaint(
      foregroundPainter: _DashedEdge(vertical: !compact),
      child: ColoredBox(
        color: WfColors.surfaceHigh,
        child: Center(
          child: Tooltip(
            message: l.settingsChangeImage,
            excludeFromSemantics: true,
            child: Semantics(
              button: true,
              label: l.settingsChangeImage,
              excludeSemantics: true,
              child: InkResponse(
                key: const Key('settings-change-image'),
                customBorder: const CircleBorder(),
                onTap: () => unawaited(
                  showAvatarDialog(
                    context,
                    userId: userId,
                    name: name,
                    imageTag: imageTag,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.gold),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: UserAvatar(
                          userId: userId,
                          name: name,
                          size: _avatarSize,
                          imageTag: imageTag,
                        ),
                      ),
                    ),
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: _PlusBadge(),
                    ),
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

class _PlusBadge extends StatelessWidget {
  const _PlusBadge();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 22,
    child: DecoratedBox(
      decoration: BoxDecoration(color: WfColors.gold, shape: BoxShape.circle),
      child: Icon(Icons.add, size: 16, color: WfColors.bg),
    ),
  );
}

/// Il filo tratteggiato sul bordo del tagliando (a destra, o in basso nello
/// stretto).
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.vertical});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WfColors.border
      ..strokeWidth = 2;
    const dash = 5.0;
    const gap = 4.0;
    final length = vertical ? size.height : size.width;
    for (var at = 0.0; at < length; at += dash + gap) {
      final end = (at + dash).clamp(0.0, length);
      if (vertical) {
        canvas.drawLine(
          Offset(size.width - 1, at),
          Offset(size.width - 1, end),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(at, size.height - 1),
          Offset(end, size.height - 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.vertical != vertical;
}
