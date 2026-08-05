import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/widgets/fixora_mark.dart';
import '../../shared/widgets/gradient_button.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _bootstrapUsernameCtrl = TextEditingController();
  final _tenantIdCtrl = TextEditingController();
  bool _obscure = true;
  bool _showBootstrap = false;
  String? _tempPassword;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _bootstrapUsernameCtrl.dispose();
    _tenantIdCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillTenant());
  }

  Future<void> _prefillTenant() async {
    try {
      final health = ref.read(healthProvider).valueOrNull;
      final uid = health?.userId;
      if (uid != null && uid.isNotEmpty && _tenantIdCtrl.text.isEmpty) {
        _tenantIdCtrl.text = uid;
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    final ok = await ref.read(authProvider.notifier).login(
          _usernameCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (!ok || !mounted) return;
    final auth = ref.read(authProvider);
    if (auth.user?.mustChangePassword == true) {
      context.go('/change-password');
    } else {
      context.go('/');
    }
  }

  Future<void> _bootstrap() async {
    final temp = await ref.read(authProvider.notifier).bootstrapAdmin(
          username: _bootstrapUsernameCtrl.text.trim(),
          tenantUserId: _tenantIdCtrl.text.trim().isEmpty
              ? null
              : _tenantIdCtrl.text.trim(),
        );
    if (!mounted) return;
    if (temp != null) {
      setState(() {
        _tempPassword = temp;
        _usernameCtrl.text = _bootstrapUsernameCtrl.text.trim();
        _passwordCtrl.text = temp;
        _showBootstrap = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated && !auth.user!.mustChangePassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const FixoraMark(size: 36, elevated: false),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Sign in to $kProductName', style: theme.headlineSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                if (auth.loading && !auth.initialized)
                  const Center(child: CircularProgressIndicator()),
                if (auth.needsAdmin && _showBootstrap) ...[
                  Text(
                    'Create the first administrator account. '
                    'You will receive a temporary password to sign in, then must set a new password.',
                    style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _bootstrapUsernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Admin username',
                      hintText: 'e.g. admin',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _tenantIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Machine user ID (optional)',
                      helperText:
                          'Scopes repos/settings — pre-filled from existing install if set.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GradientButton(
                    label: 'Create administrator',
                    onPressed: auth.loading ? null : _bootstrap,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => setState(() => _showBootstrap = false),
                    child: const Text('Back to sign in'),
                  ),
                ] else ...[
                  if (auth.needsAdmin) ...[
                    Text(
                      'No administrator exists yet. Create one before signing in.',
                      style: theme.bodySmall?.copyWith(color: palette.warning),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => setState(() => _showBootstrap = true),
                      child: const Text('Create administrator'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  TextField(
                    controller: _usernameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  if (_tempPassword != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Temporary password (copy now — it will not be shown again):',
                      style: theme.bodySmall?.copyWith(color: palette.success),
                    ),
                    SelectableText(
                      _tempPassword!,
                      style: theme.titleMedium?.copyWith(color: palette.primary),
                    ),
                  ],
                  if (auth.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      auth.error!,
                      style: theme.bodySmall?.copyWith(color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  GradientButton(
                    label: auth.loading ? 'Signing in…' : 'Sign in',
                    onPressed: auth.loading ? null : _login,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
