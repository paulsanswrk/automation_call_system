import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/shell_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/positions_screen.dart';
import '../screens/exchange_accounts_screen.dart';
import '../screens/channels_screen.dart';
import '../screens/trade_actions_screen.dart';
import '../screens/ai_log_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return GoRouter(
    initialLocation: '/notifications',
    redirect: (context, state) {
      final goingToLogin = state.matchedLocation == '/login';

      if (!isAuthenticated && !goingToLogin) {
        return '/login';
      }

      if (isAuthenticated && goingToLogin) {
        return '/notifications';
      }

      // Admin guard
      final adminPaths = ['/channels', '/trade-actions', '/ai-log'];
      if (adminPaths.contains(state.matchedLocation) && !isAdmin) {
        return '/positions';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: NotificationsScreen(),
            ),
          ),
          GoRoute(
            path: '/positions',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PositionsScreen(),
            ),
          ),
          GoRoute(
            path: '/exchanges',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExchangeAccountsScreen(),
            ),
          ),
          GoRoute(
            path: '/channels',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ChannelsScreen(),
            ),
          ),
          GoRoute(
            path: '/trade-actions',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TradeActionsScreen(),
            ),
          ),
          GoRoute(
            path: '/ai-log',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AILogScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
