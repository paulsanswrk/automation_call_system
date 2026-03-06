import 'package:flutter/material.dart';
import 'app_theme.dart';

// ─── Summary Card (used on Positions, Channels, Exchanges, etc.) ───
class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border.all(color: AppTheme.surfaceBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppTheme.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge (Live, Paper, Off, LONG, SHORT, etc.) ───
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.filled = false,
  });

  // Presets
  factory StatusBadge.long() => const StatusBadge(text: 'LONG', color: AppTheme.greenBadge);
  factory StatusBadge.short() => const StatusBadge(text: 'SHORT', color: AppTheme.redBadge);
  factory StatusBadge.live() => const StatusBadge(text: 'LIVE', color: AppTheme.greenBadge);
  factory StatusBadge.paper() => const StatusBadge(text: 'PAPER', color: AppTheme.amberBadge);
  factory StatusBadge.off() => const StatusBadge(text: 'OFF', color: AppTheme.textSecondary);
  factory StatusBadge.active() => const StatusBadge(text: 'ACTIVE', color: AppTheme.greenBadge);
  factory StatusBadge.inactive() => const StatusBadge(text: 'INACTIVE', color: AppTheme.textSecondary);
  factory StatusBadge.connected() => const StatusBadge(text: 'CONNECTED', color: AppTheme.greenBadge);
  factory StatusBadge.error() => const StatusBadge(text: 'ERROR', color: AppTheme.redBadge);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

// ─── Action Badge (PLACE_ORDER, SKIP, ERROR) ───
class ActionBadge extends StatelessWidget {
  final String action;

  const ActionBadge({super.key, required this.action});

  Color get _color {
    switch (action) {
      case 'PLACE_ORDER':
        return AppTheme.greenBadge;
      case 'SKIP':
        return AppTheme.amberBadge;
      case 'ERROR':
        return AppTheme.redBadge;
      case 'AUTO_SL_BREAKEVEN':
        return const Color(0xFF3B82F6);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        action,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ─── Exchange Badge (BitUnix blue, Phemex green) ───
class ExchangeBadge extends StatelessWidget {
  final String exchange;

  const ExchangeBadge({super.key, required this.exchange});

  Gradient get _gradient {
    switch (exchange.toLowerCase()) {
      case 'bitunix':
        return AppTheme.bitunixGradient;
      case 'phemex':
        return AppTheme.phemexGradient;
      default:
        return const LinearGradient(colors: [AppTheme.textSecondary, AppTheme.textSecondary]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        exchange.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ─── Live Dot (pulsing green animation) ───
class LiveDot extends StatefulWidget {
  final Color color;
  final double size;

  const LiveDot({
    super.key,
    this.color = AppTheme.greenBadge,
    this.size = 8,
  });

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 0.4).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Connection Indicator ───
class ConnectionIndicator extends StatelessWidget {
  final String status; // 'connected', 'connecting', 'disconnected'

  const ConnectionIndicator({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'connected':
        return AppTheme.greenBadge;
      case 'connecting':
        return AppTheme.amberBadge;
      case 'disconnected':
        return AppTheme.redBadge;
      default:
        return AppTheme.textSecondary;
    }
  }

  String get _label {
    switch (status) {
      case 'connected':
        return 'Live';
      case 'connecting':
        return 'Connecting…';
      case 'disconnected':
        return 'Disconnected';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'connected')
            LiveDot(color: _color, size: 8)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textColor,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── Empty State ───
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
