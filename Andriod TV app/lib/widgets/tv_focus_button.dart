import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tv_theme.dart';

class TVFocusButton extends StatefulWidget {
  final Widget? icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final FocusNode? focusNode;
  final bool autoFocus;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final double? iconSize;
  final double borderRadius;

  const TVFocusButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = true,
    this.focusNode,
    this.autoFocus = false,
    this.padding,
    this.fontSize,
    this.iconSize,
    this.borderRadius = 8.0,
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
    _isFocused = _node.hasFocus;
    if (_isFocused || widget.autoFocus) {
      _ensureVisible();
    }
  }

  @override
  void didUpdateWidget(TVFocusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) {
        _node.dispose();
      } else {
        oldWidget.focusNode!.removeListener(_handleFocusChange);
      }
      _node = widget.focusNode ?? FocusNode();
      _node.addListener(_handleFocusChange);
      _isFocused = _node.hasFocus;
      if (_isFocused) {
        _ensureVisible();
      }
    }
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final hasFocus = _node.hasFocus;
    if (_isFocused != hasFocus) {
      _safeSetState(() {
        _isFocused = hasFocus;
      });
      if (hasFocus) {
        _ensureVisible();
      }
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro = context.findRenderObject();
      if (ro == null) return;

      BuildContext? ctx = context;
      bool handledHorizontal = false;
      bool handledVertical = false;

      while (ctx != null && (!handledHorizontal || !handledVertical)) {
        final scrollable = Scrollable.maybeOf(ctx);
        if (scrollable == null) break;

        if (scrollable.position.axis == Axis.horizontal && !handledHorizontal) {
          scrollable.position.ensureVisible(
            ro,
            alignment: 0.1,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          handledHorizontal = true;
        } else if (scrollable.position.axis == Axis.vertical && !handledVertical) {
          scrollable.position.ensureVisible(
            ro,
            alignment: 0.15,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          handledVertical = true;
        }

        ctx = scrollable.context;
      }
    });
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
    // Authentic Netflix styling:
    // Primary: White background with black text (turns glowing Emerald when focused)
    // Secondary: Translucent glass with white text (turns solid White with black text when focused)
    final bgColor = _isFocused
        ? (widget.isPrimary ? TVTheme.emerald : Colors.white)
        : (widget.isPrimary
            ? Colors.white
            : Colors.white.withValues(alpha: 0.18));

    final textColor = _isFocused
        ? Colors.black
        : (widget.isPrimary ? Colors.black : Colors.white);

    final effectivePadding = widget.padding ??
        (widget.isPrimary
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 7.5)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5));

    final effectiveFontSize = widget.fontSize ?? (widget.isPrimary ? 13.0 : 12.0);
    final effectiveIconSize = widget.iconSize ?? (widget.isPrimary ? 18.0 : 15.0);

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
          scale: _isFocused ? 1.07 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: effectivePadding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18),
                width: _isFocused ? 2.0 : 1.0,
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
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: textColor,
                      size: effectiveIconSize,
                    ),
                    child: widget.icon!,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: effectiveFontSize,
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
