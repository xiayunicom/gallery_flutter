// lib/pages/gallery_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:badges/badges.dart' as badges;

import '../config.dart';
import '../services/task_manager.dart';
import '../widgets/tv_focusable_widget.dart';
import 'video_player_page.dart';
import 'photo_preview_page.dart';

// === 必须保留这个类定义，否则 main.dart 会报错 ===
class GalleryPage extends StatefulWidget {
  final String path;
  const GalleryPage({super.key, this.path = ""});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<dynamic> folders = [];
  List<dynamic> videos = [];
  List<dynamic> images = [];

  List<dynamic> get combinedMedia => [...videos, ...images];

  bool isLoading = true;
  String? errorMessage;
  final ScrollController _scrollController = ScrollController();

  bool isSelectionMode = false;
  Set<String> selectedPaths = {};
  int? _lastInteractionIndex;

  StreamSubscription? _refreshSubscription;

  bool _isDragSelecting = false;
  int? _dragStartIndex;
  int? _dragLastIndex;
  bool? _dragSelectTargetState;
  Set<String> _dragStartSelectedSnapshot = {};
  Timer? _autoScrollTimer;
  bool _suppressNextTap = false;

  double? _lastScreenWidth;

  static const double kSpacing = 1.0;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _refreshSubscription = TaskManager().refreshStream.listen((event) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _silentRefresh();
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    _scrollController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (isSelectionMode) {
      setState(() {
        isSelectionMode = false;
        selectedPaths.clear();
        _lastInteractionIndex = null;
      });
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final response = await Dio().get(
        '$serverUrl/api/ls',
        queryParameters: {'path': widget.path},
      );
      final rawList = response.data as List;
      if (mounted) {
        setState(() {
          folders = rawList.where((e) => e['type'] == 'folder').toList();
          videos = rawList.where((e) => e['type'] == 'video').toList();
          images = rawList.where((e) => e['type'] == 'image').toList();
          isLoading = false;
        });
        // 注意：移除了原本在这里的 FocusScope 请求，改为在各个 Grid 中使用 autofocus
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = "连接失败: $e";
        });
      }
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final response = await Dio().get(
        '$serverUrl/api/ls',
        queryParameters: {'path': widget.path},
      );
      final rawList = response.data as List;
      if (mounted) {
        setState(() {
          folders = rawList.where((e) => e['type'] == 'folder').toList();
          videos = rawList.where((e) => e['type'] == 'video').toList();
          images = rawList.where((e) => e['type'] == 'image').toList();
        });
      }
    } catch (_) {}
  }

  String _getThumbUrl(dynamic item) {
    final String? coverPath = item['cover_path'];
    if (coverPath == null || coverPath.isEmpty) return "";
    if (coverPath.startsWith('/api/')) {
      return "$serverUrl$coverPath";
    }
    return TaskManager().getImgUrl(coverPath);
  }

  // === 文件夹网格 (包含 autofocus 逻辑) ===
  Widget _buildFolderGrid(int crossAxisCount) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: kSpacing),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: kSpacing,
          crossAxisSpacing: kSpacing,
          childAspectRatio: 2 / 3,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = folders[index];
          final String? coverPath = item['cover_path'];
          final hasCover = coverPath != null && coverPath.isNotEmpty;
          final coverUrl = hasCover ? TaskManager().getImgUrl(coverPath) : "";

          // 【修复】只有第一个文件夹自动获焦
          bool shouldAutofocus = (index == 0);

          return TVFocusableWidget(
            key: ValueKey(item['path']),
            autofocus: shouldAutofocus,
            onTap: () {
              if (isSelectionMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Cannot open folder in selection mode"),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (context) => GalleryPage(path: item['path']),
                  ),
                );
              }
            },
            onLongPress: () => _showFolderMenu(item),
            onSecondaryTap: () => _showFolderMenu(item),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF252528),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheHeight: 400,
                        placeholder: (context, url) =>
                            Container(color: const Color(0xFF202023)),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.folder,
                            size: 40,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    if (!hasCover)
                      const Center(
                        child: Icon(
                          Icons.folder,
                          size: 40,
                          color: Colors.amber,
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 6,
                      right: 6,
                      child: Text(
                        item['name'],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }, childCount: folders.length),
      ),
    );
  }

  // === 视频网格 (包含 autofocus 逻辑) ===
  Widget _buildVideoGrid(int crossAxisCount) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: kSpacing,
          crossAxisSpacing: kSpacing,
          childAspectRatio: 16 / 9,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = videos[index];
          final path = item['path'];
          final fileUrl = TaskManager().getImgUrl(path);
          final currentGlobalIndex = index;
          final isSelected = selectedPaths.contains(path);
          final thumbUrl = _getThumbUrl(item);

          // 【修复】如果没有文件夹，且是第一个视频，则自动获焦
          bool shouldAutofocus = (index == 0 && folders.isEmpty);

          return TVFocusableWidget(
            key: ValueKey(path),
            autofocus: shouldAutofocus,
            isSelected: isSelected,
            onTap: () {
              final isShiftPressed =
                  HardwareKeyboard.instance.logicalKeysPressed.contains(
                    LogicalKeyboardKey.shiftLeft,
                  ) ||
                  HardwareKeyboard.instance.logicalKeysPressed.contains(
                    LogicalKeyboardKey.shiftRight,
                  );
              if (isSelectionMode || isShiftPressed) {
                _handleTapSelection(currentGlobalIndex, path);
              } else {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (context) => VideoPlayerPage(videoUrl: fileUrl),
                  ),
                );
              }
            },
            onSecondaryTap: () {
              if (!isSelectionMode) {
                setState(() {
                  isSelectionMode = true;
                  selectedPaths.add(path);
                  _lastInteractionIndex = currentGlobalIndex;
                });
              }
            },
            onLongPress: () {
              if (!isSelectionMode) {
                setState(() {
                  isSelectionMode = true;
                  selectedPaths.add(path);
                  _lastInteractionIndex = currentGlobalIndex;
                });
                HapticFeedback.mediumImpact();
              }
            },
            child: Hero(
              tag: isSelectionMode ? "no-hero-$path" : "video-$path",
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      decoration: const BoxDecoration(color: Color(0xFF202023)),
                      child: Stack(
                        alignment: Alignment.center,
                        fit: StackFit.expand,
                        children: [
                          if (thumbUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: thumbUrl,
                              fit: BoxFit.cover,
                              memCacheHeight: 400,
                              placeholder: (context, url) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF2C2C2E),
                                      Color(0xFF1C1C1E),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF2C2C2E),
                                      Color(0xFF1C1C1E),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.videocam_off,
                                    color: Colors.white12,
                                    size: 30,
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF2C2C2E),
                                    Color(0xFF1C1C1E),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black54],
                                stops: [0.6, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            right: -5,
                            bottom: -5,
                            child: Icon(
                              Icons.videocam,
                              size: 35,
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            right: 6,
                            child: Text(
                              item['name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    blurRadius: 2,
                                    color: Colors.black,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                "VIDEO",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isSelectionMode)
                    Container(
                      color: isSelected ? Colors.black45 : Colors.transparent,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? Colors.tealAccent
                                : Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: VideoResolutionTag(path: path),
                  ),
                ],
              ),
            ),
          );
        }, childCount: videos.length),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      isSelectionMode = !isSelectionMode;
      if (!isSelectionMode) {
        selectedPaths.clear();
        _lastInteractionIndex = null;
      }
    });
  }

  void _selectAll() {
    setState(() {
      selectedPaths = combinedMedia.map((e) => e['path'] as String).toSet();
      _lastInteractionIndex = combinedMedia.length - 1;
    });
  }

  void _handleTapSelection(int index, String path) {
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    setState(() {
      if (isShiftPressed) {
        isSelectionMode = true;
        if (_lastInteractionIndex != null) {
          final allMedia = combinedMedia;
          bool targetState = true;
          if (_lastInteractionIndex! < allMedia.length) {
            final lastPath = allMedia[_lastInteractionIndex!]['path'];
            targetState = selectedPaths.contains(lastPath);
          }
          _selectRange(_lastInteractionIndex!, index, targetState);
        } else {
          if (!selectedPaths.contains(path)) selectedPaths.add(path);
          _lastInteractionIndex = index;
        }
      } else if (isSelectionMode) {
        if (_suppressNextTap) {
          _suppressNextTap = false;
          return;
        }
        _toggleItemSelection(index, path);
      }
    });
  }

  void _selectRange(int start, int end, bool targetState) {
    int lower = min(start, end);
    int upper = max(start, end);
    final allMedia = combinedMedia;
    for (int i = lower; i <= upper; i++) {
      if (i < allMedia.length) {
        final p = allMedia[i]['path'];
        if (targetState) {
          selectedPaths.add(p);
        } else {
          selectedPaths.remove(p);
        }
      }
    }
  }

  void _toggleItemSelection(int index, String path) {
    if (selectedPaths.contains(path)) {
      selectedPaths.remove(path);
      if (selectedPaths.isEmpty) {
        isSelectionMode = false;
        _lastInteractionIndex = null;
      } else {
        _lastInteractionIndex = index;
      }
    } else {
      selectedPaths.add(path);
      _lastInteractionIndex = index;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!isSelectionMode) return;
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    if (isShiftPressed) return;

    final hitIndex = _hitTestImageIndex(event.position);
    if (hitIndex != null) {
      setState(() {
        _isDragSelecting = true;
        _dragStartIndex = hitIndex;
        _dragLastIndex = hitIndex;
        _dragStartSelectedSnapshot = Set.from(selectedPaths);

        final allMedia = combinedMedia;
        final path = allMedia[hitIndex]['path'];
        _dragSelectTargetState = !selectedPaths.contains(path);

        _updateSelectionState(hitIndex, _dragSelectTargetState!);
        _lastInteractionIndex = hitIndex;
        _suppressNextTap = true;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDragSelecting || _dragStartIndex == null) return;
    _handleAutoScroll(event.position);
    final hitIndex = _hitTestImageIndex(event.position);
    if (hitIndex != null && hitIndex != _dragLastIndex) {
      setState(() {
        _dragLastIndex = hitIndex;
        _lastInteractionIndex = hitIndex;
      });
      _applyRangeSelection(_dragStartIndex!, hitIndex);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDragSelecting) {
      setState(() {
        _isDragSelecting = false;
        _dragStartIndex = null;
        _dragLastIndex = null;
        _autoScrollTimer?.cancel();
      });
    }
  }

  int? _hitTestImageIndex(Offset position) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    final localPosition = box.globalToLocal(position);
    if (box.hitTest(result, position: localPosition)) {
      for (final hit in result.path) {
        final target = hit.target;
        if (target is RenderMetaData) {
          final data = target.metaData;
          if (data is int) return data;
        }
      }
    }
    return null;
  }

  void _applyRangeSelection(int start, int end) {
    final lower = min(start, end);
    final upper = max(start, end);
    final allMedia = combinedMedia;
    setState(() {
      selectedPaths = Set.from(_dragStartSelectedSnapshot);
      for (int i = lower; i <= upper; i++) {
        if (i < allMedia.length) {
          final path = allMedia[i]['path'];
          if (_dragSelectTargetState == true) {
            selectedPaths.add(path);
          } else {
            selectedPaths.remove(path);
          }
        }
      }
    });
  }

  void _updateSelectionState(int index, bool select) {
    final allMedia = combinedMedia;
    if (index < allMedia.length) {
      final path = allMedia[index]['path'];
      if (select) {
        selectedPaths.add(path);
      } else {
        selectedPaths.remove(path);
      }
    }
  }

  void _handleAutoScroll(Offset position) {
    const double scrollZoneHeight = 150.0;
    const double baseScrollSpeed = 10.0;

    final double screenHeight = MediaQuery.of(context).size.height;
    final double topPadding = MediaQuery.of(context).padding.top;
    final double dy = position.dy;

    double velocity = 0;

    if (dy < scrollZoneHeight + topPadding) {
      double ratio = (scrollZoneHeight + topPadding - dy) / scrollZoneHeight;
      ratio = ratio.clamp(0.0, 1.0);
      velocity = -baseScrollSpeed * (1 + ratio * 2);
    } else if (dy > screenHeight - scrollZoneHeight) {
      double ratio =
          (dy - (screenHeight - scrollZoneHeight)) / scrollZoneHeight;
      ratio = ratio.clamp(0.0, 1.0);
      velocity = baseScrollSpeed * (1 + ratio * 2);
    }

    if (velocity != 0) {
      if (_autoScrollTimer?.isActive ?? false) return;
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (
        timer,
      ) {
        if (!_isDragSelecting) {
          timer.cancel();
          return;
        }
        final newOffset = _scrollController.offset + velocity;
        if (newOffset < 0 ||
            newOffset > _scrollController.position.maxScrollExtent) {
          return;
        }
        _scrollController.jumpTo(newOffset);
      });
    } else {
      _autoScrollTimer?.cancel();
    }
  }

  bool _isPointerInContentArea(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final local = renderBox.globalToLocal(globalPosition);
    final size = renderBox.size;
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx < size.width &&
        local.dy < size.height;
  }

  Future<void> _rotateSelected(int angle) async {
    if (selectedPaths.isEmpty) return;
    try {
      final pathsToUpdate = List<String>.from(selectedPaths);
      await Dio().post(
        '$serverUrl/api/rotate',
        data: {'paths': jsonEncode(selectedPaths.toList()), 'angle': angle},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      TaskManager().bumpVersions(pathsToUpdate);
      setState(() {
        isSelectionMode = false;
        selectedPaths.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Rotation task started...")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteSelected() async {
    if (selectedPaths.isEmpty) return;
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text(
          "Delete Selected?",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "Delete ${selectedPaths.length} items permanently?",
          style: const TextStyle(color: Colors.white70),
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
      for (var path in selectedPaths) {
        await Dio().post(
          '$serverUrl/api/delete',
          data: FormData.fromMap({'path': path}),
        );
      }
      setState(() {
        isSelectionMode = false;
        selectedPaths.clear();
      });
      _silentRefresh();
    }
  }

  Future<void> _renameSelected() async {
    if (selectedPaths.length != 1) return;
    final String path = selectedPaths.first;
    final item = combinedMedia.firstWhere(
      (e) => e['path'] == path,
      orElse: () => null,
    );
    if (item == null) return;
    final String currentName = item['name'];
    TextEditingController controller = TextEditingController(text: currentName);

    String? newName = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Rename Item", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.white24),
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
          data: FormData.fromMap({'path': path, 'name': newName}),
        );
        setState(() {
          isSelectionMode = false;
          selectedPaths.clear();
        });
        _silentRefresh();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Rename failed: $e")));
      }
    }
  }

  void _showFolderMenu(dynamic folder) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              folder['name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(
                Icons.drive_file_rename_outline,
                color: Colors.blue,
              ),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _renameFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.image_aspect_ratio,
                color: Colors.green,
              ),
              title: const Text('Convert Content to WebP'),
              onTap: () {
                Navigator.pop(context);
                _convertWebP(folder);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.cleaning_services_outlined,
                color: Colors.orangeAccent,
              ),
              title: const Text('Clean Junk Files'),
              onTap: () {
                Navigator.pop(context);
                _cleanFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.sort_by_alpha,
                color: Colors.purpleAccent,
              ),
              title: const Text('Organize Sub-files'),
              onTap: () {
                Navigator.pop(context);
                _organizeFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Folder'),
              onTap: () {
                Navigator.pop(context);
                _deleteFolderDialog(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFolderDialog(dynamic folder) async {
    TextEditingController controller = TextEditingController(
      text: folder['name'],
    );
    String? newName = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Rename", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
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
    if (newName != null && newName.isNotEmpty && newName != folder['name']) {
      await Dio().post(
        '$serverUrl/api/rename',
        data: FormData.fromMap({'path': folder['path'], 'name': newName}),
      );
      _silentRefresh();
    }
  }

  Future<void> _deleteFolderDialog(dynamic folder) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text(
          "Delete Folder?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "This cannot be undone.",
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
      await Dio().post(
        '$serverUrl/api/delete',
        data: FormData.fromMap({'path': folder['path']}),
      );
      _silentRefresh();
    }
  }

  Future<void> _convertWebP(dynamic folder) async {
    await Dio().post(
      '$serverUrl/api/convert-webp',
      data: FormData.fromMap({'path': folder['path']}),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("WebP Conversion task started...")),
    );
  }

  Future<void> _cleanFolderDialog(dynamic folder) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text(
          "Clean Junk Files?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Folder: ${folder['name']}",
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will RECURSIVELY delete junk files (.url, .txt, .html, promotion images, etc.) inside this folder.",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This action cannot be undone.",
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Clean",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Dio().post(
          '$serverUrl/api/clean',
          data: FormData.fromMap({'path': folder['path']}),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Cleaning task started... Check task list for progress.",
            ),
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to start task: $e")));
      }
    }
  }

  Future<void> _organizeFolderDialog(dynamic folder) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text(
          "Organize Files?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Folder: ${folder['name']}",
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will recursively rename ALL files in subdirectories to a sequential number format (0001.jpg, 0002.mp4...).",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "It uses 'Natural Sort' (1.jpg, 2.jpg, 10.jpg).",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "WARNING: Original filenames will be lost!",
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Organize",
              style: TextStyle(color: Colors.purpleAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Dio().post(
          '$serverUrl/api/organize',
          data: FormData.fromMap({'path': folder['path']}),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Organizing task started..."),
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to start task: $e")));
      }
    }
  }

  void _showTaskList() {
    final now = DateTime.now();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TapRegion(
        onTapOutside: (_) {
          if (DateTime.now().difference(now) <
              const Duration(milliseconds: 500)) {
            return;
          }
          if (Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
          }
        },
        child: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: TaskManager().tasksNotifier,
          builder: (context, tasks, child) {
            return AlertDialog(
              backgroundColor: const Color(0xFF252528),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Active Tasks",
                    style: TextStyle(color: Colors.white),
                  ),
                  if (tasks.values.any(
                    (t) =>
                        t['type'] == 'done' ||
                        (t['current'] != null && t['current'] >= t['total']),
                  ))
                    TextButton(
                      onPressed: () {
                        TaskManager().clearDoneTasks();
                      },
                      child: const Text(
                        "Clear Done",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: tasks.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          "No active tasks.",
                          style: TextStyle(color: Colors.white54),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: tasks.entries.map((entry) {
                          final taskId = entry.key;
                          final task = entry.value;
                          double progress =
                              (task['current'] ?? 0) / (task['total'] ?? 1);
                          bool isDone =
                              task['type'] == 'done' || progress >= 1.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        task['message'] ?? 'Processing...',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      LinearProgressIndicator(
                                        value: isDone ? 1.0 : progress,
                                        backgroundColor: Colors.white10,
                                        minHeight: 4,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              isDone
                                                  ? Colors.green
                                                  : Colors.blue,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isDone
                                            ? 'COMPLETED'
                                            : "${(progress * 100).toInt()}% (${task['current']} / ${task['total']})",
                                        style: TextStyle(
                                          color: isDone
                                              ? Colors.green
                                              : Colors.white54,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isDone)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        TaskManager().removeTask(taskId);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    if (widget.path.isEmpty) {
      return const Text("Home", style: TextStyle(fontWeight: FontWeight.bold));
    }
    List<String> parts = widget.path
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();

    List<Widget> crumbs = [];
    crumbs.add(
      InkWell(
        onTap: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Icon(Icons.home, size: 18, color: Colors.grey),
        ),
      ),
    );

    for (int i = 0; i < parts.length; i++) {
      crumbs.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
      bool isLast = i == parts.length - 1;
      String folderName = parts[i];
      Widget textLabel = Text(
        folderName,
        style: TextStyle(
          color: isLast ? Colors.white : Colors.white70,
          fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
          fontSize: 16,
        ),
      );

      if (isLast) {
        crumbs.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: textLabel,
          ),
        );
      } else {
        crumbs.add(
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () {
              int popCount = parts.length - 1 - i;
              for (int k = 0; k < popCount; k++) {
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: textLabel,
            ),
          ),
        );
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: crumbs,
      ),
    );
  }

  double _calculateSectionTitleHeight() => 24 + 11 + 8 + 20;

  double _calculateFoldersSectionHeight(int crossAxisCount) {
    if (folders.isEmpty) return 0.0;
    const horizontalPadding = kSpacing * 2;
    const crossSpacing = kSpacing;
    const mainSpacing = kSpacing;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth - horizontalPadding;
    final itemWidth =
        (contentWidth - crossSpacing * (crossAxisCount - 1)) / crossAxisCount;
    final itemHeight = itemWidth * (3 / 2);
    final rowCount = (folders.length / crossAxisCount).ceil();
    final gridHeight = rowCount * itemHeight + (rowCount - 1) * mainSpacing;
    return gridHeight + _calculateSectionTitleHeight();
  }

  double _calculateVideosSectionHeight(int crossAxisCount) {
    if (videos.isEmpty) return 0.0;
    const double horizontalPadding = 8.0;
    const double spacing = 4.0;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double contentWidth = screenWidth - horizontalPadding;
    final double itemWidth =
        (contentWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final double itemHeight = itemWidth * 9 / 16;
    final int rowCount = (videos.length / crossAxisCount).ceil();
    double gridHeight = rowCount * itemHeight;
    if (rowCount > 1) {
      gridHeight += (rowCount - 1) * spacing;
    }
    return gridHeight + _calculateSectionTitleHeight();
  }

  void _scrollToImage(
    int targetIndex, {
    bool smartScroll = false,
    bool jump = false,
  }) {
    if (targetIndex < 0 || targetIndex >= images.length) return;
    if (!_scrollController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount;
    if (screenWidth < 600)
      crossAxisCount = 3;
    else if (screenWidth < 950)
      crossAxisCount = 4;
    else if (screenWidth < 1400)
      crossAxisCount = 6;
    else
      crossAxisCount = 8;

    double currentOffset = _calculateFoldersSectionHeight(crossAxisCount);

    if (videos.isNotEmpty) {
      currentOffset += _calculateVideosSectionHeight(crossAxisCount);
    }

    if (images.isNotEmpty) {
      currentOffset += _calculateSectionTitleHeight();
    }

    double targetRowHeight = 300.0;
    if (screenWidth >= 600 && screenWidth < 1400) targetRowHeight = 360.0;

    const double spacing = kSpacing;
    final double contentWidth = screenWidth - (spacing * 2);

    int rowStartImageIdx = 0;
    List<int> rowStartIndices = [0];
    List<double> rowHeights = [];

    double currentRowAspectSum = 0.0;

    for (int i = 0; i < images.length; i++) {
      final item = images[i];
      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0 || h <= 0) {
        w = 100;
        h = 100;
      }
      double aspectRatio = w / h;

      currentRowAspectSum += aspectRatio;
      double totalGapWidth = (i - rowStartImageIdx + 1 - 1) * spacing;
      double projectedHeight =
          (contentWidth - totalGapWidth) / currentRowAspectSum;
      bool isLast = i == images.length - 1;

      if (projectedHeight <= targetRowHeight || isLast) {
        double finalHeight = projectedHeight;
        if (isLast && projectedHeight > targetRowHeight)
          finalHeight = targetRowHeight;
        else if (projectedHeight > targetRowHeight * 1.5)
          finalHeight = targetRowHeight;

        rowHeights.add(finalHeight + spacing);

        if (!isLast) {
          rowStartImageIdx = i + 1;
          rowStartIndices.add(rowStartImageIdx);
          currentRowAspectSum = 0.0;
        }
      }
    }

    int targetRowIndex = 0;
    for (int r = 0; r < rowStartIndices.length; r++) {
      int start = rowStartIndices[r];
      int end = (r + 1 < rowStartIndices.length)
          ? rowStartIndices[r + 1]
          : images.length;
      if (targetIndex >= start && targetIndex < end) {
        targetRowIndex = r;
        break;
      }
    }

    double itemTop = currentOffset;
    for (int r = 0; r < targetRowIndex; r++) {
      itemTop += rowHeights[r];
    }

    double actualRowHeight = rowHeights[targetRowIndex] - spacing;
    double itemBottom = itemTop + actualRowHeight;

    if (jump) {
      final double viewportHeight =
          _scrollController.position.viewportDimension;
      double centerOffset =
          itemTop - (viewportHeight / 2) + (actualRowHeight / 2);
      _scrollController.jumpTo(
        centerOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
      return;
    }

    if (smartScroll) {
      final double viewportHeight =
          _scrollController.position.viewportDimension;
      final double viewTop = _scrollController.offset;
      final double viewBottom = viewTop + viewportHeight;

      if (itemTop >= viewTop - 1.0 && itemBottom <= viewBottom + 1.0) {
        return;
      }

      bool partiallyVisible = (itemTop < viewBottom && itemBottom > viewTop);

      if (partiallyVisible) {
        double targetOffset = viewTop;
        if (itemTop < viewTop) {
          targetOffset = itemTop - spacing;
        } else if (itemBottom > viewBottom) {
          targetOffset = itemBottom - viewportHeight + spacing;
          if (targetOffset > itemTop) targetOffset = itemTop;
        }
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }

      double centerOffset =
          itemTop - (viewportHeight / 2) + (actualRowHeight / 2);
      _scrollController.jumpTo(
        centerOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    } else {
      _scrollController.animateTo(
        itemTop.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _openPreview(int initialIndex) async {
    _lastInteractionIndex = initialIndex;
    final result = await Navigator.push<int>(
      context,
      CupertinoPageRoute(
        builder: (context) =>
            PhotoPreviewPage(images: images, initialIndex: initialIndex),
      ),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    await _silentRefresh();

    if (result != null && result >= 0 && result < images.length) {
      setState(() {
        _lastInteractionIndex = result;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToImage(result, smartScroll: true);
      });
    }
  }

  // === 核心逻辑: 计算图片行布局 (包含 autofocus 逻辑) ===
  List<Widget> _computeJustifiedRows(
    double screenWidth,
    List<dynamic> items, {
    required int globalStartIndex,
  }) {
    if (items.isEmpty) return [];

    double targetRowHeight = 300.0;
    if (screenWidth >= 600 && screenWidth < 1400) {
      targetRowHeight = 360.0;
    }

    const double spacing = kSpacing;
    final double contentWidth = screenWidth - (spacing * 2);
    List<Widget> rows = [];
    List<dynamic> currentRowItems = [];

    int currentRowStartLocalIndex = 0;
    double currentRowAspectRatioSum = 0.0;
    double? previousRowFinalHeight;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0 || h <= 0) {
        w = 100;
        h = 100;
      }
      double aspectRatio = w / h;

      currentRowItems.add(item);
      currentRowAspectRatioSum += aspectRatio;

      double totalGapWidth = (currentRowItems.length - 1) * spacing;
      double projectedHeight =
          (contentWidth - totalGapWidth) / currentRowAspectRatioSum;

      if (projectedHeight <= targetRowHeight || i == items.length - 1) {
        bool isLastRow = i == items.length - 1;
        double finalHeight = projectedHeight;

        if (isLastRow) {
          double referenceHeight = previousRowFinalHeight ?? targetRowHeight;
          if (projectedHeight > referenceHeight) {
            finalHeight = referenceHeight;
          } else {
            finalHeight = projectedHeight;
          }
        } else {
          if (finalHeight > targetRowHeight * 1.5) {
            finalHeight = targetRowHeight;
          }
        }

        rows.add(
          _buildJustifiedRow(
            currentRowItems,
            finalHeight,
            spacing,
            isLastRow: isLastRow,
            localStartIndex: currentRowStartLocalIndex,
            globalStartIndex: globalStartIndex,
          ),
        );

        previousRowFinalHeight = finalHeight;
        currentRowItems = [];
        currentRowAspectRatioSum = 0.0;
        currentRowStartLocalIndex = i + 1;
      }
    }
    return rows;
  }

  // === 核心逻辑: 构建每一行图片 (包含 autofocus 逻辑) ===
  Widget _buildJustifiedRow(
    List<dynamic> rowItems,
    double height,
    double spacing, {
    required bool isLastRow,
    required int localStartIndex,
    required int globalStartIndex,
  }) {
    List<Widget> children = [];
    for (int i = 0; i < rowItems.length; i++) {
      final item = rowItems[i];
      final path = item['path'];
      final fileUrl = TaskManager().getImgUrl(path);
      final isVideo = item['type'] == 'video';
      final thumbUrl = _getThumbUrl(item);

      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0) w = 100;
      if (h <= 0) h = 100;

      double itemWidth = height * (w / h);
      int currentLocalIndex = localStartIndex + i;
      int currentGlobalIndex = globalStartIndex + currentLocalIndex;
      bool isSelected = selectedPaths.contains(path);

      // 【修复】只有当没有文件夹且没有视频，且是第一张图时，自动获焦
      bool shouldAutofocus =
          (currentLocalIndex == 0) && folders.isEmpty && videos.isEmpty;

      children.add(
        MetaData(
          metaData: currentGlobalIndex,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: itemWidth,
            height: height,
            child: TVFocusableWidget(
              autofocus: shouldAutofocus,
              isSelected: isSelected,
              key: ValueKey(path),
              onTap: () {
                final isShiftPressed =
                    HardwareKeyboard.instance.logicalKeysPressed.contains(
                      LogicalKeyboardKey.shiftLeft,
                    ) ||
                    HardwareKeyboard.instance.logicalKeysPressed.contains(
                      LogicalKeyboardKey.shiftRight,
                    );
                if (isSelectionMode || isShiftPressed) {
                  _handleTapSelection(currentGlobalIndex, path);
                } else {
                  if (isVideo) {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (context) =>
                            VideoPlayerPage(videoUrl: fileUrl),
                      ),
                    );
                  } else {
                    int imageIndex = currentLocalIndex;
                    setState(() {
                      _lastInteractionIndex = currentGlobalIndex;
                    });
                    _openPreview(imageIndex);
                  }
                }
              },
              onSecondaryTap: () {
                if (!isSelectionMode) {
                  setState(() {
                    isSelectionMode = true;
                    selectedPaths.add(path);
                    _lastInteractionIndex = currentGlobalIndex;
                  });
                }
              },
              onLongPress: () {
                if (!isSelectionMode) {
                  setState(() {
                    isSelectionMode = true;
                    selectedPaths.add(path);
                    _lastInteractionIndex = currentGlobalIndex;
                  });
                  HapticFeedback.mediumImpact();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      color: const Color(0xFF202023),
                      child: isVideo
                          ? Stack(
                              alignment: Alignment.center,
                              fit: StackFit.expand,
                              children: [
                                if (thumbUrl.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: thumbUrl,
                                    fit: BoxFit.cover,
                                    memCacheHeight: 400,
                                    placeholder: (context, url) => Container(
                                      color: const Color(0xFF202023),
                                    ),
                                  )
                                else
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF2C2C2E),
                                          Color(0xFF1C1C1E),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                  ),
                                Container(color: Colors.black26),
                                const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ],
                            )
                          : CachedNetworkImage(
                              imageUrl: fileUrl,
                              memCacheHeight: 1000,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: const Color(0xFF202023)),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            ),
                    ),
                  ),
                  if (isSelectionMode)
                    Container(
                      color: isSelected ? Colors.black45 : Colors.transparent,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? Colors.tealAccent
                                : Colors.white70,
                            size: 28,
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
      if (i < rowItems.length - 1) children.add(SizedBox(width: spacing));
    }

    return Container(
      margin: EdgeInsets.only(bottom: spacing),
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _buildSectionTitle(String title) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    ),
  );

  Widget _buildBottomBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    if (_lastScreenWidth != null &&
        (screenWidth - _lastScreenWidth!).abs() > 1.0) {
      if (_lastInteractionIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToImage(_lastInteractionIndex!, jump: true);
        });
      }
    }
    _lastScreenWidth = screenWidth;

    int crossAxisCount;
    if (screenWidth < 600)
      crossAxisCount = 3;
    else if (screenWidth < 950)
      crossAxisCount = 4;
    else if (screenWidth < 1400)
      crossAxisCount = 6;
    else
      crossAxisCount = 8;

    final List<Widget> imageRows = _computeJustifiedRows(
      screenWidth,
      images,
      globalStartIndex: videos.length,
    );

    return Scaffold(
      appBar: AppBar(
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : (Navigator.canPop(context)
                  ? const BackButton()
                  : const Icon(Icons.menu, color: Colors.transparent)),
        title: isSelectionMode
            ? Text("${selectedPaths.length} Selected")
            : _buildBreadcrumbs(),
        actions: [
          ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: TaskManager().tasksNotifier,
            builder: (context, tasks, child) {
              return IconButton(
                onPressed: _showTaskList,
                icon: tasks.isEmpty
                    ? const Icon(Icons.assignment_outlined)
                    : badges.Badge(
                        badgeContent: Text(
                          '${tasks.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                        child: const Icon(Icons.assignment_outlined),
                      ),
              );
            },
          ),
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) =>
            _isPointerInContentArea(e.position) ? _onPointerDown(e) : null,
        onPointerMove: (e) =>
            _isPointerInContentArea(e.position) ? _onPointerMove(e) : null,
        onPointerUp: (e) =>
            _isPointerInContentArea(e.position) ? _onPointerUp(e) : null,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : errorMessage != null
            ? Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : CustomScrollView(
                controller: _scrollController,
                cacheExtent: 2000.0,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  if (folders.isNotEmpty) _buildSectionTitle("FOLDERS"),
                  if (folders.isNotEmpty) _buildFolderGrid(crossAxisCount),
                  if (videos.isNotEmpty)
                    _buildSectionTitle("VIDEOS (${videos.length})"),
                  if (videos.isNotEmpty) _buildVideoGrid(crossAxisCount),
                  if (images.isNotEmpty)
                    _buildSectionTitle("IMAGES (${images.length})"),
                  if (images.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: kSpacing),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => imageRows[index],
                          childCount: imageRows.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
      ),
      bottomNavigationBar: isSelectionMode
          ? Container(
              color: const Color(0xFF18181B),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBottomBtn(
                        Icons.rotate_left,
                        "Left -90°",
                        () => _rotateSelected(-90),
                      ),
                      _buildBottomBtn(
                        Icons.rotate_right,
                        "Right +90°",
                        () => _rotateSelected(90),
                      ),
                      if (selectedPaths.length == 1)
                        _buildBottomBtn(
                          Icons.drive_file_rename_outline,
                          "Rename",
                          _renameSelected,
                          color: Colors.blueAccent,
                        ),
                      _buildBottomBtn(
                        Icons.delete,
                        "Delete",
                        _deleteSelected,
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class VideoResolutionTag extends StatefulWidget {
  final String path;
  const VideoResolutionTag({super.key, required this.path});

  @override
  State<VideoResolutionTag> createState() => _VideoResolutionTagState();
}

class _VideoResolutionTagState extends State<VideoResolutionTag> {
  String text = "VIDEO";
  static final Map<String, String> _cache = {};

  @override
  void initState() {
    super.initState();
    _fetchResolution();
  }

  Future<void> _fetchResolution() async {
    if (_cache.containsKey(widget.path)) {
      if (mounted) setState(() => text = _cache[widget.path]!);
      return;
    }
    try {
      final response = await Dio().get(
        '$serverUrl/api/video-info',
        queryParameters: {'path': widget.path},
      );
      if (mounted && response.data != null) {
        final w = response.data['w'];
        final h = response.data['h'];
        if (w != null && h != null && w > 0 && h > 0) {
          final newText = "$w x $h";
          _cache[widget.path] = newText;
          setState(() {
            text = newText;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: "monospace",
        ),
      ),
    );
  }
}
