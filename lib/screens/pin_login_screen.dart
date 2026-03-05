import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/genet_config.dart';
import '../core/pin_storage.dart';
import '../theme/app_theme.dart';
import 'parent_shell.dart';

/// מסך הזנת PIN לאימות הורה
class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  void _checkPin() async {
    final enteredPin = _pinController.text;
    final ok = await PinStorage.verifyPin(enteredPin);

    if (ok) {
      if (Platform.isAndroid) GenetConfig.setPin(enteredPin);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ParentShell(),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('קוד PIN שגוי. נסה שוב.'),
            backgroundColor: Colors.red,
          ),
        );
        _pinController.clear();
        _focusNode.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אימות הורה'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.lock_outline,
              size: 80,
              color: AppTheme.primaryBlue.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 24),
            const Text(
              'הזן קוד PIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinController,
              focusNode: _focusNode,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: TextStyle(
                  letterSpacing: 8,
                  color: Colors.grey.shade400,
                ),
              ),
              onSubmitted: (_) => _checkPin(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _checkPin,
              child: const Text('כניסה'),
            ),
          ],
        ),
      ),
    );
  }
}
