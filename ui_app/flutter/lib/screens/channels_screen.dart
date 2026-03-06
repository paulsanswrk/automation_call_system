import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/exchange_account.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  List<Channel> _channels = [];
  List<ExchangeAccount> _exchangeAccounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/api/channels'),
        ApiService.get('/api/exchange-accounts'),
      ]);

      if (results[0].statusCode == 200) {
        final list = jsonDecode(results[0].body) as List;
        _channels = list.map((e) => Channel.fromJson(e)).toList();
      }
      if (results[1].statusCode == 200) {
        final list = jsonDecode(results[1].body) as List;
        _exchangeAccounts =
            list.map((e) => ExchangeAccount.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendSubscription(Channel ch, Map<String, dynamic> overrides) async {
    final sub = ch.subscription;
    final body = <String, dynamic>{
      'status': sub?.status ?? 'off',
      'tp_rule': sub?.tpRule ?? 'halving',
      'auto_sl_after_tp1': sub?.autoSlAfterTp1 ?? false,
      'position_size_type': sub?.positionSizeType ?? 'min_qty',
      'position_size_value': sub?.positionSizeValue ?? 0,
      'notes': sub?.notes ?? '',
      'exchange_account_ids': ch.exchangeAccountIds,
      ...overrides,
    };
    try {
      final res = await ApiService.post('/api/channels/${ch.id}/subscribe',
          body: body);
      if (res.statusCode == 200) _fetchAll();
    } catch (e) {
      debugPrint('Subscription error: $e');
    }
  }

  Future<void> _setStatus(Channel ch, String status) async {
    final sub = ch.subscription;
    await _sendSubscription(ch, {
      'status': status,
      'exchange_account_ids': status == 'off' ? [] : ch.exchangeAccountIds,
      'tp_rule': sub?.tpRule ?? 'halving',
      'auto_sl_after_tp1': sub?.autoSlAfterTp1 ?? false,
      'position_size_type': sub?.positionSizeType ?? 'min_qty',
      'position_size_value': sub?.positionSizeValue ?? 0,
      'notes': sub?.notes ?? '',
    });
  }

  Future<void> _deleteChannel(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Delete Channel'),
        content:
            const Text('Delete this channel and all its subscriptions?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.redBadge),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService.delete('/api/channels/$id');
      if (res.statusCode == 200) _fetchAll();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  void _showManualCallDialog(Channel ch) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AppTheme.surfaceCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.surfaceBorder),
            ),
            title: Text('Manual Call — #${ch.channelName}'),
            content: TextField(
              controller: textCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'Enter trade call here... (e.g. LONG BTC/USDT Entry: 65000 TP: 66000)',
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: sending || textCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        setDialogState(() => sending = true);
                        try {
                          final user = ref.read(currentUserProvider);
                          final payload = {
                            'channel_name': ch.channelName,
                            'text': textCtrl.text,
                          };
                          final res = await ApiService.post(
                              '/api/messages/manual',
                              body: payload);
                          if (res.statusCode == 200 && ctx.mounted) {
                            Navigator.pop(ctx);
                          } else if (ctx.mounted) {
                            final err = jsonDecode(res.body);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(
                                  'Failed: ${err['error'] ?? 'Unknown error'}'),
                            ));
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Failed to submit manual call.')),
                            );
                          }
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => sending = false);
                          }
                        }
                      },
                child: Text(sending ? 'Sending...' : 'Send Call'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeSince(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'never';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '< 1m ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return _loading && _channels.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _channels.isEmpty
            ? const EmptyState(
                icon: Icons.tag,
                title: 'No Channels Yet',
                subtitle:
                    'Channels appear automatically when Discord messages arrive.',
              )
            : RefreshIndicator(
                onRefresh: _fetchAll,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _channels.length,
                  itemBuilder: (ctx, i) => _ChannelCard(
                    channel: _channels[i],
                    exchangeAccounts: _exchangeAccounts,
                    onSetStatus: _setStatus,
                    onSendSubscription: _sendSubscription,
                    onDelete: _deleteChannel,
                    onManualCall: _showManualCallDialog,
                    timeSince: _timeSince,
                  ),
                ),
              );
  }
}

class _ChannelCard extends StatelessWidget {
  final Channel channel;
  final List<ExchangeAccount> exchangeAccounts;
  final Function(Channel, String) onSetStatus;
  final Function(Channel, Map<String, dynamic>) onSendSubscription;
  final Function(int) onDelete;
  final Function(Channel) onManualCall;
  final String Function(String?) timeSince;

  const _ChannelCard({
    required this.channel,
    required this.exchangeAccounts,
    required this.onSetStatus,
    required this.onSendSubscription,
    required this.onDelete,
    required this.onManualCall,
    required this.timeSince,
  });

  Color get _accentColor {
    switch (channel.subStatus) {
      case 'live':
        return AppTheme.greenBadge;
      case 'paper':
        return AppTheme.amberBadge;
      default:
        return Colors.transparent;
    }
  }

  String get _statusLabel {
    switch (channel.subStatus) {
      case 'live':
        return 'Live';
      case 'paper':
        return 'Paper';
      case 'off':
        return 'Off';
      default:
        return 'Unsubscribed';
    }
  }

