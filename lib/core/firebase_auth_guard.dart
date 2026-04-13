import 'package:firebase_auth/firebase_auth.dart';

/// Ensures a Firebase user exists (anonymous or otherwise) after [initializeAppBootstrap].
User requireFirebaseUser() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Firebase user is null after bootstrap');
  }
  return user;
}
