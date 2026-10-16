import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/features/assistant/presentation/assistant_screen.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/presentation/home_screen.dart';
import 'package:metromitra/features/go/presentation/route_results_screen.dart';
import 'package:metromitra/features/go/presentation/station_picker_screen.dart';
import 'package:metromitra/features/home/presentation/about_screen.dart';
import 'package:metromitra/features/home/presentation/home_grid_screen.dart';
import 'package:metromitra/features/home/presentation/lines_screen.dart';
import 'package:metromitra/features/journey/presentation/journey_screen.dart';
import 'package:metromitra/features/map/presentation/dmrc_map_screen.dart';
import 'package:metromitra/features/map/presentation/map_screen.dart';
import 'package:metromitra/features/nearby/presentation/nearby_screen.dart';
import 'package:metromitra/features/station/presentation/station_detail_screen.dart';

abstract final class Routes {
  static const home = '/home';
  static const homeLines = '/home/lines';
  static const homeAbout = '/home/about';
  static const go = '/go';
  static const pick = '/go/pick/:end';
  static const route = '/go/route';
  static const nearby = '/go/nearby';
  static const routeMap = '/go/route/map';
  static const station = '/station/:id';
  static const journey = '/journey';
  static const map = '/map';
  static const dmrcMap = '/map/dmrc';
  static const ask = '/ask';
}

/// Manual device verification: `--dart-define=METROMITRA_START_ROUTE=/map`
/// (or `/go/nearby`, `/station/<id>`, ...) opens that screen first. Ignored
/// in release builds.
const _startRoute = String.fromEnvironment('METROMITRA_START_ROUTE');

final routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(
    initialLocation: !kReleaseMode && _startRoute.startsWith('/')
        ? _startRoute
        : Routes.home,
  ),
);

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Shell with four tabs (Home, Go, Map, Ask). The station picker and route results
/// open full screen above the shell and carry canonical station ids only.
/// Other feature routes (/station/:id) come with the milestones that build them.
GoRouter buildRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeGridScreen(),
                routes: [
                  GoRoute(
                    path: 'lines',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const LinesScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.go,
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'pick/:end',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => StationPickerScreen(
                      end: state.pathParameters['end'] == 'to'
                          ? JourneyEnd.to
                          : JourneyEnd.from,
                    ),
                  ),
                  GoRoute(
                    path: 'nearby',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const NearbyScreen(),
                  ),
                  GoRoute(
                    path: 'route',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => RouteResultsScreen(
                      fromId: state.uri.queryParameters['from'] ?? '',
                      toId: state.uri.queryParameters['to'] ?? '',
                    ),
                    routes: [
                      GoRoute(
                        path: 'map',
                        parentNavigatorKey: _rootKey,
                        builder: (context, state) => RouteMapScreen(
                          fromId: state.uri.queryParameters['from'] ?? '',
                          toId: state.uri.queryParameters['to'] ?? '',
                          optionIndex:
                              int.tryParse(
                                state.uri.queryParameters['opt'] ?? '',
                              ) ??
                              0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.map,
                builder: (context, state) => MapScreen(
                  focusStationId: state.uri.queryParameters['station'],
                ),
                routes: [
                  GoRoute(
                    path: 'dmrc',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const DmrcMapScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.ask,
                builder: (context, state) => const AssistantScreen(),
              ),
            ],
          ),
        ],
      ),
      // Station detail is full screen above the tabs and takes a canonical
      // station id only (a name is never an identifier).
      GoRoute(
        path: Routes.station,
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            StationDetailScreen(stationId: state.pathParameters['id'] ?? ''),
      ),
      // Journey mode: full screen, no tabs (and no ads, ever).
      GoRoute(
        path: Routes.journey,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const JourneyScreen(),
      ),
    ],
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.directions_subway_outlined),
            selectedIcon: const Icon(Icons.directions_subway_rounded),
            label: l10n.navGo,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
            label: l10n.navMap,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: l10n.navAsk,
          ),
        ],
      ),
    );
  }
}
