import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/genet_config.dart';
import '../core/pin_storage.dart';
import '../theme/app_theme.dart';

/// מסך הגדרות אבטחה - שינוי קוד PIN
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  void _changePin() async {
    final current = _currentPinController.text;
    final newPin = _newPinController.text;
    final confirm = _confirmPinController.text;

    if (newPin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('קוד PIN חייב להכיל לפחות 4 ספרות')),
      );
      return;
    }

    if (newPin != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('קוד PIN החדש איננו תואם לאימות')),
      );
      return;
    }

    final currentOk = await PinStorage.verifyPin(current);
    if (!currentOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('קוד PIN נוכחי שגוי')),
        );
      }
      return;
    }

    await PinStorage.savePin(newPin);
    await GenetConfig.setPin(newPin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('קוד PIN עודכן בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );
      _currentPinController.clear();
      _newPinController.clear();
      _confirmPinController.clear();
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הגדרות אבטחה'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.lock_reset,
              size: 64,
              color: AppTheme.primaryBlue.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            const Text(
              'שינוי קוד PIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _currentPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'קוד PIN נוכחי',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'קוד PIN חדש',
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'אימות קוד PIN חדש',
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _changePin,
              child: const Text('שנה קוד PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
