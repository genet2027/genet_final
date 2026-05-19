import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/natural_text_field.dart';

/// Collects required first/last name for `genet_parents/{parentId}` before parent dashboard access.
///
/// [completedBuilder] builds the destination after a successful save (typically [ParentShell]).
class ParentProfileSetupScreen extends StatefulWidget {
  const ParentProfileSetupScreen({
    super.key,
    required this.completedBuilder,
  });

  final WidgetBuilder completedBuilder;

  @override
  State<ParentProfileSetupScreen> createState() => _ParentProfileSetupScreenState();
}

class _ParentProfileSetupScreenState extends State<ParentProfileSetupScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _saving = false;
  String? _validationMessage;
  String? _saveError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String? _validateFields() {
    final fn = _firstNameController.text.trim();
    final ln = _lastNameController.text.trim();
    if (fn.isEmpty) return 'יש למלא שם פרטי';
    if (ln.isEmpty) return 'יש למלא שם משפחה';
    return null;
  }

  Future<void> _onContinue() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saveError = null;
      _validationMessage = _validateFields();
    });
    if (_validationMessage != null) return;

    setState(() => _saving = true);
    try {
      await GenetConfig.commitUserRole(kUserRoleParent);
      final parentId = await getOrCreateParentId();
      if (!mounted) return;
      if (parentId.trim().isEmpty) {
        setState(() {
          _saveError = 'לא ניתן ליצור מזהה הורה. נסה שוב.';
        });
        return;
      }
      await saveParentProfile(
        parentId: parentId,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
      );
      debugPrint('[GENET][PROFILE] parent_profile_saved');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => widget.completedBuilder(context),
        ),
      );
    } catch (e, st) {
      debugPrint('[GENET][PARENT_PROFILE][ERROR] save_failed: $e');
      debugPrint('[GENET][PARENT_PROFILE][ERROR] stack: $st');
      if (mounted) {
        setState(() {
          _saveError = 'לא ניתן לשמור את הפרטים. נסה שוב.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('פרטי הורה'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'פרטי הורה',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkBlue,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'כדי להמשיך, מלא את הפרטים שלך. הפרטים יוצגו לילד לאחר החיבור.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                NaturalTextField(
                  controller: _firstNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'שם פרטי',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                NaturalTextField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _onContinue(),
                  decoration: const InputDecoration(
                    labelText: 'שם משפחה',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'השם יוצג לילד כדי לוודא שהוא מחובר להורה הנכון.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_validationMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validationMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _saveError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _saving ? null : _onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('שמור והמשך'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
