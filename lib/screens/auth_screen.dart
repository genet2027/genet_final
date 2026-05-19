import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../theme/app_theme.dart';

/// Basic email/password Firebase auth for parent or child before pairing.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.role,
    this.onAuthenticated,
  });

  final String role;
  final VoidCallback? onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  bool get _isParent => widget.role == 'parent';

  String get _title => _isParent ? 'התחברות הורה' : 'התחברות ילד';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _hebrewAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'כתובת האימייל אינה תקינה.';
      case 'user-disabled':
        return 'החשבון הושבת.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'אימייל או סיסמה שגויים.';
      case 'email-already-in-use':
        return 'כתובת האימייל כבר בשימוש.';
      case 'weak-password':
        return 'הסיסמה חלשה מדי. בחר סיסמה ארוכה יותר.';
      case 'network-request-failed':
        return 'בעיית רשת. בדוק את החיבור לאינטרנט.';
      default:
        return 'שגיאת התחברות. נסה שוב.';
    }
  }

  Future<void> _completeAuthSuccess() async {
    await GenetConfig.commitUserRole(widget.role);
    if (!mounted) return;
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('יש למלא אימייל וסיסמה.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _completeAuthSuccess();
    } on FirebaseAuthException catch (e) {
      _showError(_hebrewAuthError(e));
    } catch (_) {
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('יש למלא אימייל וסיסמה.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _completeAuthSuccess();
    } on FirebaseAuthException catch (e) {
      _showError(_hebrewAuthError(e));
    } catch (_) {
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _loading ? null : () => Navigator.pop(context, false),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.darkBlue,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'אימייל',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'סיסמה',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signIn(),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('התחבר'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _register,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('צור חשבון'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
