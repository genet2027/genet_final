import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/children_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/natural_text_field.dart';
import '../child_home_screen.dart';

/// Step 1: Child enters first name, last name, age, school code. Saved locally and used when linking to parent.
class ChildSelfIdentifyScreen extends StatefulWidget {
  const ChildSelfIdentifyScreen({super.key});

  @override
  State<ChildSelfIdentifyScreen> createState() => _ChildSelfIdentifyScreenState();
}

class _ChildSelfIdentifyScreenState extends State<ChildSelfIdentifyScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _schoolCodeController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _schoolCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      setState(() => _error = 'הזן שם פרטי או שם משפחה');
      return;
    }
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final schoolCode = _schoolCodeController.text.trim();
    setState(() => _error = null);
    await saveChildSelfProfile(
      firstName: firstName,
      lastName: lastName,
      age: age,
      schoolCode: schoolCode,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הזדהות'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'הזן את הפרטים שלך',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'הפרטים יישמרו במכשיר ויועברו להורה אחרי החיבור.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              NaturalTextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'שם פרטי',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              NaturalTextField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'שם משפחה',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              NaturalTextField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: 'גיל',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              NaturalTextField(
                controller: _schoolCodeController,
                decoration: const InputDecoration(
                  labelText: 'קוד בית ספר',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('המשך לחיבור להורה'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
