import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/genet_config.dart';
import '../core/extension_requests.dart';
import '../models/child_entity.dart';
import '../models/parent_message.dart';
import 'children_repository.dart';

// --- Parent ID (parent device) ---
const String _kParentIdKey = 'genet_parent_id';

Future<String> getOrCreateParentId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_kParentIdKey);
  if (id == null || id.isEmpty) {
    id = 'p_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    await prefs.setString(_kParentIdKey, id);
    developer.log('Parent data loaded: parentId created', name: 'Sync');
  } else {
    developer.log('Parent data loaded: parentId=$id', name: 'Sync');
  }
  return id;
}

Future<String?> getParentId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kParentIdKey);
}

// --- Child device: linked parent id ---
const String _kLinkedParentIdKey = 'genet_linked_parent_id';

Future<String?> getLinkedParentId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLinkedParentIdKey);
}

Future<void> setLinkedParentId(String? parentId) async {
  final prefs = await SharedPreferences.getInstance();
  if (parentId == null) {
    await prefs.remove(_kLinkedParentIdKey);
  } else {
    await prefs.setString(_kLinkedParentIdKey, parentId);
  }
}

// --- Firebase paths ---
String _parentChildrenPath(String parentId) => 'genet_parents/$parentId/children';

DocumentReference<Map<String, dynamic>> _childDocRef(String parentId, String childId) {
  return FirebaseFirestore.instance.doc('${_parentChildrenPath(parentId)}/$childId');
}

// --- Field names ---
const String _kProfile = 'profile';
const String _kConnectionStatus = 'connectionStatus';
const String _kBlockedPackages = 'blockedPackages';
const String _kExtensionApproved = 'extensionApproved';
const String _kExtensionRequests = 'extensionRequests';
const String _kUpdatedAt = 'updatedAt';
const String _kVpnEnabled = 'vpnEnabled';
const String _kVpnStatus = 'vpnStatus';
const String _kVpnStatusMessage = 'vpnStatusMessage';
const String _kLinkCode = 'linkCode';
const String _kParentId = 'parentId';
const String _kConnected = 'connected';
const String _kDisconnected = 'disconnected';
const String _kRemoved = 'removed'; // legacy, treat same as disconnected
const String _kConnectedAt = 'connectedAt';
const String _kDisconnectedAt = 'disconnectedAt';

const String _kFirstName = 'firstName';
const String _kLastName = 'lastName';
const String _kName = 'name';
const String _kAge = 'age';
const String _kSchoolCode = 'schoolCode';
const String _kInstalledApps = 'apps';
const String _kInstalledAppsFingerprintPrefix = 'genet_installed_apps_fp_';

DocumentReference<Map<String, dynamic>> _childInstalledAppsDocRef(String childId) {
  return FirebaseFirestore.instance.doc('child_apps/$childId');
}

Future<void> syncInstalledUserAppsOnce(String childId) async {
  if (childId.isEmpty) return;
  final rawApps = await GenetConfig.getInstalledApps();
  final byPackage = <String, Map<String, String>>{};
  for (final app in rawApps) {
    final packageName = (app['package'] as String? ?? '').trim();
    final appName = (app['name'] as String? ?? '').trim();
    if (packageName.isEmpty || appName.isEmpty) continue;
    byPackage[packageName] = {
      'packageName': packageName,
      'appName': appName,
    };
  }
  final cleanApps = byPackage.values.toList()
    ..sort((a, b) {
      final byName = (a['appName'] ?? '').toLowerCase().compareTo((b['appName'] ?? '').toLowerCase());
      if (byName != 0) return byName;
      return (a['packageName'] ?? '').compareTo(b['packageName'] ?? '');
    });
  final fingerprint = cleanApps
      .map((e) => '${e['packageName']}|${e['appName']}')
      .join(',');
  final prefs = await SharedPreferences.getInstance();
  final fingerprintKey = '$_kInstalledAppsFingerprintPrefix$childId';
  final lastFingerprint = prefs.getString(fingerprintKey) ?? '';
  if (fingerprint == lastFingerprint) {
    debugPrint('[GenetApps] duplicate firebase write prevented');
    return;
  }
  debugPrint('[GenetApps] number of apps found: ${cleanApps.length}');
  debugPrint('[GenetApps] app names: ${cleanApps.map((e) => e['appName']).join(', ')}');
  await _childInstalledAppsDocRef(childId).set({
    _kInstalledApps: cleanApps,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
  await prefs.setString(fingerprintKey, fingerprint);
  debugPrint('[GenetApps] upload success');
}

Future<List<Map<String, dynamic>>> getChildInstalledAppsFromFirebase(String childId) async {
  if (childId.isEmpty) return [];
  final snap = await _childInstalledAppsDocRef(childId).get();
  final data = snap.data();
  final raw = data?[_kInstalledApps];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e).cast<String, dynamic>())
      .toList();
}

