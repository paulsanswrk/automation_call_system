import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trade_action.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class TradeActionsScreen extends ConsumerStatefulWidget {
  const TradeActionsScreen({super.key});

  @override
  ConsumerState<TradeActionsScreen> createState() =>
      _TradeActionsScreenState();
}

class _TradeActionsScreenState extends ConsumerState<TradeActionsScreen> {
  List<TradeAction> _actions = [];
  bool _loading = true;
  int _currentPage = 1;
  int _totalCount = 0;
  final int _limit = 25;
  String _filterAction = '';
  TradeAction? _selectedAction;

  int get _totalPages => (_totalCount / _limit).ceil();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData([int page = 1]) async {
    setState(() => _loading = true);
    try {
      String url = '/api/trade-actions?page=$page&limit=$_limit';
      if (_filterAction.isNotEmpty) {
        url += '&action=${Uri.encodeComponent(_filterAction)}';
      }
      final res = await ApiService.get(url);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json['data'] as List?) ?? [];
        _actions = list.map((e) => TradeAction.fromJson(e)).toList();
        _totalCount = (json['total'] as int?) ?? 0;
        _currentPage = (json['page'] as int?) ?? page;
      }
    } catch (e) {
      debugPrint('Fetch trade actions error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAction(int id) async {
    try {
      final res = await ApiService.delete('/api/trade-actions/$id');
      if (res.statusCode == 200) _fetchData(_currentPage);
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatJSON(dynamic val) {
    if (val == null) return '';
    if (val is String) {
      try {
        return const JsonEncoder.withIndent('  ')
            .convert(jsonDecode(val));
      } catch (_) {
        return val;
      }
    }
    return const JsonEncoder.withIndent('  ').convert(val);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    return Column(
      children: [
        // Filter row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    border: Border.all(color: AppTheme.surfaceBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value:
                          _filterAction.isEmpty ? null : _filterAction,
                      hint: const Text('All Actions',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14)),
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(
                          color: AppTheme.textColor, fontSize: 14),
                      items: const [
                        DropdownMenuItem(
                            value: '', child: Text('All Actions')),
                        DropdownMenuItem(
                            value: 'PLACE_ORDER',
                            child: Text('PLACE_ORDER')),
                        DropdownMenuItem(
                            value: 'SKIP', child: Text('SKIP')),
                        DropdownMenuItem(
                            value: 'ERROR', child: Text('ERROR')),
                        DropdownMenuItem(
                            value: 'AUTO_SL_BREAKEVEN',
                            child: Text('AUTO_SL_BREAKEVEN')),
                      ],
                      onChanged: (v) {
                        _filterAction = v ?? '';
                        _fetchData(1);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _fetchData(1),
                icon:
                    const Icon(Icons.refresh, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Content
        Expanded(
          child: _loading && _actions.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _actions.isEmpty
                  ? const EmptyState(
                      icon: Icons.list_alt,
                      title: 'No Trade Actions',
                      subtitle:
                          'Trade actions will appear here when the AI evaluates a call.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _fetchData(_currentPage),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _actions.length,
                        itemBuilder: (context, index) {
                          final action = _actions[index];
                          return _TradeActionCard(
                            action: action,
                            formatTime: _formatTime,
                            isAdmin: isAdmin,
                            onDelete: () => _deleteAction(action.id),
                            onTap: () =>
                                setState(() => _selectedAction = action),
                          );
                        },
                      ),
                    ),
        ),

        // Pagination
        if (_actions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _currentPage > 1
                      ? () => _fetchData(_currentPage - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 16),
                Text(
                  'Page $_currentPage of ${_totalPages > 0 ? _totalPages : 1}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _currentPage < _totalPages
                      ? () => _fetchData(_currentPage + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),

        // Detail sheet
        if (_selectedAction != null)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedAction = null),
              child: Container(
                color: Colors.black54,
                child: GestureDetector(
                  onTap: () {},
                  child: _TradeActionDetail(
                    action: _selectedAction!,
                    formatJSON: _formatJSON,
                    onClose: () =>
                        setState(() => _selectedAction = null),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TradeActionCard extends StatelessWidget {
  final TradeAction action;
  final String Function(String?) formatTime;
  final bool isAdmin;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _TradeActionCard({
    required this.action,
    required this.formatTime,
    required this.isAdmin,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border.all(color: AppTheme.surfaceBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              children: [
                ActionBadge(action: action.action ?? ''),
                const SizedBox(width: 8),
                if (action.exchange != null)
                  ExchangeBadge(exchange: action.exchange!),
                const Spacer(),
                Text(
                  formatTime(action.createdAt),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline,
                        size: 16,
                        color:
                            AppTheme.textSecondary.withValues(alpha: 0.5)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Details
            Row(
              children: [
                if (action.symbol != null) ...[
                  Text(
                    action.symbol!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textColor),
                  ),
                  const SizedBox(width: 8),
                ],
                if (action.side != null)
                  StatusBadge(
                    text: action.side!,
                    color: action.side == 'LONG' || action.side == 'BUY'
                        ? AppTheme.greenBadge
                        : AppTheme.redBadge,
                  ),
                const Spacer(),
                if (action.price != null)
                  Text(action.price!,
                      style: AppTheme.mono),
              ],
            ),
            if (action.notes != null && action.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                action.notes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TradeActionDetail extends StatelessWidget {
  final TradeAction action;
  final String Function(dynamic) formatJSON;
  final VoidCallback onClose;

  const _TradeActionDetail({
    required this.action,
    required this.formatJSON,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Handle & close
            Row(
              children: [
                const Spacer(),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Trade Action Details',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (action.createdAt != null)
              _row('Time', DateTime.tryParse(action.createdAt!)
                      ?.toLocal()
                      .toString() ??
                  action.createdAt!),
            _row('Action', action.action ?? ''),
            if (action.exchange != null) _row('Exchange', action.exchange!),
            if (action.symbol != null) _row('Symbol', action.symbol!),
            if (action.side != null) _row('Side', action.side!),
            if (action.orderType != null)
              _row('Order Type', action.orderType!),
            if (action.price != null) _row('Price', action.price!),
            if (action.qty != null) _row('Qty', action.qty!),
            if (action.orderId != null) _row('Order ID', action.orderId!),
            if (action.notes != null) _row('Notes', action.notes!),
            if (action.request != null) ...[
              const SizedBox(height: 16),
              const Text('API Request',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  formatJSON(action.request),
                  style: AppTheme.monoSmall,
                ),
              ),
            ],
            if (action.result != null) ...[
              const SizedBox(height: 16),
              const Text('API Result',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  formatJSON(action.result),
                  style: AppTheme.monoSmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textColor)),
          ),
        ],
      ),
    );
  }
}
