// lib/pages/video_player_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ==========================================
// 视频播放器封装组件 (已移除 SimpleVideoPlayer，集中优化 VideoPlayerPage)
// ==========================================

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerPage({super.key, required this.videoUrl});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  // 用于显示快进/快退的临时提示
  bool _showSeekFeedback = false;
  String _seekText = "";

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

  // 📺 核心修复：处理遥控器按键
  KeyEventResult _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // 1. 返回键：退出播放
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }

    // 2. 播放/暂停：支持 播放键、暂停键、空格键、确定键(Select/Center/Enter)
    // 注意：我们将 OK 键映射为播放/暂停，这是电视播放器的通用逻辑
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      player.playOrPause();
      return KeyEventResult.handled;
    }

    // 3. 快进/快退：方向键左右 (步进 10秒)
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }

    // 4. 方向键上下：可以用来显示/隐藏控制栏 (media_kit 默认可能不支持外部控制显隐，这里留空或做其他扩展)
    // 如果需要调节音量，可以在这里处理 ArrowUp/ArrowDown

    return KeyEventResult.ignored;
  }

  void _seekRelative(Duration diff) {
    final position = player.state.position;
    final duration = player.state.duration;
    var newPosition = position + diff;

    // 边界检查
    if (newPosition < Duration.zero) newPosition = Duration.zero;
    if (newPosition > duration) newPosition = duration;

    player.seek(newPosition);

    // 显示简单的反馈 UI
    setState(() {
      _showSeekFeedback = true;
      _seekText = "${diff.isNegative ? '-' : '+'}${diff.inSeconds.abs()}s";
    });

    // 1.5秒后隐藏反馈
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
      child: Focus(
        autofocus: true, // 📺 确保页面进入后立即获得焦点，响应按键
        onKey: (node, event) => _handleKeyEvent(event),
        child: Stack(
          children: [
            // 视频主体
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

            // 📺 快进/快退 反馈 UI
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
    );
  }
}
