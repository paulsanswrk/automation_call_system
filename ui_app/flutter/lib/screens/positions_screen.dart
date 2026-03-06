import 'dart:async';
import 'package:flutter/material.dart';
import '../models/position.dart';
import '../services/position_ws_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  final PositionWsService _wsService = PositionWsService();
  List<Position> _positions = [];
  WsConnectionStatus _status = WsConnectionStatus.connecting;
  late StreamSubscription<List<Position>> _posSub;
  late StreamSubscription<WsConnectionStatus> _statusSub;

  @override
  void initState() {
    super.initState();
    _posSub = _wsService.positionsStream.listen((positions) {
      if (mounted) setState(() => _positions = positions);
    });
    _statusSub = _wsService.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _wsService.connect();
  }

  @override
  void dispose() {
    _posSub.cancel();
    _statusSub.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  double get _totalPnl {
    double total = 0;
    for (final p in _positions) {
      total += double.tryParse(p.unrealizedPnl) ?? 0;
    }
    return total;
  }

  Map<String, List<Position>> get _grouped {
    final map = <String, List<Position>>{};
    for (final p in _positions) {
      map.putIfAbsent(p.exchange, () => []).add(p);
    }
    // Sort within each exchange group
    for (final list in map.values) {
      list.sort((a, b) {
        final cmp = a.symbol.compareTo(b.symbol);
        if (cmp != 0) return cmp;
        return a.side.compareTo(b.side);
      });
    }
    return map;
  }

  String _statusLabel() {
    switch (_status) {
      case WsConnectionStatus.connected:
        return 'connected';
      case WsConnectionStatus.connecting:
        return 'connecting';
      case WsConnectionStatus.disconnected:
        return 'disconnected';
    }
  }

  String _formatPrice(String price) {
    if (price.isEmpty || price == '0') return '—';
    final val = double.tryParse(price);
    if (val == null) return price;
    if (val >= 100) return val.toStringAsFixed(2);
    if (val >= 1) return val.toStringAsFixed(4);
    return val.toStringAsFixed(6);
  }

  String _formatPnl(String pnl) {
    final val = double.tryParse(pnl);
    if (val == null) return pnl;
    final sign = val >= 0 ? '+' : '';
    return '$sign${val.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Connection indicator
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              ConnectionIndicator(status: _statusLabel()),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: _positions.isEmpty
              ? const EmptyState(
                  icon: Icons.candlestick_chart_outlined,
                  title: 'No open positions',
                  subtitle:
                      'Open futures positions on connected exchanges will appear here in real-time.',
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Total PnL summary
                    SummaryCard(
                      label: 'UNREALIZED PNL',
                      value:
                          '${_totalPnl >= 0 ? '+' : ''}${_totalPnl.toStringAsFixed(2)} USDT',
                      valueColor: _totalPnl >= 0
                          ? AppTheme.greenBadge
                          : AppTheme.redBadge,
                    ),
                    const SizedBox(height: 16),

                    // Grouped positions
                    ..._grouped.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Exchange header
                          Row(
                            children: [
                              ExchangeBadge(exchange: entry.key),
                              const SizedBox(width: 8),
                              Text(
                                '${entry.value.length} position${entry.value.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Position cards
                          ...entry.value
                              .map((pos) => _PositionCard(
                                    position: pos,
                                    formatPrice: _formatPrice,
                                    formatPnl: _formatPnl,
                                  )),
                          const SizedBox(height: 12),
                        ],
                      );
                    }),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  final Position position;
  final String Function(String) formatPrice;
  final String Function(String) formatPnl;

  const _PositionCard({
    required this.position,
    required this.formatPrice,
    required this.formatPnl,
  });

  @override
  Widget build(BuildContext context) {
    final pnlVal = double.tryParse(position.unrealizedPnl) ?? 0;
    final isPositive = pnlVal >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border.all(color: AppTheme.surfaceBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Top row: symbol + side + margin
          Row(
            children: [
              Text(
                position.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                text: position.side,
                color: position.side == 'LONG'
                    ? AppTheme.greenBadge
                    : AppTheme.redBadge,
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.12),
                  border: Border.all(
                      color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  position.marginMode,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary),
                ),
              ),
              const Spacer(),
              // PnL
              Text(
                formatPnl(position.unrealizedPnl),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isPositive ? AppTheme.greenBadge : AppTheme.redBadge,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Grid of details
          Row(
            children: [
              _PosDetail('Qty', position.qty),
              _PosDetail('Entry', formatPrice(position.entryPrice)),
              _PosDetail('Mark', formatPrice(position.markPrice)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PosDetail('Leverage', '${position.leverage}x'),
              _PosDetail('Liq.', formatPrice(position.liquidationPrice)),
              _PosDetail('Margin', position.margin),
            ],
          ),
        ],
      ),
    );
  }
}

class _PosDetail extends StatelessWidget {
  final String label;
  final String value;
  const _PosDetail(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.04,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.monoSmall,
          ),
        ],
      ),
    );
  }
}
