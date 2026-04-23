import 'package:flutter/material.dart';

import '../models/parent_message.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';
import 'natural_text_field.dart';

class ParentMessageHistorySection extends StatefulWidget {
  const ParentMessageHistorySection({
    super.key,
    this.refreshKeyValue = 0,
  });

  final int refreshKeyValue;

  @override
  State<ParentMessageHistorySection> createState() =>
      _ParentMessageHistorySectionState();
}

class _ParentMessageHistorySectionState
    extends State<ParentMessageHistorySection>
    with SingleTickerProviderStateMixin {
  static const int _kMessageMaxLength = 150;
  static const List<String> _kQuickEmojis = <String>[
    '❤️',
    '🎉',
    '📚',
    '💙',
    '🔥',
    '👏',
    '😊',
    '🌟',
  ];
  static const double _kPreviewBubbleHeight = 74;
  static const double _kPreviewGap = 8;
  static const double _kPreviewHeight =
      (_kPreviewBubbleHeight * 2) + _kPreviewGap;

  final TextEditingController _controller = TextEditingController();
  List<ParentMessage> _messages = const <ParentMessage>[];
  List<ParentMessage> _visibleMessages = const <ParentMessage>[];
  String? _selectedChildId;
  String _selectedChildName = '';
  bool _loading = true;
  bool _sending = false;
  late final AnimationController _outgoingPreviewController;
  ParentMessage? _outgoingPreviewMessage;

  @override
  void initState() {
    super.initState();
    _outgoingPreviewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _outgoingPreviewMessage = null);
      }
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant ParentMessageHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKeyValue != widget.refreshKeyValue) {
      _load();
    }
  }

  @override
  void dispose() {
    _outgoingPreviewController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<ParentMessage> _selectVisibleMessages(List<ParentMessage> messages) {
    if (messages.length <= 2) return List<ParentMessage>.from(messages);
    return List<ParentMessage>.from(messages.sublist(messages.length - 2));
  }

  void _applyMessages(
    List<ParentMessage> messages, {
    required bool animatePreview,
    bool clearComposer = false,
  }) {
    final nextVisible = _selectVisibleMessages(messages);
    final previousVisible = _visibleMessages;
    final shouldAnimateOutgoing =
        animatePreview &&
        previousVisible.length == 2 &&
        nextVisible.length == 2 &&
        previousVisible.first.id != nextVisible.first.id;

    if (clearComposer) {
      _controller.clear();
    }

    setState(() {
      _messages = messages;
      _visibleMessages = nextVisible;
      if (shouldAnimateOutgoing) {
        _outgoingPreviewMessage = previousVisible.first;
      } else {
        _outgoingPreviewMessage = null;
      }
    });

    if (shouldAnimateOutgoing) {
      _outgoingPreviewController.forward(from: 0);
    } else {
      _outgoingPreviewController.stop();
      _outgoingPreviewController.value = 0;
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final previousChildId = _selectedChildId;
    final childId = await getSelectedChildId();
    final child =
        childId == null || childId.isEmpty ? null : await getChildById(childId);
    final messages =
        childId == null || childId.isEmpty
            ? const <ParentMessage>[]
            : await getParentMessageHistoryFromFirebase(childId);
    if (!mounted) return;
    setState(() {
      _selectedChildId = childId;
      _selectedChildName = child?.name ?? '';
      _loading = false;
    });
    _applyMessages(
      messages,
      animatePreview: false,
      clearComposer: previousChildId != childId,
    );
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final childId = _selectedChildId;
    if (childId == null || childId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('בחר ילד לפני שליחת הודעה.')),
      );
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('כתוב הודעה קצרה לילד.')),
      );
      return;
    }
    if (text.length > _kMessageMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ההודעה ארוכה מדי.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final message = await addParentMessageToFirebase(
        childId,
        text: text,
      );
      if (!mounted) return;
      _applyMessages(
        [..._messages, message],
        animatePreview: true,
        clearComposer: true,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ההודעה נשלחה לילד.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שליחת ההודעה נכשלה. נסה שוב.')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final safeStart = start < 0 ? value.text.length : start;
    final safeEnd = end < 0 ? value.text.length : end;
    final nextText = value.text.replaceRange(safeStart, safeEnd, emoji);
    final nextOffset = safeStart + emoji.length;
    _controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _openEmojiPicker() async {
    if (_sending || _loading) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'הוספת אימוג׳י',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        _kQuickEmojis
                            .map(
                              (emoji) => InkWell(
                                onTap: () {
                                  _insertEmoji(emoji);
                                  Navigator.pop(context);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppTheme.lightBlue.withValues(
                                      alpha: 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildPreviewArea(bool disabled) {
    if (_loading) {
      return const SizedBox(
        height: _kPreviewHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_visibleMessages.isEmpty) {
      return SizedBox(
        height: _kPreviewHeight,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              disabled
                  ? 'בחר ילד כדי להתחיל לשלוח הודעות.'
                  : 'אין הודעות עדיין. המסר הראשון שלך יופיע כאן.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 13,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      );
    }

    final topMessage = _visibleMessages.isNotEmpty ? _visibleMessages.first : null;
    final bottomMessage =
        _visibleMessages.length > 1 ? _visibleMessages.last : null;

    return SizedBox(
      height: _kPreviewHeight,
      child: ClipRect(
        child: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: _kPreviewBubbleHeight,
                  child:
                      topMessage == null
                          ? const SizedBox.shrink()
                          : _PreviewMessageBubble(message: topMessage),
                ),
                const SizedBox(height: _kPreviewGap),
                SizedBox(
                  height: _kPreviewBubbleHeight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child:
                        bottomMessage == null
                            ? const SizedBox(key: ValueKey('preview-bottom-empty'))
                            : KeyedSubtree(
                              key: ValueKey('preview-bottom-${bottomMessage.id}'),
                              child: _PreviewMessageBubble(message: bottomMessage),
                            ),
                  ),
                ),
              ],
            ),
            if (_outgoingPreviewMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _outgoingPreviewController,
                    child: _PreviewMessageBubble(
                      message: _outgoingPreviewMessage!,
                    ),
                    builder: (context, child) {
                      final curved = Curves.easeOutCubic.transform(
                        _outgoingPreviewController.value,
                      );
                      return Opacity(
                        opacity: 1 - curved,
                        child: Transform.translate(
                          offset: Offset(0, -14 * curved),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _selectedChildId == null || _selectedChildId!.isEmpty;
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Message to Child',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedChildName.isNotEmpty
                              ? 'שלח/י מסר קצר ל$_selectedChildName'
                              : 'שלח/י מסר קצר ותומך לילד',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildPreviewArea(disabled),
              const SizedBox(height: 14),
              NaturalTextField(
                controller: _controller,
                enabled: !disabled && !_loading,
                maxLength: _kMessageMaxLength,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'כתוב/כתבי מסר קצר לילד',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.92),
                  counterStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed:
                        disabled || _loading || _sending
                            ? null
                            : _openEmojiPicker,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
                    tooltip: 'הוסף אימוג׳י',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          disabled || _loading || _sending ? null : _sendMessage,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryBlue,
                      ),
                      child: Text(_sending ? 'שולח...' : 'Send Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewMessageBubble extends StatelessWidget {
  const _PreviewMessageBubble({required this.message});

  final ParentMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: naturalTextDirectionFor(message.body),
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatTime(message.updatedAt),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }
}
