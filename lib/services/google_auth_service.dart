import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/auth_flow_helpers.dart';

/// User closed the Google account picker without signing in.
class GoogleSignInCanceledException implements Exception {}

/// Firebase Console / google-services.json is not configured for Google Sign-In.
class GoogleSignInSetupException implements Exception {
  GoogleSignInSetupException(this.message);
  final String message;
}

bool _googleSignInInitialized = false;

const _kGoogleSetupLog =
    '[GENET][LOGIN_UI] google setup hint: android/app/google-services.json has '
    'empty oauth_client — add debug/release SHA-1 and SHA-256 in Firebase Console '
    '(Project Settings → Your apps → Android → Add fingerprint), enable Google '
    'sign-in provider (Authentication → Sign-in method), then re-download '
    'google-services.json and rebuild.';

Future<void> _ensureGoogleSignInInitialized() async {
  if (_googleSignInInitialized) return;
  await GoogleSignIn.instance.initialize();
  _googleSignInInitialized = true;
}

String authFlowHebrewGoogleSignInError(Object error) {
  if (error is GoogleSignInCanceledException) {
    return '';
  }
  if (error is GoogleSignInSetupException) {
    return error.message;
  }
  if (error is GoogleSignInException) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return '';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'התחברות Google לא מוגדרת באפליקציה. יש להוסיף SHA-1/SHA-256 ב-Firebase Console, להפעיל Google Sign-In, ולהוריד google-services.json מעודכן.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'לא ניתן להציג את מסך Google. נסה שוב.';
      case GoogleSignInExceptionCode.interrupted:
        return 'ההתחברות עם Google נקטעה. נסה שוב.';
      case GoogleSignInExceptionCode.userMismatch:
      case GoogleSignInExceptionCode.unknownError:
        return 'שגיאה בהתחברות עם Google. נסה שוב.';
    }
  }
  if (error is FirebaseAuthException) {
    if (error.code == 'invalid-credential' ||
        error.code == 'operation-not-allowed') {
      return 'התחברות Google לא מוגדרת ב-Firebase. ודא שהפעלת Google Sign-In ב-Firebase Console.';
    }
    return authFlowHebrewAuthError(error);
  }
  return 'שגיאה בהתחברות עם Google. נסה שוב.';
}

void logGoogleSignInFailure(Object error) {
  debugPrint('[GENET][LOGIN_UI] google login failed: $error');
  if (error is GoogleSignInSetupException ||
      (error is GoogleSignInException &&
          (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
              error.code ==
                  GoogleSignInExceptionCode.providerConfigurationError)) ||
      (error is FirebaseAuthException &&
          (error.code == 'invalid-credential' ||
              error.code == 'operation-not-allowed'))) {
    debugPrint(_kGoogleSetupLog);
  }
}

Future<UserCredential> signInWithGoogle() async {
  await _ensureGoogleSignInInitialized();

  final hadAnonymous = FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
  if (hadAnonymous) {
    await FirebaseAuth.instance.signOut();
  }

  try {
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw GoogleSignInSetupException(
        'התחברות Google לא מוגדרת באפליקציה. יש להוסיף SHA-1/SHA-256 ב-Firebase Console, להפעיל Google Sign-In, ולהוריד google-services.json מעודכן.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      throw GoogleSignInCanceledException();
    }
    if (hadAnonymous && FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    rethrow;
  } catch (e) {
    if (hadAnonymous && FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    rethrow;
  }
}
