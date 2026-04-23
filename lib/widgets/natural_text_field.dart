import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

TextDirection naturalTextDirectionFor(
  String text, {
  TextDirection fallback = TextDirection.rtl,
}) {
  for (final rune in text.runes) {
    if (_isHebrewRune(rune) || _isArabicRune(rune)) {
      return TextDirection.rtl;
    }
    if (_isLatinRune(rune)) {
      return TextDirection.ltr;
    }
  }
  return fallback;
}

class NaturalTextField extends StatefulWidget {
  const NaturalTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.enabled,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final bool? enabled;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NaturalTextField> createState() => _NaturalTextFieldState();
}

class _NaturalTextFieldState extends State<NaturalTextField> {
  late TextDirection _textDirection;

  @override
  void initState() {
    super.initState();
    _textDirection = naturalTextDirectionFor(widget.controller.text);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant NaturalTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      _textDirection = naturalTextDirectionFor(widget.controller.text);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    final nextDirection = naturalTextDirectionFor(widget.controller.text);
    if (_textDirection != nextDirection && mounted) {
      setState(() => _textDirection = nextDirection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      onSubmitted: widget.onSubmitted,
      textDirection: _textDirection,
      textAlign: TextAlign.start,
    );
  }
}

bool _isHebrewRune(int rune) => rune >= 0x0590 && rune <= 0x05FF;

bool _isArabicRune(int rune) => rune >= 0x0600 && rune <= 0x06FF;

bool _isLatinRune(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) ||
    (rune >= 0x0061 && rune <= 0x007A) ||
    (rune >= 0x00C0 && rune <= 0x024F);
