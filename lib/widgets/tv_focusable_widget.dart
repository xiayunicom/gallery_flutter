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
  final FocusNode? focusNode; // 可选：允许外部传入 FocusNode

  const TVFocusableWidget({
    super.key, // 确保在父组件使用时传入 Key，例如 key: ValueKey(path)
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.isSelected = false,
    this.borderRadius = 4.0,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            onTap();
            return null;
          },
        ),
      },
      shortcuts: {
        // Android TV 的“确定/中间键”通常是 select
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        // 部分遥控器可能是 enter
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        // 删除了不存在的 LogicalKeyboardKey.center
      },
      child: Builder(
        builder: (context) {
          final bool focused = Focus.of(context).hasFocus;

          return GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            child: AnimatedContainer(
              // 如果觉得卡顿，可以将 duration 改为 Duration.zero
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                // 焦点状态样式
                border: focused
                    ? Border.all(color: Colors.white, width: 2)
                    : (isSelected
                          ? Border.all(color: Colors.tealAccent, width: 2)
                          : Border.all(color: Colors.transparent, width: 2)),
                // 阴影：如果低端盒子卡顿，建议去掉下面的 boxShadow 属性
                boxShadow: focused
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
