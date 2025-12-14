// lib/pages/photo_preview_page.dart
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../config.dart';
import '../services/task_manager.dart';

class PhotoPreviewPage extends StatefulWidget {
  final List<dynamic> images;
  final int initialIndex;
  const PhotoPreviewPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });
  @override
  State<PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<PhotoPreviewPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int currentIndex;
  late List<dynamic> _currentImages;
  
  // 管理每一页的缩放控制器
  final Map<int, PhotoViewController> _controllers = {};

  bool showControls = false;
  bool isPlaying = false;
  Timer? _autoPlayTimer;
  late AnimationController _breatheController;
  Offset _dragOffset = Offset.zero;
  double _dragScale = 1.0;
  AnimationController? _resetController;
  Animation<Offset>? _offsetAnimation;
  Animation<double>? _scaleAnimation;
  
  // 核心状态：是否处于放大状态
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _currentImages = List.from(widget.images);
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.5,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    _breatheController.dispose();
    _resetController?.dispose();
    
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    
    super.dispose();
  }

  PhotoViewController _getController(int index) {
    if (!_controllers.containsKey(index)) {
      _controllers[index] = PhotoViewController();
    }
    return _controllers[index]!;
  }

  // 处理鼠标滚轮缩放
  void _handleScroll(PointerScrollEvent event) {
    // 如果正在执行下滑关闭动作，禁止缩放
    if (_dragScale != 1.0) return;

    final controller = _getController(currentIndex);
    double currentScale = controller.scale ?? 1.0;
    
    // 向上滚动(dy<0)放大，向下滚动(dy>0)缩小
    double zoomFactor = 0.08; 
    double delta = event.scrollDelta.dy > 0 ? -zoomFactor : zoomFactor;
    double newScale = currentScale + delta;

    // 限制缩放范围
    if (newScale < 0.1) newScale = 0.1;
    if (newScale > 5.0) newScale = 5.0;

    controller.scale = newScale;
    
    // 手动更新缩放状态（辅助 PhotoView 的状态回调）
    // 注意：这里阈值设为 1.0 可能不准确（取决于 initialScale），但在大多数 contained 模式下是有效的参考
    // 更准确的逻辑由 scaleStateChangedCallback 处理，这里主要处理滚轮的即时反馈
    if (newScale > 1.05 && !_isZoomed) {
       setState(() => _isZoomed = true);
    }
  }

  void _toggleControls() {
    setState(() {
      showControls = !showControls;
    });
    if (showControls) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
  }

  void _toggleAutoPlay() {
    setState(() {
      isPlaying = !isPlaying;
    });
    if (isPlaying) {
      _breatheController.repeat(reverse: true);
      _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (currentIndex < _currentImages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else {
          _pageController.jumpToPage(0);
        }
      });
    } else {
      _breatheController.stop();
      _breatheController.value = 1.0;
      _autoPlayTimer?.cancel();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // 【关键】如果处于缩放状态，直接忽略下滑关闭逻辑
    if (_isZoomed) return;

    setState(() {
      double dy = _dragOffset.dy + details.delta.dy;
      double dx = _dragOffset.dx + details.delta.dx;
      // 向上拖动阻尼更大
      if (dy < 0) dy *= 0.4;
      _dragOffset = Offset(dx, dy);
      final screenHeight = MediaQuery.of(context).size.height;
      double progress = (_dragOffset.dy.abs() / screenHeight).clamp(0.0, 1.0);
      _dragScale = 1.0 - (progress * 0.4);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    
    final velocity = details.primaryVelocity ?? 0;
    final screenHeight = MediaQuery.of(context).size.height;
    final threshold = screenHeight * 0.15;
    if (_dragOffset.dy > threshold || velocity > 800) {
      Navigator.pop(context, currentIndex);
    } else {
      _runResetAnimation();
    }
  }

  void _runResetAnimation() {
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnimation = Tween<Offset>(begin: _dragOffset, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _resetController!, curve: Curves.easeOutBack),
        );
    _scaleAnimation = Tween<double>(begin: _dragScale, end: 1.0).animate(
      CurvedAnimation(parent: _resetController!, curve: Curves.easeOut),
    );
    _resetController!.addListener(() {
      setState(() {
        _dragOffset = _offsetAnimation!.value;
        _dragScale = _scaleAnimation!.value;
      });
    });
    _resetController!.forward();
  }

  Future<void> _deleteCurrentPhoto() async {
    bool wasPlaying = isPlaying;
    if (wasPlaying) _toggleAutoPlay();
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text(
          "Confirm Delete",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to delete this image?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final item = _currentImages[currentIndex];
      try {
        await Dio().post(
          '$serverUrl/api/delete',
          data: FormData.fromMap({'path': item['path']}),
        );
        setState(() {
          _currentImages.removeAt(currentIndex);
          _controllers[currentIndex]?.dispose();
          _controllers.remove(currentIndex);
          _controllers.clear(); 

          if (currentIndex >= _currentImages.length)
            currentIndex = _currentImages.length - 1;
        });
        if (_currentImages.isEmpty) {
          Navigator.pop(context, -1);
        } else if (wasPlaying) {
          _toggleAutoPlay();
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
      }
    } else if (wasPlaying) {
      _toggleAutoPlay();
    }
  }

  Future<void> _renameCurrentPhoto() async {
    final item = _currentImages[currentIndex];
    final String currentPath = item['path'];
    final String currentName = item['name'];

    TextEditingController controller = TextEditingController(text: currentName);

    String? newName = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Rename", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.tealAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text("Rename"),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await Dio().post(
          '$serverUrl/api/rename',
          data: FormData.fromMap({'path': currentPath, 'name': newName}),
        );

        String parentPath = currentPath.substring(
          0,
          currentPath.lastIndexOf('/') + 1,
        );
        String newPath = parentPath + newName;

        setState(() {
          _currentImages[currentIndex]['name'] = newName;
          _currentImages[currentIndex]['path'] = newPath;
          TaskManager().bumpVersions([newPath]);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Renamed successfully"),
            duration: Duration(seconds: 1),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Rename failed: $e")));
      }
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.pop(context, currentIndex);
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _toggleAutoPlay();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _deleteCurrentPhoto();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentImages.isEmpty) return const SizedBox();
    final currentItem = _currentImages[currentIndex];
    final platform = Theme.of(context).platform;
    final isMobile =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    final screenHeight = MediaQuery.of(context).size.height;
    double opacityProgress = (_dragOffset.dy.abs() / (screenHeight * 0.5))
        .clamp(0.0, 1.0);
    double bgOpacity = 1.0 - opacityProgress;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Focus(
        autofocus: true,
        onKey: (node, event) {
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _handleScroll(event);
              }
            },
            child: Stack(
              children: [
                Container(color: Colors.black.withOpacity(bgOpacity)),
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _toggleControls,
                    // 【关键修改】如果处于缩放状态，将外层的拖动回调设为 null
                    // 这样手势事件就会穿透给 PhotoView，实现放大后的拖动（Pan）
                    onVerticalDragUpdate: _isZoomed ? null : _onVerticalDragUpdate,
                    onVerticalDragEnd: _isZoomed ? null : _onVerticalDragEnd,
                    child: Transform.translate(
                      offset: _dragOffset,
                      child: Transform.scale(
                        scale: _dragScale,
                        child: PhotoViewGallery.builder(
                          scrollPhysics: const BouncingScrollPhysics(),
                          // 监听缩放状态变化，更新 _isZoomed
                          scaleStateChangedCallback: (state) => setState(
                            () => _isZoomed = state != PhotoViewScaleState.initial,
                          ),
                          builder: (context, index) {
                            final item = _currentImages[index];
                            final imgUrl = TaskManager().getImgUrl(item['path']);
                            return PhotoViewGalleryPageOptions(
                              imageProvider: CachedNetworkImageProvider(imgUrl),
                              initialScale: PhotoViewComputedScale.contained,
                              minScale: PhotoViewComputedScale.contained * 0.8,
                              maxScale: PhotoViewComputedScale.covered * 4,
                              heroAttributes: PhotoViewHeroAttributes(
                                tag: item['path'],
                              ),
                              controller: _getController(index),
                            );
                          },
                          itemCount: _currentImages.length,
                          loadingBuilder: (context, event) =>
                              const Center(child: CircularProgressIndicator()),
                          pageController: _pageController,
                          onPageChanged: (index) =>
                              setState(() => currentIndex = index),
                        ),
                      ),
                    ),
                  ),
                ),

                // ===== 顶部控制栏 =====
                if (showControls)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 16,
                    right: 16,
                    child: Stack(
                      children: [
                        // 左侧：返回箭头 + 页码
                        Row(
                          children: [
                            AnimatedSlide(
                              offset: showControls ? Offset.zero : const Offset(-1.5, 0),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: AnimatedOpacity(
                                opacity: showControls ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(30),
                                    onTap: () => Navigator.pop(context, currentIndex),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_back_ios_new,
                                        color: Colors.white,
                                        size: 26,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 4,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "${currentIndex + 1}/${_currentImages.length}",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),

                        // 中间：标题
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentItem['name'],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (currentItem['w'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    "${currentItem['w']} x ${currentItem['h']} px",
                                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // 右侧：操作按钮
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _breatheController,
                                builder: (ctx, child) => Opacity(
                                  opacity: isPlaying ? _breatheController.value : 1.0,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: Icon(
                                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                      color: isPlaying ? Colors.tealAccent : Colors.white,
                                    ),
                                    iconSize: 28,
                                    onPressed: _toggleAutoPlay,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.drive_file_rename_outline, color: Colors.white),
                                iconSize: 24,
                                onPressed: _renameCurrentPhoto,
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                iconSize: 24,
                                onPressed: _deleteCurrentPhoto,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                if (!isMobile) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedSlide(
                      offset: showControls ? Offset.zero : const Offset(-1.2, 0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 30),
                            onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedSlide(
                      offset: showControls ? Offset.zero : const Offset(1.2, 0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 30),
                            onPressed: () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}