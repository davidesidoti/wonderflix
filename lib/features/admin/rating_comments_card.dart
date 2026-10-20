import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/rating_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../social/social_providers.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_providers.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

/// Altezza massima dell'elenco dentro la card.
const _commentsMaxHeight = 480.0;

/// L'elenco dei commenti, le pagine lette finora.
@immutable
class RatingCommentsState {
  const RatingCommentsState({
    required this.items,
    this.next,
    this.loadingMore = false,
    this.error,
  });

  final List<AdminComment> items;

  /// Il `before` per la pagina dopo; `null` a fine elenco.
  final String? next;
  final bool loadingMore;

  /// L'ultimo "Altri" non riuscito; le voci già lette restano.
  final Object? error;

  RatingCommentsState copyWith({
    List<AdminComment>? items,
    String? next,
    bool? loadingMore,
    Object? error,
  }) =>
      RatingCommentsState(
        items: items ?? this.items,
        next: next ?? this.next,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
      );
}

class RatingCommentsController extends AsyncNotifier<RatingCommentsState> {
  @override
  Future<RatingCommentsState> build() async {
    final api = ref.watch(pluginAdminApiProvider);
    final page = await api.ratingComments();
    return RatingCommentsState(items: page.items, next: page.next);
  }

  /// "Altri": la pagina dopo, in fondo. Un errore resta nello stato.
  Future<void> more() async {
    final current = state.value;
    final before = current?.next;
    if (current == null || current.loadingMore || before == null) return;
    final api = ref.read(pluginAdminApiProvider);
    state = AsyncData(current.copyWith(loadingMore: true, next: before));
    try {
      final page = await api.ratingComments(before: before);
      if (!ref.mounted) return;
      final now = state.requireValue;
      state = AsyncData(RatingCommentsState(
          items: [...now.items, ...page.items], next: page.next));
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(
          state.requireValue.copyWith(loadingMore: false, error: error));
    }
  }

  /// Toglie la voce solo se il server ha cancellato; l'errore passa a chi
  /// chiama.
  Future<void> delete(AdminComment comment) async {
    await ref
        .read(pluginAdminApiProvider)
        .deleteRatingComment(comment.userId, comment.itemId);
    final now = state.value;
    if (!ref.mounted || now == null) return;
    final user = jellyfinIdKey(comment.userId);
    final item = jellyfinIdKey(comment.itemId);
    state = AsyncData(now.copyWith(items: [
      for (final c in now.items)
        if (jellyfinIdKey(c.userId) != user || jellyfinIdKey(c.itemId) != item)
          c,
    ], next: now.next));
  }
}

final ratingCommentsProvider = AsyncNotifierProvider.autoDispose<
    RatingCommentsController, RatingCommentsState>(RatingCommentsController.new);

/// "Commenti degli utenti" (spec Q §11.3): chi ha scritto cosa su quale
/// titolo, con "Cancella commento".
class RatingCommentsCard extends ConsumerWidget {
  const RatingCommentsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    return AdminCard(
      title: l.adminCommentsTitle,
      icon: LucideIcons.messageSquare,
      child: !features.known
          ? const SkeletonBox(width: 240, height: 20)
          // shortcut: `ratings` vale solo con l'accesso ai watch party, quindi
          // un admin senza quell'accesso vede "Serve il plugin"; da rivedere
          // se serve un'altra via per la funzione.
          : !features.ratings
              ? Text(l.adminCommentsNeedPlugin,
                  style: const TextStyle(color: WfColors.creamMuted))
              : _list(context, ref, l),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final data = ref.watch(ratingCommentsProvider);
    final value = data.value;
    if (value == null) {
      return data.hasError
          ? AdminCardError(
              error: data.error!,
              onRetry: () => ref.invalidate(ratingCommentsProvider))
          : const SkeletonBox(width: 240, height: 20);
    }
    // Con tutte le voci cancellate ma altre pagine da leggere, resta "Altri".
    if (value.items.isEmpty && value.next == null) {
      return AdminEmptyText(text: l.adminCommentsEmpty);
    }
    final controller = ref.read(ratingCommentsProvider.notifier);
    final error = value.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Una pagina può avere 50 voci: la lista scorre dentro la card e non
        // spinge in basso le altre.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _commentsMaxHeight),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final comment in value.items)
                _CommentTile(
                  comment: comment,
                  onDelete: () async {
                    final confirmed = await showAdminConfirmDialog(
                      context,
                      title: l.adminCommentDeleteTitle,
                      message: l.adminCommentDeleteMessage(
                          comment.userName, comment.title),
                      confirmLabel: l.adminCommentDelete,
                    );
                    if (confirmed) await controller.delete(comment);
                  },
                ),
            ],
          ),
        ),
        if (value.next != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            AdminActionButton(
              label: l.adminCommentsMore,
              icon: LucideIcons.chevronDown,
              onPressed: value.loadingMore ? null : controller.more,
            ),
            if (error != null) ...[
              const SizedBox(width: 12),
              Flexible(
                  child: Text(describeError(l, error),
                      style: const TextStyle(color: WfColors.error))),
            ],
          ]),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onDelete});

  final AdminComment comment;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(comment.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
            const SizedBox(width: 4),
            Text('${comment.score}'),
            const Spacer(),
            Text(adminTimeLabel(comment.updatedAt, clock.now(), l),
                style: muted),
          ]),
          const SizedBox(height: 2),
          Text(comment.title, style: muted),
          const SizedBox(height: 6),
          // Sempre testo semplice, intero.
          Text(comment.comment),
          const SizedBox(height: 8),
          AdminActionButton(
            label: l.adminCommentDelete,
            icon: LucideIcons.trash2,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
