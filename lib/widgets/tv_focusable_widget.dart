// lib/widgets/tv_focusable_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TVFocusableWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) => onTap(),
        ),
      },
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.select): ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Builder(
        builder: (context) {
          final bool focused = Focus.of(context).hasFocus;

          return GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: focused
                    ? Border.all(color: Colors.white, width: 3)
                    : (isSelected
                        ? Border.all(color: Colors.tealAccent, width: 3)
                        : null),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}