// lib/pages/video_player_page.dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ==========================================
// 视频播放器封装组件 (底部单行布局优化)
// ==========================================
class SimpleVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;

  const SimpleVideoPlayer({super.key, required this.url, this.autoPlay = true});

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    await player.open(Media(widget.url), play: widget.autoPlay);
    await player.setPlaylistMode(PlaylistMode.loop);
    await player.setVolume(100);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    // 1. 顶部栏：只有返回箭头
    final List<Widget> topBarItems = [
      const SizedBox(width: 10),
      IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 26,
          shadows: [
            Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
      ),
      const Spacer(),
    ];

    // 2. 底部栏：所有元素在一行 [播放] [时间] [-----进度条-----] [全屏]
    final List<Widget> bottomBarItems = [
      const SizedBox(width: 20), // 左侧间距
      // 播放/暂停按钮
      const MaterialPlayOrPauseButton(
        iconSize: 32, // 稍微大一点
      ),
      const SizedBox(width: 8),

      // 时间显示 (当前 / 总时长)
      const MaterialPositionIndicator(),
      const SizedBox(width: 8),

      // 进度条 (使用 Expanded 占据剩余空间，强制在同一行)
      const Expanded(child: MaterialSeekBar()),

      const SizedBox(width: 8),

      // 全屏按钮
      const MaterialFullscreenButton(iconSize: 28),
      const SizedBox(width: 20), // 右侧间距
    ];

    final themeData = MaterialVideoControlsThemeData(
      // 顶部配置
      topButtonBar: topBarItems,
      topButtonBarMargin: EdgeInsets.only(top: topPadding > 0 ? topPadding : 8),

      // 底部配置
      bottomButtonBar: bottomBarItems,
      // 底部稍微留点空隙，不要贴着屏幕边缘
      bottomButtonBarMargin: const EdgeInsets.only(bottom: 20),
    );

    return Material(
      color: Colors.black,
      child: MaterialVideoControlsTheme(
        normal: themeData,
        fullscreen: themeData,
        child: Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Video(
              controller: controller,
              fit: BoxFit.contain,
              controls: (state) => MaterialVideoControls(state),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerPage({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

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

  // 封装一个辅助方法，确保所有底部按钮高度一致且绝对居中
  Widget _buildCenteredControl(Widget child) {
    return Container(
      height: 48, // 强制固定高度，确保所有元素基准线一致
      alignment: Alignment.center, // 强制内容垂直居中
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    // 这一段定义底部栏的布局，普通模式和全屏模式复用
    final bottomBarItems = [
      const SizedBox(width: 14),

      // 1. 播放/暂停按钮 (包裹在居中容器里)
      _buildCenteredControl(const MaterialPlayOrPauseButton()),

      const SizedBox(width: 14),

      // 2. 时间显示 (包裹在居中容器里)
      _buildCenteredControl(const MaterialPositionIndicator()),

      const SizedBox(width: 14),

      // 3. 进度条 (使用 Expanded 占满剩余空间，且内部也强制居中)
      Expanded(
        child: Container(
          height: 48,
          alignment: Alignment.center,
          // 👇👇👇 使用 Transform.translate 强制下移 👇👇👇
          child: Transform.translate(
            offset: const Offset(0, -16), // 向下平移 2 像素（根据视觉感觉微调，不行就改成 4）
            child: const MaterialSeekBar(),
          ),
        ),
      ),
      const SizedBox(width: 14),

      // 4. 全屏按钮 (包裹在居中容器里)
      _buildCenteredControl(const MaterialFullscreenButton()),

      const SizedBox(width: 14),
    ];

    return Material(
      color: Colors.black,
      child: MaterialVideoControlsTheme(
        // 1. 普通模式配置
        normal: MaterialVideoControlsThemeData(
          displaySeekBar: false, // 隐藏默认的顶部进度条
          topButtonBar: [
            const SizedBox(width: 14),
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
          ],
          topButtonBarMargin: EdgeInsets.only(top: topPadding),

          // 使用上面定义好的对齐 Item
          bottomButtonBar: bottomBarItems,

          bottomButtonBarMargin: const EdgeInsets.only(
            bottom: 4,
            left: 16,
            right: 16,
          ),
          primaryButtonBar: [], // 隐藏中间大播放按钮
        ),

        // 2. 全屏模式配置
        fullscreen: MaterialVideoControlsThemeData(
          displaySeekBar: false,
          topButtonBar: [
            const SizedBox(width: 14),
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
          ],
          topButtonBarMargin: EdgeInsets.only(top: topPadding),

          // 复用同样的底部栏
          bottomButtonBar: bottomBarItems,

          bottomButtonBarMargin: const EdgeInsets.only(
            bottom: 24,
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
    );
  }
}
