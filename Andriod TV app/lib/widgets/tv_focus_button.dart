import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tv_theme.dart';

class TVFocusButton extends StatefulWidget {
  final Widget? icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final FocusNode? focusNode;
  final bool autoFocus;

  const TVFocusButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = true,
    this.focusNode,
    this.autoFocus = false,
  });

  @override
  State<TVFocusButton> createState() => _TVFocusButtonState();
}

class _TVFocusButtonState extends State<TVFocusButton> {
  late FocusNode _node;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _node.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isFocused
        ? (widget.isPrimary ? TVTheme.emerald : Colors.white)
        : (widget.isPrimary
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.4));

    final textColor = _isFocused
        ? (widget.isPrimary ? Colors.black : Colors.black)
        : Colors.white;

    return Focus(
      focusNode: _node,
      autofocus: widget.autoFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
                width: _isFocused ? 2.5 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color:
                            (widget.isPrimary ? TVTheme.emerald : Colors.white)
                                .withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  IconTheme(
                    data: IconThemeData(color: textColor, size: 18),
                    child: widget.icon!,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
