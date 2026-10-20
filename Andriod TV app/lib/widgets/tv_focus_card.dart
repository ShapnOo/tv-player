import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tv_theme.dart';

class TVFocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final double width;
  final double height;
  final double borderRadius;
  final double scaleFactor;
  final Color focusBorderColor;
  final FocusNode? focusNode;
  final bool autoFocus;

  const TVFocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onFocusChange,
    required this.width,
    required this.height,
    this.borderRadius = 14.0,
    this.scaleFactor = 1.04,
    this.focusBorderColor = TVTheme.emerald,
    this.focusNode,
    this.autoFocus = false,
  });

  @override
  State<TVFocusCard> createState() => _TVFocusCardState();
}

class _TVFocusCardState extends State<TVFocusCard> {
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
  void didUpdateWidget(TVFocusCard oldWidget) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onFocusChange?.call(hasFocus);
        }
      });
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
            alignment: 0.5,
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
          scale: _isFocused ? widget.scaleFactor : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isFocused
                    ? widget.focusBorderColor
                    : Colors.white.withValues(alpha: 0.08),
                width: _isFocused ? 3.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.focusBorderColor.withValues(alpha: 0.4),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius - 2),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
