import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import '../repositories/child_profile_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import '../theme/app_theme.dart';
import 'child_home_screen.dart';
import 'child_link_screen.dart';
import 'child_self_identify_screen.dart';
import 'parent_profile_setup_screen.dart';
import 'parent_shell.dart';

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
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _verificationBusy = false;
  bool _isLoginMode = true;
  bool _waitingForEmailVerification = false;
  bool _emailVerifyFromLogin = false;
  String? _pendingRegisterNextRoute;
  DateTime? _birthDate;

  bool get _isParent => widget.role == 'parent';

  String get _subtitle => _isParent ? 'התחברות הורה' : 'התחברות ילד';

  String get _roleHelper =>
      _isParent ? 'ממשיך בתור הורה' : 'ממשיך בתור ילד';

  int? get _calculatedAge {
    if (_birthDate == null) return null;
    final today = DateTime.now();
    var age = today.year - _birthDate!.year;
    if (today.month < _birthDate!.month ||
        (today.month == _birthDate!.month && today.day < _birthDate!.day)) {
      age--;
    }
    return age;
  }

  String get _birthDateLabel {
    if (_birthDate == null) return 'תאריך לידה';
    return DateFormat('dd/MM/yyyy', 'he').format(_birthDate!);
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.backgroundLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
      ),
    );
  }

  void _onPrimaryAction() {
    if (_isLoginMode) {
      _signIn();
    } else {
      _register();
    }
  }

  void _toggleMode() {
    if (_loading) return;
    setState(() => _isLoginMode = !_isLoginMode);
  }

  Future<void> _onForgotPassword() async {
    debugPrint('[GENET][PASSWORD_RESET] pressed');
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      debugPrint('[GENET][PASSWORD_RESET] email_empty');
      _showError('הכנס אימייל כדי לאפס סיסמה');
      return;
    }
    debugPrint('[GENET][PASSWORD_RESET] send_attempt email=$email');
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      debugPrint('[GENET][PASSWORD_RESET] send_success');
      _showMessage('שלחנו קישור לאיפוס סיסמה למייל');
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[GENET][PASSWORD_RESET] send_error code=${e.code} message=${e.message}',
      );
      _showError('${_hebrewPasswordResetError(e)} (${e.code})');
    } catch (e) {
      debugPrint('[GENET][PASSWORD_RESET] send_error code=unexpected message=$e');
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 10),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('he'),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  String? _validateRegister() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (firstName.isEmpty) {
      return 'יש למלא שם פרטי.';
    }
    if (lastName.isEmpty) {
      return 'יש למלא שם משפחה.';
    }
    if (_birthDate == null) {
      return 'יש לבחור תאריך לידה.';
    }
    final today = DateTime.now();
    final birthDay = DateTime(_birthDate!.year, _birthDate!.month, _birthDate!.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    if (birthDay.isAfter(todayDay)) {
      return 'תאריך לידה לא יכול להיות בעתיד.';
    }
    if (phone.isEmpty) {
      return 'יש למלא מספר פלאפון.';
    }
    if (email.isEmpty) {
      return 'יש למלא אימייל.';
    }
    if (!_isValidEmail(email)) {
      return 'יש להזין אימייל תקין';
    }
    if (password.isEmpty) {
      return 'יש למלא סיסמה.';
    }
    if (password.length < 6) {
      return 'הסיסמה חלשה מדי. בחר סיסמה ארוכה יותר.';
    }
    if (confirmPassword.isEmpty) {
      return 'יש למלא אימות סיסמה.';
    }
    if (password != confirmPassword) {
      return 'הסיסמאות לא תואמות';
    }
    return null;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _confirmPasswordController.dispose();
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<User?> _reloadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    await user.reload();
    return FirebaseAuth.instance.currentUser;
  }

  Future<String> _reloadForEmailVerifyDiag() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'currentUser=null';
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      return 'emailVerified=${refreshed?.emailVerified} uid=${refreshed?.uid}';
    } catch (e) {
      return 'reload_error=$e';
    }
  }

  void _logEmailVerifyDiagSnapshot(User user, {required String reloadResult}) {
    final projectId =
        Firebase.apps.isNotEmpty ? Firebase.app().options.projectId : null;
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] projectId=$projectId');
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] uid=${user.uid}');
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] email=${user.email}');
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] emailVerified=${user.emailVerified}');
    debugPrint(
      '[GENET][EMAIL_VERIFY_DIAG] providerIds='
      '${user.providerData.map((p) => p.providerId).toList()}',
    );
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] reload() result=$reloadResult');
  }

  Future<void> _sendVerificationEmailWithDiag() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
      _exitEmailVerificationGate();
      return;
    }
    final reloadResult = await _reloadForEmailVerifyDiag();
    final snapshotUser = FirebaseAuth.instance.currentUser ?? user;
    _logEmailVerifyDiagSnapshot(snapshotUser, reloadResult: reloadResult);
    debugPrint('[GENET][EMAIL_VERIFY_DIAG] SEND_ATTEMPT');
    try {
      await snapshotUser.sendEmailVerification();
      debugPrint('[GENET][EMAIL_VERIFY_DIAG] SEND_SUCCESS');
      debugPrint('[GENET][EMAIL_VERIFY] sent');
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[GENET][EMAIL_VERIFY_DIAG] SEND_ERROR code=${e.code} message=${e.message}',
      );
      rethrow;
    }
  }

  void _enterEmailVerificationGate({
    required bool fromLogin,
    String? registerNextRoute,
  }) {
    debugPrint(
      '[GENET][EMAIL_VERIFY] gate source=${fromLogin ? "login" : "register"}',
    );
    setState(() {
      _waitingForEmailVerification = true;
      _emailVerifyFromLogin = fromLogin;
      _pendingRegisterNextRoute = registerNextRoute;
    });
  }

  void _exitEmailVerificationGate() {
    setState(() => _waitingForEmailVerification = false);
  }

  Future<void> _sendVerificationEmail() async {
    await _sendVerificationEmailWithDiag();
  }

  Future<void> _continueAfterEmailVerified() async {
    if (_emailVerifyFromLogin) {
      await _completeAuthSuccess(isLoginMode: true);
      return;
    }
    final nextRoute = _pendingRegisterNextRoute;
    if (nextRoute == null) {
      _showError('שגיאת ניווט. נסה שוב.');
      return;
    }
    await _navigateAfterRegister(nextRoute: nextRoute);
  }

  Future<void> _onCheckEmailVerified() async {
    setState(() => _verificationBusy = true);
    try {
      final reloadResult = await _reloadForEmailVerifyDiag();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint(
          '[GENET][EMAIL_VERIFY_DIAG] reload() result=$reloadResult',
        );
        _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
        _exitEmailVerificationGate();
        return;
      }
      _logEmailVerifyDiagSnapshot(user, reloadResult: reloadResult);
      debugPrint(
        '[GENET][EMAIL_VERIFY] checked verified=${user.emailVerified}',
      );
      if (user.emailVerified) {
        await _continueAfterEmailVerified();
        return;
      }
      _showMessage('האימייל עדיין לא אומת');
    } catch (e) {
      debugPrint('[GENET][AUTH][ERROR] email_verify_check: $e');
      _showError('לא ניתן לבדוק אימות. נסה שוב.');
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  Future<void> _onResendVerification() async {
    setState(() => _verificationBusy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
        _exitEmailVerificationGate();
        return;
      }
      final reloadResult = await _reloadForEmailVerifyDiag();
      final snapshotUser = FirebaseAuth.instance.currentUser ?? user;
      _logEmailVerifyDiagSnapshot(snapshotUser, reloadResult: reloadResult);
      debugPrint('[GENET][EMAIL_VERIFY_DIAG] SEND_ATTEMPT');
      await snapshotUser.sendEmailVerification();
      debugPrint('[GENET][EMAIL_VERIFY_DIAG] SEND_SUCCESS');
      debugPrint('[GENET][EMAIL_VERIFY] resend');
      _showMessage('קישור אימות נשלח שוב');
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[GENET][EMAIL_VERIFY_DIAG] SEND_ERROR code=${e.code} message=${e.message}',
      );
      debugPrint('[GENET][AUTH][ERROR] email_verify_resend: $e');
      _showError('לא ניתן לשלוח קישור אימות. נסה שוב.');
    } catch (e) {
      debugPrint('[GENET][AUTH][ERROR] email_verify_resend: $e');
      _showError('לא ניתן לשלוח קישור אימות. נסה שוב.');
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  String _hebrewPasswordResetError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'כתובת האימייל אינה תקינה.';
      case 'user-not-found':
        return 'לא נמצא חשבון עם אימייל זה.';
      case 'network-request-failed':
        return 'בעיית רשת. בדוק את החיבור לאינטרנט.';
      case 'too-many-requests':
        return 'יותר מדי ניסיונות. נסה שוב מאוחר יותר.';
      default:
        return 'לא ניתן לשלוח קישור לאיפוס סיסמה. נסה שוב.';
    }
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

  Future<void> _completeAuthSuccess({required bool isLoginMode}) async {
    debugPrint(
      '[GENET][ONBOARDING_FLOW] isLoginMode=${isLoginMode ? "loginMode" : "registerMode"}',
    );
    await GenetConfig.commitUserRole(widget.role);
    if (!mounted) return;
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      Navigator.pop(context, true);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
      return;
    }
    if (widget.role == kUserRoleParent) {
      if (isLoginMode) {
        final parentId = await getOrCreateParentId();
        final profile = await getParentProfile(parentId);
        if (!mounted) return;
        final hasCompletedProfile = isParentProfileComplete(profile);
        debugPrint(
          '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasCompletedProfile',
        );
        if (hasCompletedProfile) {
          debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentShell');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const ParentShell()),
          );
          return;
        }
        debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentProfileSetupScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ParentProfileSetupScreen(
              completedBuilder: (_) => const ParentShell(),
            ),
          ),
        );
        return;
      }
      debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=false');
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentShell');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const ParentShell()),
      );
      return;
    }
    if (widget.role == kUserRoleChild) {
      if (isLoginMode) {
        final verified = await hasVerifiedChildCanonicalConnection();
        if (!mounted) return;
        if (verified) {
          debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=true');
          debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildHomeScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const ChildHomeScreen()),
          );
          return;
        }
        final hasProfile = await isChildProfileComplete();
        if (!mounted) return;
        debugPrint(
          '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasProfile',
        );
        if (hasProfile) {
          debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildLinkScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const ChildLinkScreen()),
          );
          return;
        }
        debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildSelfIdentifyScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChildSelfIdentifyScreen()),
        );
        return;
      }
      debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=false');
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildLinkScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChildLinkScreen()),
      );
    }
  }

  void _logRegisterProfile({
    required String role,
    required String authUid,
    required String appUserId,
    required String nextRoute,
  }) {
    debugPrint('[GENET][REGISTER_PROFILE] role=$role');
    debugPrint('[GENET][REGISTER_PROFILE] authUid=$authUid');
    debugPrint('[GENET][REGISTER_PROFILE] appUserId=$appUserId');
    debugPrint('[GENET][REGISTER_PROFILE] profileCompleted=true');
    debugPrint('[GENET][REGISTER_PROFILE] nextRoute=$nextRoute');
  }

  Future<void> _navigateAfterRegister({required String nextRoute}) async {
    if (!mounted) return;
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      Navigator.pop(context, true);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
      return;
    }
    if (nextRoute == 'ParentShell') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const ParentShell()),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const ChildLinkScreen()),
    );
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
      final user = await _reloadCurrentUser();
      if (user == null) {
        _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
        return;
      }
      if (user.emailVerified) {
        await _completeAuthSuccess(isLoginMode: true);
        return;
      }
      _enterEmailVerificationGate(fromLogin: true);
    } on FirebaseAuthException catch (e) {
      debugPrint('[GENET][AUTH][ERROR] sign_in code=${e.code} message=${e.message}');
      _showError('${_hebrewAuthError(e)} (${e.code})');
    } catch (e) {
      debugPrint('[GENET][AUTH][ERROR] unexpected: $e');
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final validationError = _validateRegister();
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final birthDate = _birthDate!;
    final age = _calculatedAge!;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final email = _emailController.text.trim();

    debugPrint('[GENET][AUTH_EMAIL] registerEmail=$email');

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Firebase user missing after registration');
      }
      final authUid = user.uid;

      await GenetConfig.commitUserRole(widget.role);

      if (widget.role == kUserRoleParent) {
        final parentId = await getOrCreateParentId();
        await saveRegistrationParentProfile(
          parentId: parentId,
          authUid: authUid,
          firstName: firstName,
          lastName: lastName,
          birthDate: birthDate,
          age: age,
          phone: phone,
        );
        _logRegisterProfile(
          role: kUserRoleParent,
          authUid: authUid,
          appUserId: parentId,
          nextRoute: 'ParentShell',
        );
        await _sendVerificationEmail();
        _enterEmailVerificationGate(
          fromLogin: false,
          registerNextRoute: 'ParentShell',
        );
      } else {
        final childId = await getLocalChildId();
        if (childId == null || childId.isEmpty) {
          throw StateError('Auth-bound childId missing after registration');
        }
        await saveRegistrationChildProfile(
          childId: childId,
          authUid: authUid,
          firstName: firstName,
          lastName: lastName,
          birthDate: birthDate,
          age: age,
          phone: phone,
        );
        await saveChildSelfProfile(
          firstName: firstName,
          lastName: lastName,
          age: age,
          schoolCode: '',
        );
        _logRegisterProfile(
          role: kUserRoleChild,
          authUid: authUid,
          appUserId: childId,
          nextRoute: 'ChildLinkScreen',
        );
        await _sendVerificationEmail();
        _enterEmailVerificationGate(
          fromLogin: false,
          registerNextRoute: 'ChildLinkScreen',
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[GENET][AUTH][ERROR] register code=${e.code} message=${e.message}');
      _showError('${_hebrewAuthError(e)} (${e.code})');
    } catch (e) {
      debugPrint('[GENET][AUTH][ERROR] unexpected: $e');
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildLoginFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          decoration: _fieldDecoration('אימייל'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: _fieldDecoration('סיסמה'),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onPrimaryAction(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _loading ? null : _onForgotPassword,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('שכחתי סיסמה?'),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _firstNameController,
          decoration: _fieldDecoration('שם פרטי'),
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastNameController,
          decoration: _fieldDecoration('שם משפחה'),
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _loading ? null : _pickBirthDate,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: _fieldDecoration('תאריך לידה').copyWith(
              hintText: null,
            ),
            child: Text(
              _birthDateLabel,
              style: TextStyle(
                color: _birthDate == null
                    ? Colors.grey.shade600
                    : AppTheme.darkBlue,
                fontSize: 16,
              ),
            ),
          ),
        ),
        if (_calculatedAge != null) ...[
          const SizedBox(height: 8),
          Text(
            'גיל: $_calculatedAge',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          decoration: _fieldDecoration('מספר פלאפון'),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          decoration: _fieldDecoration('אימייל'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: _fieldDecoration('סיסמה'),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: _fieldDecoration('אימות סיסמה'),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onPrimaryAction(),
        ),
      ],
    );
  }

  Widget _buildEmailVerificationUi() {
    final email = FirebaseAuth.instance.currentUser?.email?.trim();
    final busy = _loading || _verificationBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 56,
          color: AppTheme.primaryBlue,
        ),
        const SizedBox(height: 24),
        const Text(
          'אימות אימייל',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppTheme.darkBlue,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'שלחנו לך קישור אימות לאימייל',
          style: TextStyle(fontSize: 15, height: 1.45),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'יש לאשר את האימייל כדי להמשיך',
          style: TextStyle(fontSize: 15, height: 1.45),
          textAlign: TextAlign.center,
        ),
        if (email != null && email.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            email,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.darkBlue,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: busy ? null : _onCheckEmailVerified,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('בדקתי, המשך'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : _onResendVerification,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('שלח שוב'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _verificationBusy;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.darkBlue,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: busy
                ? null
                : () {
                    if (_waitingForEmailVerification) {
                      _exitEmailVerificationGate();
                      return;
                    }
                    Navigator.pop(context, false);
                  },
          ),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: busy,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Genet',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkBlue,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (!_waitingForEmailVerification)
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 40),
                  if (_waitingForEmailVerification)
                    _buildEmailVerificationUi()
                  else ...[
                    if (_isLoginMode) _buildLoginFields() else _buildRegisterFields(),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _onPrimaryAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        disabledBackgroundColor:
                            AppTheme.primaryBlue.withValues(alpha: 0.45),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white70,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isLoginMode ? 'התחברות' : 'יצירת חשבון'),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'או',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _loading ? null : _toggleMode,
                      child: Text(
                        _isLoginMode
                            ? 'אין לך חשבון? צור חשבון'
                            : 'כבר יש לך חשבון? התחבר',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _roleHelper,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
