import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Initializes Firebase once and ensures a signed-in user (anonymous if needed).
/// Call from [main] after [WidgetsFlutterBinding.ensureInitialized], before [runApp].
Future<void> initializeAppBootstrap() async {
  debugPrint('[GENET][BOOTSTRAP] start');
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    debugPrint('[GENET][BOOTSTRAP] firebase_initialized');

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[GENET][BOOTSTRAP] signing_in_anonymously');
      final credential = await FirebaseAuth.instance.signInAnonymously();
      user = credential.user;
    }

    if (user == null) {
      debugPrint('[GENET][BOOTSTRAP][ERROR] sign_in_returned_null_user');
      throw StateError('Firebase user is null after bootstrap');
    }

    debugPrint('[GENET][BOOTSTRAP] firebase_ready=true');
    debugPrint('[GENET][BOOTSTRAP] auth_uid=${user.uid}');
    debugPrint('[GENET][BOOTSTRAP] is_anonymous=${user.isAnonymous}');
  } catch (e, st) {
    debugPrint('[GENET][BOOTSTRAP][ERROR] $e');
    debugPrint('[GENET][BOOTSTRAP][ERROR] $st');
    rethrow;
  }
}
