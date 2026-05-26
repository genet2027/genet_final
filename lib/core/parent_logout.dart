import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/genet_config.dart';
import 'user_role.dart';
import '../repositories/parent_child_sync_repository.dart';

/// Signs out Firebase and clears local parent auth/session routing prefs only.
Future<void> performParentLogout() async {
  await FirebaseAuth.instance.signOut();
  debugPrint('[GENET][PARENT_LOGOUT] firebase_signout_success');

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kUserRoleKey);
  await clearParentAuthSessionPrefs();

  await GenetConfig.applyNativeChildModeFromSavedRole();
  debugPrint('[GENET][PARENT_LOGOUT] local_session_cleared');
}
