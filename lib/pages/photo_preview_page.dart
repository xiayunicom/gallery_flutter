// lib/pages/photo_preview_page.dart
import 'dart:async';
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
  bool showControls = false;
  bool isPlaying = false;
  Timer? _autoPlayTimer;
  late AnimationController _breatheController;
  Offset _dragOffset = Offset.zero;
  double _dragScale = 1.0;
  AnimationController? _resetController;
  Animation<Offset>? _offsetAnimation;
  Animation<double>? _scaleAnimation;
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
    super.dispose();
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
    if (_isZoomed) return;
    setState(() {
      double dy = _dragOffset.dy + details.delta.dy;
      double dx = _dragOffset.dx + details.delta.dx;
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
          if (currentIndex >= _currentImages.length)
            currentIndex = _currentImages.length - 1;
        });
        if (_currentImages.isEmpty)
          Navigator.pop(context, -1);
        else if (wasPlaying)
          _toggleAutoPlay();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
      }
    } else {
      if (wasPlaying) _toggleAutoPlay();
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape)
        Navigator.pop(context, currentIndex);
      else if (event.logicalKey == LogicalKeyboardKey.space)
        _toggleAutoPlay();
      else if (event.logicalKey == LogicalKeyboardKey.arrowRight)
        _pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      else if (event.logicalKey == LogicalKeyboardKey.arrowLeft)
        _pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      else if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace)
        _deleteCurrentPhoto();
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
          body: Stack(
            children: [
              Container(color: Colors.black.withOpacity(bgOpacity)),
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleControls,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  child: Transform.translate(
                    offset: _dragOffset,
                    child: Transform.scale(
                      scale: _dragScale,
                      child: PhotoViewGallery.builder(
                        scrollPhysics: const BouncingScrollPhysics(),
                        scaleStateChangedCallback: (PhotoViewScaleState state) {
                          setState(() {
                            _isZoomed = state != PhotoViewScaleState.initial;
                          });
                        },
                        builder: (BuildContext context, int index) {
                          final item = _currentImages[index];
                          final imgUrl = TaskManager().getImgUrl(item['path']);
                          return PhotoViewGalleryPageOptions(
                            imageProvider: CachedNetworkImageProvider(imgUrl),
                            initialScale: PhotoViewComputedScale.contained,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 3.0,
                            heroAttributes: PhotoViewHeroAttributes(
                              tag: imgUrl,
                            ),
                            onTapUp: (context, details, value) {
                              _toggleControls();
                            },
                          );
                        },
                        itemCount: _currentImages.length,
                        loadingBuilder: (context, event) => const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white24,
                          ),
                        ),
                        pageController: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            currentIndex = index;
                          });
                        },
                        backgroundDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: !showControls,
                child: Opacity(
                  opacity: bgOpacity,
                  child: Stack(
                    children: [
                      // Top Bar
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOutQuart,
                        top: showControls ? 0 : -20,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          opacity: showControls ? 1.0 : 0.0,
                          child: Container(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 10,
                              top: MediaQuery.of(context).padding.top + 10,
                            ),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black87, Colors.transparent],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      "${currentIndex + 1}/${_currentImages.length}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        currentItem['name'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (currentItem['w'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            "${currentItem['w']} x ${currentItem['h']} px",
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _breatheController,
                                        builder: (ctx, child) => Opacity(
                                          opacity: isPlaying
                                              ? _breatheController.value
                                              : 1.0,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              isPlaying
                                                  ? Icons.pause_circle_filled
                                                  : Icons.play_circle_filled,
                                              color: isPlaying
                                                  ? Colors.tealAccent
                                                  : Colors.white,
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
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                        ),
                                        iconSize: 24,
                                        onPressed: _deleteCurrentPhoto,
                                      ),
                                      const SizedBox(width: 16),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
                                        iconSize: 28,
                                        onPressed: () => Navigator.pop(
                                          context,
                                          currentIndex,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!isMobile) ...[
                        // 左箭头
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedSlide(
                            offset: showControls
                                ? Offset.zero
                                : const Offset(-1.2, 0),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: showControls ? 1.0 : 0.0,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back_ios,
                                    color: Colors.white24,
                                    size: 30,
                                  ),
                                  onPressed: () => _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.ease,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 右箭头
                        Align(
                          alignment: Alignment.centerRight,
                          child: AnimatedSlide(
                            offset: showControls
                                ? Offset.zero
                                : const Offset(1.2, 0),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: showControls ? 1.0 : 0.0,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white24,
                                    size: 30,
                                  ),
                                  onPressed: () => _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.ease,
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}
