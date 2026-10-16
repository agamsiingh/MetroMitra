import 'package:flutter/material.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';

enum StateViewKind { empty, error, offline, denied }

/// Shared empty / error / offline / denied state (docs/design-system.md).
/// Every screen shows one of these instead of a blank or a raw error.
class StateView extends StatelessWidget {
  const StateView({
    required this.kind,
    this.title,
    this.message,
    this.onRetry,
    this.action,
    super.key,
  });

  final StateViewKind kind;

  /// Overrides the default title for [kind].
  final String? title;
  final String? message;

  /// Shows a "Try again" button when set.
  final VoidCallback? onRetry;

  /// Optional extra action (e.g. "Open settings" for [StateViewKind.denied]).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, defaultTitle, defaultMessage) = switch (kind) {
      StateViewKind.empty => (Icons.inbox_rounded, l10n.stateEmptyTitle, null),
      StateViewKind.error => (
        Icons.error_outline_rounded,
        l10n.stateErrorTitle,
        null,
      ),
      StateViewKind.offline => (
        Icons.cloud_off_rounded,
        l10n.stateOfflineTitle,
        l10n.stateOfflineBody,
      ),
      StateViewKind.denied => (
        Icons.lock_outline_rounded,
        l10n.stateDeniedTitle,
        null,
      ),
    };
    final body = message ?? defaultMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.screenPadding),
            Text(
              title ?? defaultTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.unit * 2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sectionGap),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.stateRetry)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.screenPadding),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
