import 'package:firebase_auth/firebase_auth.dart';

/// Ensures a Firebase user exists (anonymous or otherwise) after [initializeAppBootstrap].
User requireFirebaseUser() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Firebase user is null after bootstrap');
  }
  return user;
}

/// True when a non-anonymous Firebase user is signed in.
bool firebaseUserIsAuthenticated() {
  final user = FirebaseAuth.instance.currentUser;
  return user != null && !user.isAnonymous;
}

/// True when any Firebase user is signed in (anonymous or authenticated).
bool firebaseUserExists() {
  return FirebaseAuth.instance.currentUser != null;
}