  Color get _statusColor {
    switch (channel.subStatus) {
      case 'live':
        return AppTheme.greenBadge;
      case 'paper':
        return AppTheme.amberBadge;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpandable =
        channel.subStatus != 'none' && channel.subStatus != 'off';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border.all(color: AppTheme.surfaceBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _accentColor, width: 3)),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text('#',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5))),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    channel.channelName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textColor),
                  ),
                ),
                StatusBadge(text: _statusLabel, color: _statusColor),
              ],
            ),
            const SizedBox(height: 4),
            // Meta
            Text(
              'Last msg: ${timeSince(channel.lastMessageAt)} · Last ping: ${timeSince(channel.lastHeartbeatAt)}',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),

            // Segmented control
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceGround.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: Row(
                children: [
                  _SegBtn(
                    label: '⚫ Off',
                    active: channel.subStatus == 'off' ||
                        channel.subStatus == 'none',
                    onTap: () => onSetStatus(channel, 'off'),
                  ),
                  _SegBtn(
                    label: '🟡 Paper',
                    active: channel.subStatus == 'paper',
                    activeColor: AppTheme.amberBadge,
                    onTap: () => onSetStatus(channel, 'paper'),
                  ),
                  _SegBtn(
                    label: '🟢 Live',
                    active: channel.subStatus == 'live',
                    activeColor: AppTheme.greenBadge,
                    onTap: () => onSetStatus(channel, 'live'),
                  ),
                ],
              ),
            ),

            // Expandable settings
            if (isExpandable) ...[
              const SizedBox(height: 12),
              const Divider(color: AppTheme.surfaceBorder, height: 1),
              const SizedBox(height: 12),

              // Target exchanges
              const Text('TARGET EXCHANGES',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.05)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: exchangeAccounts.map((acc) {
                  final active =
                      channel.exchangeAccountIds.contains(acc.id);
                  return GestureDetector(
                    onTap: () {
                      final ids = [...channel.exchangeAccountIds];
                      if (active) {
                        ids.remove(acc.id);
                      } else {
                        ids.add(acc.id);
                      }
                      onSendSubscription(
                          channel, {'exchange_account_ids': ids});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.primaryColor.withValues(alpha: 0.1)
                            : AppTheme.surfaceGround,
                        border: Border.all(
                          color: active
                              ? AppTheme.primaryColor
                              : AppTheme.surfaceBorder,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(acc.exchangeIcon,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(
                            acc.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? AppTheme.textColor
                                  : AppTheme.textSecondary,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.check,
                                size: 14, color: AppTheme.primaryColor),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // TP Rule
              _SettingRow(
                label: 'TP Rule',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGround,
                    border: Border.all(color: AppTheme.surfaceBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: channel.subscription?.tpRule ?? 'halving',
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(
                          color: AppTheme.textColor, fontSize: 13),
                      items: const [
                        DropdownMenuItem(
                            value: 'halving',
                            child: Text('Halving (50% each TP)')),
                        DropdownMenuItem(
                            value: 'equal_split',
                            child: Text('Equal Split')),
                        DropdownMenuItem(
                            value: 'manual', child: Text('Manual')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          onSendSubscription(channel, {'tp_rule': v});
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Auto-SL
              _SettingRow(
                label: 'Auto-SL after TP1',
                child: GestureDetector(
                  onTap: () {
                    onSendSubscription(channel, {
                      'auto_sl_after_tp1':
                          !(channel.subscription?.autoSlAfterTp1 ?? false)
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (channel.subscription?.autoSlAfterTp1 ?? false)
                          ? AppTheme.greenBadge.withValues(alpha: 0.15)
                          : AppTheme.surfaceGround,
                      border: Border.all(
                        color:
                            (channel.subscription?.autoSlAfterTp1 ?? false)
                                ? AppTheme.greenBadge
                                : AppTheme.surfaceBorder,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (channel.subscription?.autoSlAfterTp1 ?? false)
                          ? 'ON'
                          : 'OFF',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color:
                            (channel.subscription?.autoSlAfterTp1 ?? false)
                                ? AppTheme.greenBadge
                                : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Position size
              _SettingRow(
                label: 'Position Size',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGround,
                    border: Border.all(color: AppTheme.surfaceBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: channel.subscription?.positionSizeType ??
                          'min_qty',
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(
                          color: AppTheme.textColor, fontSize: 13),
                      items: const [
                        DropdownMenuItem(
                            value: 'min_qty',
                            child: Text('Exchange Min Qty')),
                        DropdownMenuItem(
                            value: 'tp_wise_min_qty',
                            child: Text('TP-wise Min Qty')),
                        DropdownMenuItem(
                            value: 'usd_amount',
                            child: Text('Specific USD Value')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          onSendSubscription(
                              channel, {'position_size_type': v});
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Footer
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => onManualCall(channel),
                  icon:
                      const Icon(Icons.campaign, size: 16),
                  label: const Text('Manual Call',
                      style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.surfaceBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => onDelete(channel.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  tooltip: 'Delete channel',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _SegBtn({
    required this.label,
    required this.active,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? (activeColor ?? AppTheme.textSecondary)
                    .withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active
                  ? (activeColor ?? AppTheme.textColor)
                  : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 0.05,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
