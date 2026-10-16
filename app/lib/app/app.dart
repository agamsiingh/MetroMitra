import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/router.dart';
import 'package:metromitra/app/theme/app_theme.dart';
import 'package:metromitra/bootstrap/bootstrap_gate.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';

class MetroMitraApp extends ConsumerWidget {
  const MetroMitraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(remoteConfigProvider.select((c) => c.seedColor));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: buildTheme(Brightness.light, seed: seed),
      darkTheme: buildTheme(Brightness.dark, seed: seed),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => BootstrapGate(child: child!),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
