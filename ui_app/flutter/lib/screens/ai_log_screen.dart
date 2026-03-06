import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_log.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class AILogScreen extends ConsumerStatefulWidget {
  const AILogScreen({super.key});

  @override
  ConsumerState<AILogScreen> createState() => _AILogScreenState();
}

class _AILogScreenState extends ConsumerState<AILogScreen> {
  List<AILog> _logs = [];
  bool _loading = true;
  int _currentPage = 1;
  int _totalCount = 0;
  final int _limit = 25;
  AILog? _selectedLog;

  int get _totalPages => (_totalCount / _limit).ceil();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData([int page = 1]) async {
    setState(() => _loading = true);
    try {
      final url = '/api/ai-log?page=$page&limit=$_limit';
      final res = await ApiService.get(url);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json['data'] as List?) ?? [];
        _logs = list.map((e) => AILog.fromJson(e)).toList();
        _totalCount = (json['total'] as int?) ?? 0;
        _currentPage = (json['page'] as int?) ?? page;
      }
    } catch (e) {
      debugPrint('Fetch AI logs error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteLog(int id) async {
    try {
      final res = await ApiService.delete('/api/ai-log/$id');
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

  String _formatCost(double? val) {
    if (val == null || val == 0) return '—';
    return '\$${val.toStringAsFixed(4)}';
  }

  String _truncate(String? str, int len) {
    if (str == null || str.isEmpty) return '—';
    if (str.length <= len) return str;
    return '${str.substring(0, len)}...';
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: () => _fetchData(1),
                icon:
                    const Icon(Icons.refresh, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _loading && _logs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? const EmptyState(
                      icon: Icons.smart_toy_outlined,
                      title: 'No AI Logs',
                      subtitle:
                          'AI processing logs will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _fetchData(_currentPage),
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return _AILogCard(
                            log: log,
                            formatTime: _formatTime,
                            formatCost: _formatCost,
                            truncate: _truncate,
                            isAdmin: isAdmin,
                            onDelete: () => _deleteLog(log.id),
                            onTap: () =>
                                setState(() => _selectedLog = log),
                          );
                        },
                      ),
                    ),
        ),

        // Pagination
        if (_logs.isNotEmpty)
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

        // Detail
        if (_selectedLog != null)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedLog = null),
              child: Container(
                color: Colors.black54,
                child: GestureDetector(
                  onTap: () {},
                  child: _AILogDetail(
                    log: _selectedLog!,
                    onClose: () =>
                        setState(() => _selectedLog = null),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AILogCard extends StatelessWidget {
  final AILog log;
  final String Function(String?) formatTime;
  final String Function(double?) formatCost;
  final String Function(String?, int) truncate;
  final bool isAdmin;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _AILogCard({
    required this.log,
    required this.formatTime,
    required this.formatCost,
    required this.truncate,
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
                // Model badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        AppTheme.textSecondary.withValues(alpha: 0.12),
                    border: Border.all(
                        color: AppTheme.textSecondary
                            .withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.model ?? 'unknown',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Tokens
                Text(
                  '${log.tokensIn ?? 0} → ${log.tokensOut ?? 0} tokens',
                  style: AppTheme.monoSmall,
                ),
                const Spacer(),
                Text(
                  formatTime(log.createdAt),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline,
                        size: 16,
                        color: AppTheme.textSecondary
                            .withValues(alpha: 0.5)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Cost
            Text(
              formatCost(log.costUsd),
              style: TextStyle(
                fontSize: 13,
                color: (log.costUsd ?? 0) > 0
                    ? AppTheme.redBadge
                    : AppTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(height: 6),
            // Prompt & response previews
            Text(
              truncate(log.userPrompt, 60),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AILogDetail extends StatelessWidget {
  final AILog log;
  final VoidCallback onClose;

  const _AILogDetail({required this.log, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
            const Text('Log Details',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _row('Time',
                DateTime.tryParse(log.createdAt ?? '')?.toLocal().toString() ??
                    log.createdAt ?? ''),
            _row('Model', log.model ?? '—'),
            _row('Tokens In', '${log.tokensIn ?? 0}'),
            _row('Tokens Out', '${log.tokensOut ?? 0}'),
            _row('Cost', '\$${log.costUsd ?? 0}'),

            if (log.userPrompt != null && log.userPrompt!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('User Prompt',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: log.userPrompt!));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    color: AppTheme.textSecondary,
                    tooltip: 'Copy',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  log.userPrompt!,
                  style: AppTheme.monoSmall,
                ),
              ),
            ],

            if (log.response != null && log.response!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('AI Response',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  log.response!,
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
