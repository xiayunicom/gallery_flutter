// lib/widgets/tv_focusable_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';

class TVFocusableWidget extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool isSelected;
  final double borderRadius;
  final FocusNode? focusNode;
  final bool autofocus; // 确保保留了上一步添加的 autofocus 参数

  const TVFocusableWidget({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.isSelected = false,
    this.borderRadius = 4.0,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: focusNode,
      autofocus: autofocus,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            onTap();
            return null;
          },
        ),
      },
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      child: Builder(
        builder: (context) {
          final bool focused = Focus.of(context).hasFocus;

          final bool showFocusVisuals = focused && isAndroidTv;

          return GestureDetector(
            onTap: () {
              if (!focused) {
                Focus.of(context).requestFocus();
              }
              onTap();
            },
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                // [修改逻辑]
                // 1. 如果 showFocusVisuals (安卓获焦) -> 显示白色边框
                // 2. 否则看 isSelected -> 显示青色选中框
                // 3. 否则 -> 透明框
                border: showFocusVisuals
                    ? Border.all(color: Colors.white, width: 2)
                    : (isSelected
                          ? Border.all(color: Colors.tealAccent, width: 2)
                          : Border.all(color: Colors.transparent, width: 2)),
                // 阴影也只在安卓获焦时显示，避免桌面端鼠标划过时出现奇怪的阴影
                boxShadow: showFocusVisuals
                    ? [
                        const BoxShadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
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