/// Parent: create/update child doc in Firebase when child connects. Also write to local and child_link_status.
Future<void> upsertParentChildDoc({
  required String parentId,
  required String childId,
  required String firstName,
  required String lastName,
  required String name,
  required int age,
  required String schoolCode,
  required String linkCode,
}) async {
  print('PARENT ACTION');
  print('PARENT ID: $parentId');
  print('SELECTED CHILD ID: $childId');
  print('Writing settings to: genet_parents/$parentId/children/$childId');
  final ref = _childDocRef(parentId, childId);
  const connectWriteFields = [_kProfile, _kParentId, _kConnectionStatus, _kLinkCode, _kConnectedAt, _kBlockedPackages, _kExtensionApproved, _kExtensionRequests, _kUpdatedAt];
  developer.log('CONNECT_WRITE_PATH = ${ref.path}', name: 'Sync');
  developer.log('CONNECT_WRITE_CHILD_ID = $childId', name: 'Sync');
  developer.log('CONNECT_WRITE_PARENT_ID = $parentId', name: 'Sync');
  developer.log('CONNECT_WRITE_FIELDS = $connectWriteFields', name: 'Sync');
  final profile = {
    _kFirstName: firstName,
    _kLastName: lastName,
    _kName: name,
    _kAge: age,
    _kSchoolCode: schoolCode,
  };
  await ref.set({
    _kProfile: profile,
    _kParentId: parentId,
    _kConnectionStatus: _kConnected,
    _kLinkCode: linkCode,
    _kConnectedAt: FieldValue.serverTimestamp(),
    _kBlockedPackages: FieldValue.arrayUnion([]),
    _kExtensionApproved: <String, int>{},
    _kExtensionRequests: FieldValue.arrayUnion([]),
    _kUpdatedAt: FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Returns true if status means "connected" for UI.
bool isConnectionStatusConnected(String? status) {
  return status == _kConnected;
}

/// Parent: set child connection status to disconnected (when parent removes child).
Future<void> setChildConnectionStatusFirebase(String parentId, String childId, String status) async {
  final ref = _childDocRef(parentId, childId);
  final updates = <String, dynamic>{
    _kConnectionStatus: status,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (status == _kDisconnected || status == _kRemoved) {
    updates[_kDisconnectedAt] = FieldValue.serverTimestamp();
    updates[_kParentId] = null;
  }
  developer.log('DISCONNECT_WRITE_PATH = ${ref.path}', name: 'Sync');
  developer.log('DISCONNECT_WRITE_CHILD_ID = $childId', name: 'Sync');
  developer.log('DISCONNECT_WRITE_FIELDS = ${updates.keys.toList()}', name: 'Sync');
  await ref.update(updates);
}

/// Parent: update blocked packages for a child in Firebase and local.
Future<void> syncBlockedPackagesToFirebase(String parentId, String childId, List<String> packages) async {
  print('PARENT ACTION');
  print('PARENT ID: $parentId');
  print('SELECTED CHILD ID: $childId');
  print('Writing settings to: genet_parents/$parentId/children/$childId');
  developer.log('Blocked apps synced: childId=$childId count=${packages.length}', name: 'Sync');
  await setBlockedPackagesForChild(childId, packages);
  final ref = _childDocRef(parentId, childId);
  final snap = await ref.get();
  if (snap.exists) {
    final cur = (snap.data()![_kBlockedPackages] as List?)?.cast<String>() ?? [];
    final a = List<String>.from(cur)..sort();
    final b = List<String>.from(packages)..sort();
    if (listEquals(a, b)) {
      debugPrint('[GenetVpn] skipped duplicate update (blockedPackages unchanged in Firestore)');
      debugPrint('[GenetBlocked] duplicate firebase write prevented');
      return;
    }
  }
  await ref.update({
    _kBlockedPackages: packages,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Parent: remote VPN policy for the child device (actual VPN runs on child only).
/// Uses [set] with merge so writes succeed even if the doc was missing (unlike [update]).
Future<void> syncVpnPolicyToFirebase(String parentId, String childId, {required bool vpnEnabled}) async {
  final path = _childDocRef(parentId, childId).path;
  try {
    if (vpnEnabled) {
      final pkgs = await getBlockedPackagesForChild(childId);
      await setBlockedPackagesForChild(childId, pkgs);
      developer.log(
        'parent wrote vpnEnabled=true for childId=$childId blocked=${pkgs.length}',
        name: 'GenetVpn',
      );
      debugPrint('[GenetVpn] parent wrote vpnEnabled=true');
      debugPrint('[GenetVpn] writing blockedApps=$pkgs');
      await _childDocRef(parentId, childId).set({
        _kBlockedPackages: pkgs,
        _kVpnEnabled: true,
        _kUpdatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      developer.log('parent wrote vpnEnabled=false for childId=$childId', name: 'GenetVpn');
      debugPrint('[GenetVpn] parent wrote vpnEnabled=false');
      await _childDocRef(parentId, childId).set({
        _kVpnEnabled: false,
        _kUpdatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  } catch (e, st) {
    debugPrint('[GenetVpn] syncVpnPolicyToFirebase FAILED path=$path error=$e $st');
    rethrow;
  }
}

List<ParentMessage> parentMessageHistoryFromChildSettings(
  Map<String, dynamic>? data,
) {
  if (data == null) return const <ParentMessage>[];
  final messages = <ParentMessage>[];
  final rawHistory = data[_kParentMessages];
  if (rawHistory is List) {
    for (final entry in rawHistory) {
      if (entry is Map) {
        final parsed = ParentMessage.fromMap(Map<String, dynamic>.from(entry));
        if (parsed.hasContent) {
          messages.add(parsed);
        }
      }
    }
  }
  final legacySingle = data['parentMessage'];
  if (messages.isEmpty && legacySingle is Map) {
    final parsed = ParentMessage.fromMap(Map<String, dynamic>.from(legacySingle));
    if (parsed.hasContent) {
      messages.add(parsed);
    }
  }
  messages.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return messages;
}

ParentMessage? latestParentMessageFromChildSettings(Map<String, dynamic>? data) {
  final history = parentMessageHistoryFromChildSettings(data);
  if (history.isEmpty) return null;
  return history.last;
}

Future<ParentMessage> addParentMessageToFirebase(
  String childId, {
  required String text,
}) async {
  final message = ParentMessage.create(text);
  if (childId.isEmpty || !message.hasContent) return message;
  final ref = _childSettingsDocRef(childId);
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final snap = await transaction.get(ref);
    final current = parentMessageHistoryFromChildSettings(snap.data());
    final updated = [...current, message];
    final trimmed =
        updated.length > 40 ? updated.sublist(updated.length - 40) : updated;
    transaction.set(
      ref,
      {
        _kParentMessages: trimmed.map((entry) => entry.toMap()).toList(),
        'parentMessage': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  });
  return message;
}

/// Child device: report VPN outcome to the same child doc (parent reads [vpnStatus]).
Future<void> syncChildVpnStatusToFirebase(
  String parentId,
  String childId,
  String vpnStatus, {
  String? vpnStatusMessage,
}) async {
  final path = _childDocRef(parentId, childId).path;
  final m = <String, dynamic>{
    _kVpnStatus: vpnStatus,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (vpnStatusMessage != null) {
    m[_kVpnStatusMessage] = vpnStatusMessage;
  } else {
    m[_kVpnStatusMessage] = FieldValue.delete();
  }
  try {
    debugPrint('[GenetVpn] child writing path=$path vpnStatus=$vpnStatus msg=$vpnStatusMessage');
    await _childDocRef(parentId, childId).set(m, SetOptions(merge: true));
  } catch (e, st) {
    debugPrint('[GenetVpn] syncChildVpnStatusToFirebase FAILED path=$path error=$e $st');
  }
}

/// Parent: update extension approved map in Firebase and local.
Future<void> syncExtensionApprovedToFirebase(String parentId, String childId, Map<String, int> map) async {
  print('PARENT ACTION');
  print('PARENT ID: $parentId');
  print('SELECTED CHILD ID: $childId');
  print('Writing settings to: genet_parents/$parentId/children/$childId');
  developer.log('Extension approved synced: childId=$childId', name: 'Sync');
  await setExtensionApprovedForChild(childId, map);
  final data = map.map((k, v) => MapEntry(k, v));
  await _childDocRef(parentId, childId).update({
    _kExtensionApproved: data,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Child doc snapshot to local state (await prefs so merge finishes before next snapshot consumer).
Future<void> _applyChildDocToLocalAsync(
  String childId,
  Map<String, dynamic>? data,
) async {
  if (data == null) return;
  final blocked = (data[_kBlockedPackages] as List?)?.cast<String>() ?? [];
  final approvedRaw = data[_kExtensionApproved] as Map<String, dynamic>?;
  final approved = <String, int>{};
  if (approvedRaw != null) {
    for (final e in approvedRaw.entries) {
      final v = e.value;
      if (v is int) {
        approved[e.key] = v;
      } else if (v is num) {
        approved[e.key] = v.toInt();
      }
    }
  }
  await setBlockedPackagesForChild(childId, blocked);
  await setExtensionApprovedForChild(childId, approved);
  final requestsList = data[_kExtensionRequests] as List?;
  if (requestsList != null) {
    final requests = requestsList
        .map((e) => ExtensionRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final current = await getExtensionRequests();
    final byOther = current.where((r) => r.childId != childId).toList();
    await saveExtensionRequests([...byOther, ...requests]);
  }
}

/// Parsed child doc for UI (child device).
class SyncedChildData {
  const SyncedChildData({
    this.blockedPackages = const [],
    this.extensionApproved = const {},
    this.extensionRequests = const [],
    this.connectionStatus = 'connected',
    this.parentId,
    this.vpnEnabled = false,
    this.vpnStatus,
  });
  final List<String> blockedPackages;
  final Map<String, int> extensionApproved;
  final List<ExtensionRequest> extensionRequests;
  final String connectionStatus;
  final String? parentId;
  final bool vpnEnabled;
  /// Last status written by child device: on | off | error
  final String? vpnStatus;
}

/// Stream child doc from Firebase (for child device). Updates local when data arrives.
Stream<Map<String, dynamic>?> watchChildDocStream(String parentId, String childId) {
  if (parentId.isEmpty || childId.isEmpty) return Stream.value(null);
  final ref = _childDocRef(parentId, childId);
  developer.log('CHILD_READ_PATH = ${ref.path}', name: 'Sync');
  developer.log('CHILD_READ_CHILD_ID = $childId', name: 'Sync');
  return ref.snapshots().asyncMap((snap) async {
    if (!snap.exists) {
      print('CHILD LISTENER');
      print('CHILD ID: $childId');
      print('Listening to: genet_parents/$parentId/children/$childId');
      print('DATA RECEIVED: (no document / snap.exists=false)');
      return null;
    }
    final data = snap.data();
    print('CHILD LISTENER');
    print('CHILD ID: $childId');
    print('Listening to: genet_parents/$parentId/children/$childId');
    print(
      'DATA RECEIVED: parentId=${data?[_kParentId]} connectionStatus=${data?[_kConnectionStatus]} blocked=${(data?[_kBlockedPackages] as List?)?.length ?? 0}',
    );
    developer.log('CHILD_READ_DOC_DATA = parentId=${data?[_kParentId]} connectionStatus=${data?[_kConnectionStatus]}', name: 'Sync');
    await _applyChildDocToLocalAsync(childId, data);
    // Remote parent (other device) updated Firestore — push policy to Android enforcement on child device only.
    scheduleMicrotask(() => GenetConfig.syncToNativeAfterRemoteChildDoc());
    return data;
  });
}

/// Stream parsed child data for child device UI (blocked, approved, requests).
Stream<SyncedChildData?> watchSyncedChildDataStream(String parentId, String childId) {
  return watchChildDocStream(parentId, childId).map((data) {
    if (data == null) return null;
    final blocked = (data[_kBlockedPackages] as List?)?.cast<String>() ?? [];
    final approvedRaw = data[_kExtensionApproved] as Map<String, dynamic>?;
    final approved = <String, int>{};
    if (approvedRaw != null) {
      for (final e in approvedRaw.entries) {
        final v = e.value;
        if (v is int) {
          approved[e.key] = v;
        } else if (v is num) approved[e.key] = v.toInt();
      }
    }
    final reqList = (data[_kExtensionRequests] as List?) ?? [];
    final requests = reqList
        .map((e) => ExtensionRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final status = data[_kConnectionStatus] as String? ?? _kConnected;
    final parentId = data[_kParentId] as String?;
    final vpnEnabled = data[_kVpnEnabled] == true;
    final vpnStatus = data[_kVpnStatus] as String?;
    developer.log('Child data loaded: blocked=${blocked.length} approved=${approved.length} requests=${requests.length} vpnEnabled=$vpnEnabled vpnStatus=$vpnStatus', name: 'Sync');
    return SyncedChildData(
      blockedPackages: blocked,
      extensionApproved: approved,
      extensionRequests: requests,
      connectionStatus: status,
      parentId: parentId,
      vpnEnabled: vpnEnabled,
      vpnStatus: vpnStatus,
    );
  });
}

/// Parent: stream single child doc (for selected child).
Stream<Map<String, dynamic>?> watchParentChildDocStream(String parentId, String childId) {
  if (parentId.isEmpty || childId.isEmpty) return Stream.value(null);
  return _childDocRef(parentId, childId).snapshots().asyncMap((snap) async {
    if (!snap.exists) return null;
    final data = snap.data();
    await _applyChildDocToLocalAsync(childId, data);
    return data;
  });
}

/// Parent: stream all children for this parent from Firebase.
Stream<List<ChildEntity>> watchParentChildrenStream(String parentId) async* {
  if (parentId.isEmpty) {
    yield [];
    return;
  }
  final collectionPath = _parentChildrenPath(parentId);
  developer.log('PARENT_READ_PATH = $collectionPath', name: 'Sync');
  developer.log('PARENT_READ_PARENT_ID = $parentId', name: 'Sync');
  await for (final snap in FirebaseFirestore.instance
      .collection(collectionPath)
      .snapshots()) {
    final list = <ChildEntity>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final childId = doc.id;
      final docParentId = data[_kParentId] as String?;
      final status = data[_kConnectionStatus] as String? ?? _kConnected;
      if (docParentId != parentId || !isConnectionStatusConnected(status)) {
        continue;
      }
      final profile = data[_kProfile] as Map<String, dynamic>? ?? {};
      final name = profile[_kName] as String? ?? '';
      final firstName = profile[_kFirstName] as String? ?? '';
      final lastName = profile[_kLastName] as String? ?? '';
      final linkCode = data[_kLinkCode] as String? ?? '';
      list.add(ChildEntity(
        childId: childId,
        name: name.isEmpty ? [firstName, lastName].join(' ').trim() : name,
        firstName: firstName,
        lastName: lastName,
        age: (profile[_kAge] as num?)?.toInt() ?? 0,
        schoolCode: profile[_kSchoolCode] as String? ?? '',
        linkCode: linkCode,
        isConnected: status == _kConnected,
        connectionStatus: status == _kConnected ? ChildConnectionStatus.connected : ChildConnectionStatus.disconnected,
      ));
    }
    developer.log('PARENT_READ_QUERY_RESULT_COUNT = ${list.length}', name: 'Sync');
    developer.log('PARENT_READ_DOCS = ${list.map((e) => e.childId).toList()}', name: 'Sync');
    yield list;
  }
}

/// Child: add extension request to Firebase (and local).
Future<void> addExtensionRequestToFirebase(
  String parentId,
  String childId,
  ExtensionRequest request,
) async {
  print('CHILD ACTION (extension request write)');
  print('PARENT ID: $parentId');
  print('CHILD ID: $childId');
  print('Writing to: genet_parents/$parentId/children/$childId');
  developer.log('Extension request created: package=${request.packageName}', name: 'Sync');
  final ref = _childDocRef(parentId, childId);
  debugPrint(
    '[GenetExtReq] extension request write started path=${ref.path} childId used=$childId requestId=${request.id}',
  );
  try {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) {
        debugPrint('[GenetExtReq] wrong path / missing document path=${ref.path}');
        return;
      }
      final list = List<Map<String, dynamic>>.from(
        (snap.data()![_kExtensionRequests] as List?) ?? [],
      );
      if (list.any((e) => (e['id'] as String?) == request.id)) {
        debugPrint('[GenetExtReq] duplicate request skipped requestId=${request.id} path=${ref.path}');
        return;
      }
      list.add(request.toJson());
      transaction.update(ref, {
        _kExtensionRequests: list,
        _kUpdatedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (e, st) {
    debugPrint('[GenetExtReq] extension request write failed path=${ref.path} error=$e $st');
    rethrow;
  }
  debugPrint('[GenetExtReq] extension request write success path=${ref.path} requestId=${request.id}');
  final all = await getExtensionRequests();
  all.add(request);
  await saveExtensionRequests(all);
}

/// Parent: update extension request status in Firebase and update extension approved if approved.
Future<void> updateExtensionRequestInFirebase(
  String parentId,
  String childId,
  String requestId,
  String status, {
  int? approvedUntilMs,
  String? packageName,
}) async {
  if (status == ExtensionRequestStatus.approved) {
    developer.log('Extension approved: requestId=$requestId', name: 'Sync');
  } else if (status == ExtensionRequestStatus.rejected) {
    developer.log('Extension rejected: requestId=$requestId', name: 'Sync');
  }
  print('PARENT ACTION');
  print('PARENT ID: $parentId');
  print('SELECTED CHILD ID: $childId');
  print('Writing settings to: genet_parents/$parentId/children/$childId');
  final ref = _childDocRef(parentId, childId);
  final snap = await ref.get();
  final data = snap.data();
  if (data == null) return;
  final list = List<Map<String, dynamic>>.from(
    (data[_kExtensionRequests] as List?) ?? [],
  );
  var idx = list.indexWhere((e) => (e['id'] as String?) == requestId);
  if (idx >= 0) list[idx] = {...list[idx], 'status': status};

  final approved = Map<String, int>.from(
    (data[_kExtensionApproved] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v is int ? v : (v as num).toInt())) ?? {},
  );
  if (status == ExtensionRequestStatus.approved && approvedUntilMs != null && packageName != null) {
    approved[packageName] = approvedUntilMs;
  }
  if (status == ExtensionRequestStatus.rejected || status == ExtensionRequestStatus.approved) {
    // no change to approved map for reject; for approve we set above
  }

  await ref.update({
    _kExtensionRequests: list,
    _kExtensionApproved: approved,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
  await setExtensionApprovedForChild(childId, approved);
  final currentRequests = await getExtensionRequests();
  final ri = currentRequests.indexWhere((e) => e.id == requestId);
  if (ri >= 0) {
    currentRequests[ri] = currentRequests[ri].copyWith(status: status);
    await saveExtensionRequests(currentRequests);
  }
}

/// Parent: cancel extension (remove from approved map) in Firebase.
Future<void> cancelExtensionInFirebase(String parentId, String childId, String packageName) async {
  print('PARENT ACTION');
  print('PARENT ID: $parentId');
  print('SELECTED CHILD ID: $childId');
  print('Writing settings to: genet_parents/$parentId/children/$childId');
  developer.log('Extension cancelled: package=$packageName', name: 'Sync');
  final ref = _childDocRef(parentId, childId);
  final snap = await ref.get();
  final data = snap.data();
  if (data == null) return;
  final approved = Map<String, int>.from(
    (data[_kExtensionApproved] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v is int ? v : (v as num).toInt())) ?? {},
  );
  approved.remove(packageName);
  await ref.update({
    _kExtensionApproved: approved,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
  await setExtensionApprovedForChild(childId, approved);
}

// --- Remote Sleep Lock (cross-device): child_settings/{childId}/sleep_lock/settings ---

const String _kChildSettingsCollection = 'child_settings';
const String _kSleepLockSubcollection = 'sleep_lock';
const String _kSleepLockSettingsDoc = 'settings';
const String _kRequireVpn = 'requireVpn';
const String _kParentMessages = 'parentMessages';

DocumentReference<Map<String, dynamic>> _childSettingsDocRef(String childId) {
  return FirebaseFirestore.instance
      .collection(_kChildSettingsCollection)
      .doc(childId);
}

DocumentReference<Map<String, dynamic>> _sleepLockDocRef(String childId) {
  return FirebaseFirestore.instance
      .collection(_kChildSettingsCollection)
      .doc(childId)
      .collection(_kSleepLockSubcollection)
      .doc(_kSleepLockSettingsDoc);
}

/// Parent device: write sleep lock for the selected child only (remote sync).
Future<void> writeSleepLockToFirebase(
  String childId, {
  required bool isActive,
  required String startTime,
  required String endTime,
}) async {
  if (childId.isEmpty) return;
  final path = '$_kChildSettingsCollection/$childId/$_kSleepLockSubcollection/$_kSleepLockSettingsDoc';
  developer.log('SLEEP_LOCK parent write selectedChildId=$childId path=$path isActive=$isActive start=$startTime end=$endTime', name: 'Sync');
  await _sleepLockDocRef(childId).set(
    {
      'isActive': isActive,
      'startTime': startTime,
      'endTime': endTime,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
  await _childSettingsDocRef(childId).set(
    {
      'sleepLock': {
        'isActive': isActive,
        'startTime': startTime,
        'endTime': endTime,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

/// One-shot read (e.g. parent Sleep Lock screen open).
Future<Map<String, dynamic>?> getSleepLockFromFirebase(String childId) async {
  if (childId.isEmpty) return null;
  final snap = await _sleepLockDocRef(childId).get();
  if (!snap.exists) return null;
  return snap.data();
}

/// Child device: real-time sleep lock from Firebase (same [childId] as [getLinkedChildId]).
Stream<Map<String, dynamic>?> watchChildSleepLockStream(String childId) {
  if (childId.isEmpty) return Stream.value(null);
  final path = '$_kChildSettingsCollection/$childId/$_kSleepLockSubcollection/$_kSleepLockSettingsDoc';
  developer.log('SLEEP_LOCK child listen childId=$childId path=$path', name: 'Sync');
  return _sleepLockDocRef(childId).snapshots().map((snap) {
    if (!snap.exists) {
      developer.log('SLEEP_LOCK child snapshot: no doc', name: 'Sync');
      return null;
    }
    final d = snap.data();
    developer.log(
      'SLEEP_LOCK child snapshot received isActive=${d?['isActive']} start=${d?['startTime']} end=${d?['endTime']}',
      name: 'Sync',
    );
    return d;
  });
}

Future<void> writeRequireVpnToFirebase(String childId, {required bool requireVpn}) async {
  if (childId.isEmpty) return;
  final path = '$_kChildSettingsCollection/$childId';
  developer.log(
    'REQUIRE_VPN parent write childId=$childId path=$path requireVpn=$requireVpn',
    name: 'Sync',
  );
  await _childSettingsDocRef(childId).set(
    {
      _kRequireVpn: requireVpn,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

Future<bool> getRequireVpnFromFirebase(String childId) async {
  if (childId.isEmpty) return false;
  final snap = await _childSettingsDocRef(childId).get();
  return snap.data()?[_kRequireVpn] == true;
}

Future<List<ParentMessage>> getParentMessageHistoryFromFirebase(
  String childId,
) async {
  if (childId.isEmpty) return const <ParentMessage>[];
  final snap = await _childSettingsDocRef(childId).get();
  return parentMessageHistoryFromChildSettings(snap.data());
}

DocumentReference<Map<String, dynamic>> _trustedTimeDocRef(String childId) {
  return _childSettingsDocRef(childId).collection('trusted_time').doc('reference');
}

Future<DateTime?> fetchTrustedTimeFromFirebase(String childId) async {
  if (childId.isEmpty) return null;
  final ref = _trustedTimeDocRef(childId);
  try {
    await ref.set({
      'serverNow': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final snap = await ref.get(const GetOptions(source: Source.server));
    final raw = snap.data()?['serverNow'];
    if (raw is Timestamp) {
      return raw.toDate();
    }
  } catch (_) {
    return null;
  }
  return null;
}

Stream<Map<String, dynamic>?> watchChildSettingsStream(String childId) {
  if (childId.isEmpty) return Stream.value(null);
  final path = '$_kChildSettingsCollection/$childId';
  developer.log('CHILD_SETTINGS child listen childId=$childId path=$path', name: 'Sync');
  return _childSettingsDocRef(childId).snapshots().map((snap) {
    final d = snap.data();
    developer.log(
      'CHILD_SETTINGS source=Firebase childId=$childId requireVpn=${d?[_kRequireVpn] == true} sleepLockActive=${(d?['sleepLock'] as Map?)?['isActive']}',
      name: 'Sync',
    );
    return d;
  });
}
