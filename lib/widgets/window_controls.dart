import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkFullScreen();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkFullScreen() async {
    bool isFull = await windowManager.isFullScreen();
    if (mounted && _isFullScreen != isFull) {
      setState(() {
        _isFullScreen = isFull;
      });
    }
  }

  @override
  void onWindowEnterFullScreen() {
    _checkFullScreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    _checkFullScreen();
  }

  // Listen to other events just in case
  @override
  void onWindowMaximize() {
    _checkFullScreen();
  }

  @override
  void onWindowUnmaximize() {
    _checkFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _isFullScreen ? null : () => windowManager.minimize(),
          icon: Icon(
            Icons.minimize,
            color: _isFullScreen ? Colors.white24 : Colors.white,
          ),
          splashRadius: 20,
          tooltip: 'Minimize',
        ),
        IconButton(
          onPressed: () async {
            if (_isFullScreen) {
              await windowManager.setFullScreen(false);
            } else {
              await windowManager.setFullScreen(true);
            }
            // Manually check state after action, as events might lag
            await Future.delayed(const Duration(milliseconds: 200));
            if (mounted) _checkFullScreen();
          },
          icon: const Icon(Icons.crop_square, color: Colors.white),
          splashRadius: 20,
          tooltip: _isFullScreen ? 'Restore' : 'Maximize / FullScreen',
        ),
        IconButton(
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close, color: Colors.white),
          splashRadius: 20,
          tooltip: 'Close',
          hoverColor: Colors.red,
        ),
      ],
    );
  }
}
