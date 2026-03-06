import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ShellScreen extends ConsumerStatefulWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  List<_NavItem> _getNavItems(bool isAdmin) {
    final items = <_NavItem>[
      const _NavItem(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          path: '/notifications'),
      const _NavItem(
          icon: Icons.candlestick_chart_outlined,
          label: 'Positions',
          path: '/positions'),
      const _NavItem(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Exchanges',
          path: '/exchanges'),
    ];
    if (isAdmin) {
      items.addAll(const [
        _NavItem(icon: Icons.tag, label: 'Channels', path: '/channels'),
        _NavItem(
            icon: Icons.list_alt, label: 'Trades', path: '/trade-actions'),
        _NavItem(
            icon: Icons.smart_toy_outlined, label: 'AI Log', path: '/ai-log'),
      ]);
    }
    return items;
  }

  int _getSelectedIndex(List<_NavItem> items) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < items.length; i++) {
      if (location == items[i].path) return i;
    }
    return 0;
  }

  String _getTitle(List<_NavItem> items, int index) {
    if (index < items.length) return items[index].label;
    return 'ACT Trading';
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final user = ref.watch(currentUserProvider);
    final items = _getNavItems(isAdmin);
    final selectedIndex = _getSelectedIndex(items);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getTitle(items, selectedIndex),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PopupMenuButton<String>(
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.surfaceBorder),
                ),
                color: AppTheme.surfaceCard,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primaryColor,
                    backgroundImage:
                        user.userMetadata?['avatar_url'] != null
                            ? NetworkImage(
                                user.userMetadata!['avatar_url'] as String)
                            : null,
                    child: user.userMetadata?['avatar_url'] == null
                        ? Text(
                            (user.userMetadata?['full_name'] as String? ??
                                    user.email ??
                                    'U')
                                .characters
                                .first
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                ),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Text(
                      user.userMetadata?['full_name'] as String? ??
                          user.email ??
                          'User',
                      style: const TextStyle(
                        color: AppTheme.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'signout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: AppTheme.redBadge),
                        SizedBox(width: 8),
                        Text('Sign Out',
                            style: TextStyle(color: AppTheme.redBadge)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'signout') {
                    await AuthService.signOut();
                  }
                },
              ),
            ),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.surfaceBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex.clamp(0, items.length - 1),
          onTap: (index) {
            if (index < items.length) {
              context.go(items[index].path);
            }
          },
          items: items
              .map((item) => BottomNavigationBarItem(
                    icon: Icon(item.icon),
                    label: item.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
  });
}
