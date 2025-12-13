// lib/widgets/tv_focusable_widget.dart
import 'package:flutter/material.dart';

class TVFocusableWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool isSelected;
  final double borderRadius;

  const TVFocusableWidget({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.isSelected = false,
    this.borderRadius = 4.0,
  });

  @override
  State<TVFocusableWidget> createState() => _TVFocusableWidgetState();
}

class _TVFocusableWidgetState extends State<TVFocusableWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onSecondaryTap,
      onFocusChange: (value) {
        setState(() {
          _isFocused = value;
        });
      },
      borderRadius: BorderRadius.circular(widget.borderRadius),
      focusColor: Colors.white.withOpacity(0.1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(color: Colors.white, width: 3)
              : (widget.isSelected
                    ? Border.all(color: Colors.tealAccent, width: 3)
                    : Border.all(color: Colors.transparent, width: 0)),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}