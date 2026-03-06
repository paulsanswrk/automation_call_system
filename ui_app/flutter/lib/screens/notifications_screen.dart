import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/discord_message.dart';
import '../models/trade_action.dart';
import '../services/api_service.dart';
import '../services/system_ws_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<DiscordMessage> _messages = [];
  List<TradeAction> _tradeActions = [];
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;
  String _filterChannel = '';
  DiscordMessage? _selectedMessage;

  // Real-time WebSocket
  final SystemWsService _wsService = SystemWsService();
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  int _newMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  void _connectWebSocket() {
    _wsService.connect(
      newMessageCallback: (data) {
        // A new Discord message arrived — prepend to the list immediately
        try {
          final msg = DiscordMessage.fromJson(data);
          // If we're filtering and this message doesn't match, skip it
          if (_filterChannel.isNotEmpty &&
              msg.channelName != _filterChannel) {
            return;
          }
          if (mounted) {
            setState(() {
              _messages.insert(0, msg);
              _newMessageCount++;
            });
          }
        } catch (_) {}
      },
      tradeEventCallback: (eventType, data) {
        // When a new trade action arrives, refresh trade actions
        if (eventType == 'new_trade_action') {
          try {
            final action = TradeAction.fromJson(data);
            if (mounted) {
              setState(() {
                _tradeActions.insert(0, action);
              });
            }
          } catch (_) {
            // Fallback: full refresh
            _fetchTradeActions();
          }
        }
      },
    );
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      String msgUrl = '/api/messages';
      if (_filterChannel.isNotEmpty) {
        msgUrl += '?channel_name=${Uri.encodeComponent(_filterChannel)}';
      }
      final results = await Future.wait([
        ApiService.get(msgUrl),
        ApiService.get('/api/trade-actions'),
        ApiService.get('/api/channels'),
      ]);

      if (results[0].statusCode == 200) {
        final list = jsonDecode(results[0].body) as List;
        _messages = list.map((e) => DiscordMessage.fromJson(e)).toList();
      }
      if (results[1].statusCode == 200) {
        final json = jsonDecode(results[1].body);
        final list = (json is Map ? json['data'] : json) as List? ?? [];
        _tradeActions = list.map((e) => TradeAction.fromJson(e)).toList();
      }
      if (results[2].statusCode == 200) {
        final list = jsonDecode(results[2].body) as List;
        _channels = list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _newMessageCount = 0;
        });
      }
    }
  }

  Future<void> _fetchTradeActions() async {
    try {
      final res = await ApiService.get('/api/trade-actions');
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json is Map ? json['data'] : json) as List? ?? [];
        if (mounted) {
          setState(() {
            _tradeActions = list.map((e) => TradeAction.fromJson(e)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Map<String, List<TradeAction>> get _tradeActionsByMsg {
    final map = <String, List<TradeAction>>{};
    for (final action in _tradeActions) {
      final key = action.discordMessageId;
      if (key == null || key.isEmpty) continue;
      map.putIfAbsent(key, () => []).add(action);
    }
    return map;
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    border: Border.all(color: AppTheme.surfaceBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterChannel.isEmpty ? null : _filterChannel,
                      hint: const Text('All Channels',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14)),
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(
                          color: AppTheme.textColor, fontSize: 14),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('All Channels')),
                        ..._channels.map((ch) {
                          final name = ch['channel_name'] as String? ?? '';
                          return DropdownMenuItem(
                              value: name, child: Text('#$name'));
                        }),
                      ],
                      onChanged: (v) {
                        setState(() => _filterChannel = v ?? '');
                        _fetchData();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Live indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.greenBadge.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveDot(),
                    SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.greenBadge,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _fetchData,
                icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No messages yet',
                      subtitle:
                          'Discord trade calls will appear here when they arrive.',
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchData,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final actions =
                              _tradeActionsByMsg[msg.messageId] ?? [];
                          final isNew = index < _newMessageCount;
                          return _MessageCard(
                            message: msg,
                            actions: actions,
                            formatTime: _formatTime,
                            isNew: isNew,
                            onTap: () =>
                                setState(() => _selectedMessage = msg),
                          );
                        },
                      ),
                    ),
        ),

        // Detail bottom sheet
        if (_selectedMessage != null) _buildDetailSheet(),
      ],
    );
  }

  Widget _buildDetailSheet() {
    final msg = _selectedMessage!;
    final actions = _tradeActionsByMsg[msg.messageId] ?? [];

    return GestureDetector(
      onTap: () => setState(() => _selectedMessage = null),
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {}, // prevent dismissal on inner tap
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Discord Message',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _DetailRow('Author', msg.author),
                  _DetailRow('Channel', '#${msg.channelName}'),
                  _DetailRow(
                      'Time',
                      DateTime.tryParse(msg.receivedAt)
                              ?.toLocal()
                              .toString() ??
                          msg.receivedAt),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGround,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      msg.textContent,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: AppTheme.textColor),
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Trade Actions',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...actions.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGround,
                              border:
                                  Border.all(color: AppTheme.surfaceBorder),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ActionBadge(action: a.action ?? ''),
                                if (a.exchange != null)
                                  _DetailRow('Exchange', a.exchange!),
                                if (a.symbol != null)
                                  _DetailRow('Symbol', a.symbol!),
                                if (a.side != null)
                                  _DetailRow('Side', a.side!),
                                if (a.price != null)
                                  _DetailRow('Price', a.price!),
                                if (a.qty != null)
                                  _DetailRow('Qty', a.qty!),
                                if (a.slPrice != null)
                                  _DetailRow('Stop Loss', a.slPrice!),
                                if (a.notes != null && a.notes!.isNotEmpty)
                                  _DetailRow('Notes', a.notes!),
                              ],
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.textColor)),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final DiscordMessage message;
  final List<TradeAction> actions;
  final String Function(String?) formatTime;
  final bool isNew;
  final VoidCallback onTap;

  const _MessageCard({
    required this.message,
    required this.actions,
    required this.formatTime,
    this.isNew = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isNew
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : AppTheme.surfaceCard,
          border: Border.all(
            color: isNew
                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                : AppTheme.surfaceBorder,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Meta row
            Row(
              children: [
                if (isNew)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  message.author,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '#${message.channelName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryHover,
                  ),
                ),
                const Spacer(),
                Text(
                  formatTime(message.receivedAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Message text (truncated)
            Text(
              message.textContent,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            // Trade action badges
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: actions
                    .map((a) => ActionBadge(action: a.action ?? ''))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
