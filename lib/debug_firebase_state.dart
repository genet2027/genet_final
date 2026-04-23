// ignore_for_file: avoid_print — intentional temporary diagnostics (see TASK).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Temporary: verify Firebase project + auth (Firestore rules). Remove when done.
void debugFirebaseState() {
  final app = Firebase.app();
  final user = FirebaseAuth.instance.currentUser;

  print('[GENET][FIREBASE] projectId=${app.options.projectId}');
  print('[GENET][AUTH] uid=${user?.uid} isSignedIn=${user != null}');
}
