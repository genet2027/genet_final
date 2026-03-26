import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../models/child_entity.dart';
import '../repositories/child_link_status_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/natural_text_field.dart';
import 'add_child_by_link_screen.dart';

/// Parent: list children, select active, add child, edit child, show QR + manual code for linking.
class ChildrenManagementScreen extends StatefulWidget {
  const ChildrenManagementScreen({super.key});

  @override
  State<ChildrenManagementScreen> createState() => _ChildrenManagementScreenState();
}

class _ChildrenManagementScreenState extends State<ChildrenManagementScreen> {
  List<ChildEntity> _children = [];
  String? _selectedChildId;
  bool _loading = true;
  StreamSubscription<List<ChildEntity>>? _childrenStreamSub;

  Future<void> _load() async {
    final list = await getChildren();
    final selected = await getSelectedChildId();
    if (mounted) {
      setState(() {
        _children = list;
        _selectedChildId = selected;
        _loading = false;
      });
    }
  }

  void _mergeAndSetChildren(List<ChildEntity> fromFirebase) {
    developer.log('Parent linked children updated: count=${fromFirebase.length}', name: 'Sync');
    getChildren().then((local) {
      final byId = {for (final c in fromFirebase) c.childId: c};
      for (final c in local) {
        // Keep only local non-connected/pending entries; connected entries come from Firebase only.
        if (!byId.containsKey(c.childId) && !c.isConnected) {
          byId[c.childId] = c;
        }
      }
      final merged = byId.values.toList();
      saveChildren(merged);
      if (mounted) setState(() => _children = merged);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
    getOrCreateParentId().then((parentId) {
      if (!mounted) return;
      developer.log('PARENT_READ_PATH = genet_parents/$parentId/children', name: 'Sync');
      developer.log('PARENT_READ_PARENT_ID = $parentId', name: 'Sync');
      _childrenStreamSub = watchParentChildrenStream(parentId).listen((list) {
        developer.log('PARENT_QUERY_PARENT_ID = $parentId', name: 'Sync');
        developer.log('PARENT_QUERY_RESULT_COUNT = ${list.length}', name: 'Sync');
        developer.log('PARENT_LISTENER: children updated', name: 'Sync');
        developer.log('PARENT_LISTENER: connected children count = ${list.length}', name: 'Sync');
        developer.log('PARENT_READ_QUERY_RESULT_COUNT = ${list.length}', name: 'Sync');
        developer.log('PARENT_READ_DOCS = ${list.map((e) => e.childId).toList()}', name: 'Sync');
        if (mounted) _mergeAndSetChildren(list);
      });
    });
  }

  @override
  void dispose() {
    _childrenStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _selectChild(String childId) async {
    await setSelectedChildId(childId);
    if (mounted) setState(() => _selectedChildId = childId);
  }

  Future<void> _addChild() async {
    final child = ChildEntity(
      childId: generateChildId(),
      name: 'ילד חדש',
      linkCode: generateLinkCode(),
      isConnected: false,
      connectionStatus: ChildConnectionStatus.pending,
    );
    final list = [..._children, child];
    await saveChildren(list);
    if (_children.isEmpty) await setSelectedChildId(child.childId);
    if (mounted) {
      setState(() {
        _children = list;
        if (_children.length == 1) _selectedChildId = child.childId;
      });
    }
  }

  Future<void> _updateChild(ChildEntity updated) async {
    final list = _children.map((c) => c.childId == updated.childId ? updated : c).toList();
    await saveChildren(list);
    if (mounted) setState(() => _children = list);
  }

  Future<void> _removeChild(ChildEntity child) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הסרת ילד'),
        content: Text('האם להסיר את ${child.name} מרשימת הילדים? הקישור להורה יבוטל.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('הסר'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await removeChild(child.childId);
      final parentId = await getOrCreateParentId();
      await setChildConnectionStatusFirebase(parentId, child.childId, 'disconnected');
      await setChildLinkStatusRemoved(child.childId);
      developer.log('Parent removed child: childId=${child.childId}', name: 'Sync');
    } catch (e) {
      developer.log('Parent remove child error: $e', name: 'Sync');
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ילדים'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'בחר ילד פעיל – ההגדרות והבקשות יחולו רק עליו',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._children.map((child) => _ChildTile(
                        child: child,
                        isActive: _selectedChildId == child.childId,
                        onTap: () => _selectChild(child.childId),
                        onEdit: () => _openEditChild(context, child),
                        onRemove: () => _removeChild(child),
                      )),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddChildByLinkScreen(),
                        ),
                      ).then((_) => _load());
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('חבר ילד'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addChild,
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף ילד (ידני)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                    ),
                  ),
                  if (_selectedChildId != null) ...[
                    const SizedBox(height: 24),
                    Builder(
                      builder: (context) {
                        ChildEntity? selectedChild;
                        for (final c in _children) {
                          if (c.childId == _selectedChildId) {
                            selectedChild = c;
                            break;
                          }
                        }
                        if (selectedChild == null) return const SizedBox.shrink();
                        return _LinkSection(child: selectedChild);
                      },
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  void _openEditChild(BuildContext context, ChildEntity child) {
    final firstNameController = TextEditingController(text: child.firstName.isNotEmpty ? child.firstName : child.name);
    final lastNameController = TextEditingController(text: child.lastName);
    final ageController = TextEditingController(text: child.age > 0 ? child.age.toString() : '');
    final gradeController = TextEditingController(text: child.grade);
    final schoolCodeController = TextEditingController(text: child.schoolCode);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'עריכת ${child.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  NaturalTextField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'שם פרטי',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  NaturalTextField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'שם משפחה',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  NaturalTextField(
                    controller: ageController,
                    decoration: const InputDecoration(
                      labelText: 'גיל',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  NaturalTextField(
                    controller: gradeController,
                    decoration: const InputDecoration(
                      labelText: 'כיתה',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  NaturalTextField(
                    controller: schoolCodeController,
                    decoration: const InputDecoration(
                      labelText: 'קוד בית ספר',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      final first = firstNameController.text.trim();
                      final last = lastNameController.text.trim();
                      final name = [first, last].join(' ').trim();
                      final age = int.tryParse(ageController.text.trim()) ?? 0;
                      _updateChild(child.copyWith(
                        name: name.isEmpty ? child.name : name,
                        firstName: first,
                        lastName: last,
                        age: age,
                        grade: gradeController.text.trim(),
                        schoolCode: schoolCodeController.text.trim(),
                      ));
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                    child: const Text('שמור'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildTile extends StatelessWidget {
  final ChildEntity child;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ChildTile({
    required this.child,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? const BorderSide(color: AppTheme.primaryBlue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: AppTheme.primaryBlue, size: 24),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isActive ? AppTheme.primaryBlue : null,
                      ),
                    ),
                    if (child.firstName.isNotEmpty || child.lastName.isNotEmpty || child.age > 0 || child.schoolCode.isNotEmpty)
                      Text(
                        [
                          if (child.age > 0) 'גיל ${child.age}',
                          if (child.schoolCode.isNotEmpty) 'קוד בית ספר: ${child.schoolCode}',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        child.connectionStatusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: child.isConnected
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isActive)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'פעיל',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
                tooltip: 'ערוך',
              ),
              IconButton(
                icon: Icon(Icons.person_remove_outlined, color: Colors.red.shade700),
                onPressed: onRemove,
                tooltip: 'הסר ילד',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkSection extends StatelessWidget {
  final ChildEntity child;

  const _LinkSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'פרטי ${child.name}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (child.firstName.isNotEmpty || child.lastName.isNotEmpty) ...[
              Text('שם פרטי: ${child.firstName}', style: const TextStyle(fontSize: 14)),
              Text('שם משפחה: ${child.lastName}', style: const TextStyle(fontSize: 14)),
            ],
            if (child.age > 0) Text('גיל: ${child.age}', style: const TextStyle(fontSize: 14)),
            if (child.schoolCode.isNotEmpty) Text('קוד בית ספר: ${child.schoolCode}', style: const TextStyle(fontSize: 14)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    child.isConnected ? Icons.check_circle : Icons.schedule,
                    size: 18,
                    color: child.isConnected ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    child.connectionStatusLabel,
                    style: TextStyle(
                      fontSize: 14,
                      color: child.isConnected ? Colors.green.shade700 : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (child.linkCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('קוד ששימש לחיבור: ${child.linkCode}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }
}
