import 'package:flutter/material.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// Temporary body for tabs whose feature lands in a later milestone.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StateView(
        kind: StateViewKind.empty,
        message: AppLocalizations.of(context).placeholderBody,
      ),
    );
  }
}
