import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/exchange_account.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class ExchangeAccountsScreen extends StatefulWidget {
  const ExchangeAccountsScreen({super.key});

  @override
  State<ExchangeAccountsScreen> createState() =>
      _ExchangeAccountsScreenState();
}

class _ExchangeAccountsScreenState extends State<ExchangeAccountsScreen> {
  List<ExchangeAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
  }

  Future<void> _fetchAccounts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.get('/api/exchange-accounts');
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _accounts = list.map((e) => ExchangeAccount.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Fetch accounts error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount(int id, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: const Text('Remove Account'),
        content: Text('Remove "$label"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.redBadge),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService.delete('/api/exchange-accounts/$id');
      if (res.statusCode == 200) _fetchAccounts();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  void _showAddAccountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddAccountSheet(onAdded: _fetchAccounts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading && _accounts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No Exchange Accounts',
                  subtitle:
                      'Connect an exchange by adding your API keys. Keys are encrypted at rest.',
                  action: ElevatedButton.icon(
                    onPressed: _showAddAccountSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Your First Account'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchAccounts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _accounts.length,
                    itemBuilder: (context, index) {
                      return _AccountCard(
                        account: _accounts[index],
                        onDelete: _deleteAccount,
                      );
                    },
                  ),
                ),
      floatingActionButton: _accounts.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showAddAccountSheet,
              backgroundColor: AppTheme.primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

class _AccountCard extends StatelessWidget {
  final ExchangeAccount account;
  final Function(int, String) onDelete;

  const _AccountCard({required this.account, required this.onDelete});

  Color get _accentColor {
    switch (account.exchangeType) {
      case 'bitunix':
        return AppTheme.greenBadge;
      case 'phemex':
        return AppTheme.primaryColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border.all(color: AppTheme.surfaceBorder),
        borderRadius: BorderRadius.circular(14),
        // Accent left border
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _accentColor, width: 3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  // Exchange icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(account.exchangeIcon,
                        style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textColor,
                          ),
                        ),
                        Text(
                          account.exchangeDisplayName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badges
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadge(
                        text: account.isActive ? 'ACTIVE' : 'INACTIVE',
                        color: account.isActive
                            ? AppTheme.greenBadge
                            : AppTheme.textSecondary,
                      ),
                      if (account.isActive) ...[
                        const SizedBox(height: 4),
                        StatusBadge(
                          text:
                              account.isConnected ? 'CONNECTED' : 'ERROR',
                          color: account.isConnected
                              ? AppTheme.greenBadge
                              : AppTheme.redBadge,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceGround.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    if (account.availableBalance != null &&
                        account.availableBalance!.isNotEmpty)
                      _detailRow(
                        'Balance',
                        '\$${account.availableBalance}',
                        valueColor:
                            (double.tryParse(account.availableBalance!) ??
                                        0) >
                                    0
                                ? AppTheme.greenBadge
                                : null,
                        isMono: true,
                      ),
                    _detailRow('API Key', account.apiKeyMasked, isMono: true),
                    _detailRow('Added', _formatDate(account.createdAt)),
                  ],
                ),
              ),

              // Error banner
              if (account.lastError != null &&
                  account.lastError!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.redBadge.withValues(alpha: 0.08),
                    border: Border.all(
                        color: AppTheme.redBadge.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 16, color: AppTheme.redBadge),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          account.lastError!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.redBadge,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock, size: 14,
                          color: AppTheme.greenBadge.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text('Encrypted',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  AppTheme.greenBadge.withValues(alpha: 0.7))),
                    ],
                  ),
                  IconButton(
                    onPressed: () =>
                        onDelete(account.id, account.label),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    tooltip: 'Remove account',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {Color? valueColor, bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.04,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? AppTheme.textColor,
              fontWeight: valueColor != null ? FontWeight.w700 : null,
              fontFamily: isMono ? 'JetBrains Mono' : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ─── Add Account Bottom Sheet ───

class _AddAccountSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddAccountSheet({required this.onAdded});

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  String _exchangeType = 'bitunix';
  final _labelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();
  bool _showApiKey = false;
  bool _showSecretKey = false;
  bool _submitting = false;
  String? _error;

  bool get _formValid =>
      _labelCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      _secretKeyCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formValid) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiService.post('/api/exchange-accounts', body: {
        'exchange_type': _exchangeType,
        'label': _labelCtrl.text.trim(),
        'api_key': _apiKeyCtrl.text.trim(),
        'secret_key': _secretKeyCtrl.text.trim(),
      });
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) Navigator.pop(context);
        widget.onAdded();
      } else {
        final body = jsonDecode(res.body);
        setState(
            () => _error = body['error'] as String? ?? 'Failed to add account');
      }
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Exchange Account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            // Security info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.greenBadge.withValues(alpha: 0.06),
                border: Border.all(
                    color: AppTheme.greenBadge.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield, color: AppTheme.greenBadge, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your API keys are encrypted with AES-256 before storage.',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Exchange selector
            const Text('EXCHANGE',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.05)),
            const SizedBox(height: 8),
            Row(
              children: [
                _exchangeOption('bitunix', '⚡', 'BitUnix'),
                const SizedBox(width: 10),
                _exchangeOption('phemex', '🔷', 'Phemex'),
              ],
            ),
            const SizedBox(height: 16),

            // Label
            _buildField('LABEL', _labelCtrl, 'e.g. My Main Account'),
            const SizedBox(height: 12),

            // API Key
            _buildField('API KEY', _apiKeyCtrl, 'Paste your API key',
                obscure: !_showApiKey,
                toggleObscure: () =>
                    setState(() => _showApiKey = !_showApiKey)),
            const SizedBox(height: 12),

            // Secret Key
            _buildField('SECRET KEY', _secretKeyCtrl, 'Paste your secret key',
                obscure: !_showSecretKey,
                toggleObscure: () =>
                    setState(() => _showSecretKey = !_showSecretKey)),
            const SizedBox(height: 20),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 16, color: AppTheme.redBadge),
                    const SizedBox(width: 6),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppTheme.redBadge, fontSize: 13)),
                  ],
                ),
              ),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.surfaceBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting || !_formValid ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Add Account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _exchangeOption(String type, String icon, String name) {
    final selected = _exchangeType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _exchangeType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.08)
                : AppTheme.surfaceGround,
            border: Border.all(
              color: selected ? AppTheme.primaryColor : AppTheme.surfaceBorder,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: selected
                        ? AppTheme.textColor
                        : AppTheme.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController ctrl, String hint,
      {bool obscure = false, VoidCallback? toggleObscure}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.05)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: toggleObscure != null
                ? IconButton(
                    onPressed: toggleObscure,
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                        color: AppTheme.textSecondary),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
