import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => windowManager.minimize(),
          icon: const Icon(Icons.minimize, color: Colors.white),
          tooltip: 'Minimize',
        ),
        IconButton(
          onPressed: () async {
            if (await windowManager.isFullScreen()) {
              windowManager.setFullScreen(false);
            } else {
              windowManager.setFullScreen(true);
            }
          },
          icon: const Icon(Icons.crop_square, color: Colors.white),
          tooltip: 'Maximize / Restore',
        ),
        IconButton(
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Close',
          hoverColor: Colors.red,
        ),
      ],
    );
  }
}
