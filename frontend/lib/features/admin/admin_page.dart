import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/soft_panel.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/one_time_secret_card.dart';

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic> _security = {};
  bool _repoReadonly = false;

  final _newUsernameCtrl = TextEditingController();
  final _newTenantCtrl = TextEditingController();
  String _newRole = 'user';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newUsernameCtrl.dispose();
    _newTenantCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final usersRes = await api.getJson(Endpoints.authUsers);
      final secRes = await api.getJson(Endpoints.authSecuritySettings);
      final usersRaw = (usersRes as Map)['users'] as List? ?? [];
      _users = usersRaw
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
      final secMap = (secRes as Map).cast<String, dynamic>();
      _security = (secMap['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      _repoReadonly = secMap['repo_data_readonly'] == true;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createUser() async {
    final username = _newUsernameCtrl.text.trim();
    if (username.isEmpty) return;
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.postJson(
        Endpoints.authUsers,
        body: {
          'username': username,
          if (_newTenantCtrl.text.trim().isNotEmpty)
            'tenant_user_id': _newTenantCtrl.text.trim(),
          'role': _newRole,
        },
      );
      final temp = (res as Map)['temp_password']?.toString();
      await _load();
      if (temp != null && mounted) {
        await _showTempPasswordDialog(username, temp);
      }
      _newUsernameCtrl.clear();
      _newTenantCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showTempPasswordDialog(String username, String temp) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.palette.border),
        ),
        title: Text('Temporary password for $username'),
        content: SingleChildScrollView(
          child: OneTimeSecretCard(
            secret: temp,
            message:
                'Share this password securely. The user must sign in and set a new password.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String userId, String username) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.postJson(Endpoints.authUserResetPassword(userId));
      final temp = (res as Map)['temp_password']?.toString();
      if (temp != null) await _showTempPasswordDialog(username, temp);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleBlock(Map<String, dynamic> user) async {
    final id = user['id']?.toString() ?? '';
    final status = user['status'] == 'blocked' ? 'active' : 'blocked';
    try {
      final api = ref.read(apiClientProvider);
      await api.patchJson(Endpoints.authUser(id), body: {'status': status});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteUser(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteJson(Endpoints.authUser(id));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _saveSecurity() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.postJson(
        Endpoints.authSecuritySettings,
        body: {
          'session_hours': _security['session_hours'],
          'max_failed_logins': _security['max_failed_logins'],
          'lockout_minutes': _security['lockout_minutes'],
          'min_password_length': _security['min_password_length'],
        },
      );
      await api.postJson(
        Endpoints.authRepoReadonly,
        body: {'repo_data_readonly': _repoReadonly},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Security settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final me = ref.watch(authProvider).user;

    if (me == null || !me.isAdmin) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Admin only',
        subtitle: 'Sign in with an administrator account to manage users and security.',
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Administration', style: theme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Manage users, security policy, and read-only mode.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              SoftPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  _repoReadonly
                      ? 'Repo data is currently read-only on this machine.'
                      : 'Changes here apply immediately to authentication and security policy.',
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: TextStyle(color: palette.danger)),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text('Users', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                child: Column(
                  children: [
                    for (final u in _users)
                      ListTile(
                        title: Text(u['username']?.toString() ?? ''),
                        subtitle: Text(
                          '${u['role']} · ${u['status']}'
                          '${u['must_change_password'] == true ? ' · must change password' : ''}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Reset temp password',
                              icon: const Icon(Icons.lock_reset),
                              onPressed: () => _resetPassword(
                                u['id']?.toString() ?? '',
                                u['username']?.toString() ?? '',
                              ),
                            ),
                            IconButton(
                              tooltip: u['status'] == 'blocked'
                                  ? 'Unblock'
                                  : 'Block',
                              icon: Icon(
                                u['status'] == 'blocked'
                                    ? Icons.check_circle_outline
                                    : Icons.block,
                              ),
                              onPressed: u['id'] == me.id
                                  ? null
                                  : () => _toggleBlock(u),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: u['id'] == me.id
                                  ? null
                                  : () => _deleteUser(u['id']?.toString() ?? ''),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Add user', style: theme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _newUsernameCtrl,
                        decoration: const InputDecoration(labelText: 'Username'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _newTenantCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Machine user ID (optional)',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        value: _newRole,
                        items: const [
                          DropdownMenuItem(value: 'user', child: Text('User')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _newRole = v);
                        },
                        decoration: const InputDecoration(labelText: 'Role'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      GradientButton(
                        label: 'Create user',
                        icon: Icons.person_add_outlined,
                        onPressed: _createUser,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('Security settings', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      _numField(
                        label: 'Session lifetime (hours)',
                        value: _security['session_hours'] as int? ?? 24,
                        onChanged: (v) =>
                            _security['session_hours'] = v,
                      ),
                      _numField(
                        label: 'Max failed logins',
                        value: _security['max_failed_logins'] as int? ?? 5,
                        onChanged: (v) =>
                            _security['max_failed_logins'] = v,
                      ),
                      _numField(
                        label: 'Lockout (minutes)',
                        value: _security['lockout_minutes'] as int? ?? 15,
                        onChanged: (v) =>
                            _security['lockout_minutes'] = v,
                      ),
                      _numField(
                        label: 'Minimum password length',
                        value: _security['min_password_length'] as int? ?? 12,
                        onChanged: (v) =>
                            _security['min_password_length'] = v,
                      ),
                      SwitchListTile(
                        title: const Text('Repo data read-only'),
                        subtitle: const Text(
                          'Disables repo/settings writes for all users',
                        ),
                        value: _repoReadonly,
                        onChanged: (v) => setState(() => _repoReadonly = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GradientButton(
                          label: 'Save security settings',
                          onPressed: _saveSecurity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (s) {
          final n = int.tryParse(s.trim());
          if (n != null) onChanged(n);
        },
      ),
    );
  }
}
