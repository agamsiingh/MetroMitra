import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/router.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/shared/widgets/announcement_banner.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';

/// First tab: one tile per thing the app can really do. Tiles for data the
/// app does not have yet (fares, gates, timings, parking) are not shown.
class HomeGridScreen extends ConsumerWidget {
  const HomeGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tiles = <_Tile>[
      _Tile(
        'route',
        l10n.homeTileRoute,
        Icons.alt_route_rounded,
        Routes.go,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _Tile(
        'map',
        l10n.homeTileMap,
        Icons.map_rounded,
        Routes.map,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _Tile(
        'lines',
        l10n.homeTileLines,
        Icons.stacked_line_chart_rounded,
        Routes.homeLines,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _Tile(
        'nearby',
        l10n.homeTileNearby,
        Icons.near_me_rounded,
        Routes.nearby,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _Tile(
        'ask',
        l10n.homeTileAsk,
        Icons.chat_bubble_rounded,
        Routes.ask,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _Tile(
        'about',
        l10n.homeTileAbout,
        Icons.info_rounded,
        Routes.homeAbout,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DataBanner(),
          const AnnouncementBanner(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [for (final t in tiles) _TileCard(tile: t)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  const _Tile(this.id, this.label, this.icon, this.location, this.bg, this.fg);

  final String id;
  final String label;
  final IconData icon;
  final String location;
  final Color bg;
  final Color fg;
}

class _TileCard extends StatelessWidget {
  const _TileCard({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tile.label,
      excludeSemantics: true,
      child: Material(
        color: tile.bg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          key: Key('home-tile-${tile.id}'),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onTap: () => context.go(tile.location),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tile.icon, size: 36, color: tile.fg),
                const SizedBox(height: 10),
                Text(
                  tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tile.fg,
                    fontWeight: FontWeight.w600,
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
