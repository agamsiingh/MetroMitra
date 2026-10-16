import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/bootstrap/update_providers.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// Shows the app only once a dataset has been loaded and validated. Until
/// then (or if none is usable) it shows a loading or an explanatory state, so
/// no screen ever sees a missing, corrupt or disallowed dataset.
class BootstrapGate extends ConsumerWidget {
  const BootstrapGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    final l10n = AppLocalizations.of(context);
    return boot.when(
      loading: () => Scaffold(
        body: Center(
          key: const Key('boot-loading'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.bootLoading),
            ],
          ),
        ),
      ),
      error: (_, _) => _Failure(
        problem: DatasetProblem.corrupt,
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
      data: (result) => switch (result) {
        BootstrapReady() => _UpdateTrigger(child: child),
        BootstrapFailed(:final problem) => _Failure(
          problem: problem,
          onRetry: () => ref.invalidate(bootstrapProvider),
        ),
      },
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.problem, required this.onRetry});

  final DatasetProblem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, body) = switch (problem) {
      DatasetProblem.missing => (l10n.bootMissingTitle, l10n.bootMissingBody),
      DatasetProblem.corrupt => (l10n.bootCorruptTitle, l10n.bootCorruptBody),
      DatasetProblem.incompatible => (
        l10n.bootIncompatibleTitle,
        l10n.bootIncompatibleBody,
      ),
      DatasetProblem.invalid => (l10n.bootInvalidTitle, l10n.bootInvalidBody),
      DatasetProblem.draftNotAllowed => (
        l10n.bootDraftTitle,
        l10n.bootDraftBody,
      ),
      DatasetProblem.testDataNotAllowed => (
        l10n.bootTestDataTitle,
        l10n.bootTestDataBody,
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: StateView(
          key: Key('boot-failure-${problem.name}'),
          kind: problem == DatasetProblem.missing
              ? StateViewKind.empty
              : StateViewKind.error,
          title: title,
          message: body,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

/// Starts the once-a-day dataset check after the first frame, so it can never
/// delay launch. Failures are silent: the loaded dataset keeps working.
class _UpdateTrigger extends ConsumerStatefulWidget {
  const _UpdateTrigger({required this.child});

  final Widget child;

  @override
  ConsumerState<_UpdateTrigger> createState() => _UpdateTriggerState();
}

class _UpdateTriggerState extends ConsumerState<_UpdateTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateCheckProvider);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
