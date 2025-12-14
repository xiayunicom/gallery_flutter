// lib/pages/video_player_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerPage({super.key, required this.videoUrl});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  bool _showSeekFeedback = false;
  String _seekText = "";

  // 记录下拉拖拽的偏移量
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(widget.videoUrl), play: true);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      player.playOrPause();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _seekRelative(Duration diff) {
    final position = player.state.position;
    final duration = player.state.duration;
    var newPosition = position + diff;

    if (newPosition < Duration.zero) newPosition = Duration.zero;
    if (newPosition > duration) newPosition = duration;

    player.seek(newPosition);

    setState(() {
      _showSeekFeedback = true;
      _seekText = "${diff.isNegative ? '-' : '+'}${diff.inSeconds.abs()}s";
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showSeekFeedback = false);
    });
  }

  Widget _buildCenteredControl(Widget child) {
    return Container(height: 48, alignment: Alignment.center, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    final bottomBarItems = [
      const SizedBox(width: 14),
      _buildCenteredControl(const MaterialPlayOrPauseButton()),
      const SizedBox(width: 14),
      _buildCenteredControl(const MaterialPositionIndicator()),
      const SizedBox(width: 14),
      Expanded(
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Transform.translate(
            offset: const Offset(0, -16),
            child: const MaterialSeekBar(),
          ),
        ),
      ),
      const SizedBox(width: 14),
      _buildCenteredControl(const MaterialFullscreenButton()),
      const SizedBox(width: 14),
    ];

    return Material(
      color: Colors.black,
      child: GestureDetector(
        // 添加垂直拖拽监听
        onVerticalDragUpdate: (details) {
          // 只允许向下拉
          if (details.delta.dy > 0 || _dragOffsetY > 0) {
            setState(() {
              _dragOffsetY += details.delta.dy;
              if (_dragOffsetY < 0) _dragOffsetY = 0;
            });
          }
        },
        onVerticalDragEnd: (details) {
          // 如果拖拽距离超过 100 或者快速向下滑动，则关闭页面
          if (_dragOffsetY > 100 || details.primaryVelocity! > 800) {
            Navigator.pop(context);
          } else {
            // 否则恢复原位
            setState(() {
              _dragOffsetY = 0.0;
            });
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) => _handleKeyEvent(node, event),
            child: Stack(
              children: [
                MaterialVideoControlsTheme(
                  normal: MaterialVideoControlsThemeData(
                    displaySeekBar: false,
                    topButtonBar: [
                      const SizedBox(width: 14),
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                    ],
                    topButtonBarMargin: EdgeInsets.only(top: topPadding),
                    bottomButtonBar: bottomBarItems,
                    bottomButtonBarMargin: const EdgeInsets.only(
                      bottom: 4,
                      left: 16,
                      right: 16,
                    ),
                    primaryButtonBar: [],
                  ),
                  fullscreen: MaterialVideoControlsThemeData(
                    displaySeekBar: false,
                    topButtonBar: [
                      const SizedBox(width: 14),
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                    ],
                    topButtonBarMargin: EdgeInsets.only(top: topPadding),
                    bottomButtonBar: bottomBarItems,
                    bottomButtonBarMargin: const EdgeInsets.only(
                      bottom: 40,
                      left: 16,
                      right: 16,
                    ),
                    primaryButtonBar: [],
                  ),
                  child: Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(
                      child: Video(
                        controller: controller,
                        controls: MaterialVideoControls,
                      ),
                    ),
                  ),
                ),
                if (_showSeekFeedback)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _seekText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
