import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/child_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/natural_text_field.dart';

/// Child definition screen (Parent only). שם, גיל, כיתה, קוד בית ספר. Saves to SharedPreferences and pops.
class ChildSettingsScreen extends StatefulWidget {
  const ChildSettingsScreen({super.key});

  @override
  State<ChildSettingsScreen> createState() => _ChildSettingsScreenState();
}

class _ChildSettingsScreenState extends State<ChildSettingsScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _gradeController = TextEditingController();
  final _schoolCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = await ChildModel.load();
    if (model != null && mounted) {
      _nameController.text = model.name;
      _ageController.text = model.age > 0 ? model.age.toString() : '';
      _gradeController.text = model.grade;
      _schoolCodeController.text = model.schoolCode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _gradeController.dispose();
    _schoolCodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final model = ChildModel(
      name: _nameController.text.trim(),
      age: age,
      grade: _gradeController.text.trim(),
      schoolCode: _schoolCodeController.text.trim(),
    );
    await ChildModel.save(model);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('נשמר בהצלחה')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הגדרת ילד'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            NaturalTextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            NaturalTextField(
              controller: _ageController,
              decoration: const InputDecoration(
                labelText: 'גיל',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            NaturalTextField(
              controller: _gradeController,
              decoration: const InputDecoration(
                labelText: 'כיתה',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            NaturalTextField(
              controller: _schoolCodeController,
              decoration: const InputDecoration(
                labelText: 'קוד בית ספר',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
  }
}
