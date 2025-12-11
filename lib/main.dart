import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter/gestures.dart';
import 'package:video_player/video_player.dart';

// ==========================================
// CONFIG: 你的 Mac/PC 局域网 IP
// ==========================================
const String serverIp = "192.168.3.22";
const String serverPort = "8899";
const String serverUrl = "http://$serverIp:$serverPort";

// ==========================================
// 全局任务管理器 & 缓存控制器
// ==========================================
class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  final ValueNotifier<Map<String, dynamic>> tasksNotifier = ValueNotifier({});
  final StreamController<String> _refreshEventController = StreamController.broadcast();
  Stream<String> get refreshStream => _refreshEventController.stream;

  final Map<String, int> _fileVersions = {};

  void init() {
    print("Initializing Global SSE Connection...");
    try {
      SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: '$serverUrl/api/events',
        header: {},
      ).listen((event) {
        if (event.data != null && event.data!.isNotEmpty) {
          try {
            final data = jsonDecode(event.data!);
            final taskId = data['taskId'];
            final type = data['type'];

            final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);

            bool isActuallyDone = type == 'done';
            if (!isActuallyDone && data['current'] != null && data['total'] != null) {
              if (data['current'] >= data['total'] && data['total'] > 0) {
                isActuallyDone = true;
                data['type'] = 'done';
              }
            }

            if (isActuallyDone) {
              if (data['message'].toString().contains('Rotat') ||
                  data['message'].toString().contains('Convert')) {
                _refreshEventController.add('refresh');
              }
            }

            currentTasks[taskId] = data;
            tasksNotifier.value = currentTasks;
          } catch (e) {
            print("SSE Parse Error: $e");
          }
        }
      });
    } catch (e) {
      print("SSE Connection Error: $e");
    }
  }

  String getImgUrl(String path) {
    final encodedPath = Uri.encodeComponent(path);
    final version = _fileVersions[path] ?? 0;
    return "$serverUrl/file/$encodedPath?v=$version";
  }

  void bumpVersions(List<String> paths) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var path in paths) {
      _fileVersions[path] = now;
    }
  }

  void removeTask(String taskId) {
    final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);
    currentTasks.remove(taskId);
    tasksNotifier.value = currentTasks;
  }

  void clearDoneTasks() {
    final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);
    currentTasks.removeWhere((key, value) {
      bool isDone = value['type'] == 'done';
      if (!isDone && value['current'] != null && value['total'] != null) {
        if (value['current'] >= value['total']) isDone = true;
      }
      return isDone;
    });
    tasksNotifier.value = currentTasks;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 扩大全局图片缓存，防止大列表回滚时重新加载
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024; 
  PaintingBinding.instance.imageCache.maximumSize = 3000;

  TaskManager().init();
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gallery Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF18181B),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF202023),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const GalleryPage(path: ""),
    );
  }
}

class GalleryPage extends StatefulWidget {
  final String path;
  const GalleryPage({super.key, this.path = ""});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<dynamic> folders = [];
  List<dynamic> images = [];
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
          images = rawList.where((e) => e['type'] == 'image' || e['type'] == 'video').toList();
          isLoading = false;
        });
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
          images = rawList.where((e) => e['type'] == 'image' || e['type'] == 'video').toList();
        });
      }
    } catch (_) {}
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
      selectedPaths = images.map((e) => e['path'] as String).toSet();
      _lastInteractionIndex = images.length - 1;
    });
  }

  void _handleTapSelection(int index, String path) {
    final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

    setState(() {
      if (isShiftPressed) {
        isSelectionMode = true;
        if (_lastInteractionIndex != null) {
          _selectRange(_lastInteractionIndex!, index);
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

  void _selectRange(int start, int end) {
    int lower = min(start, end);
    int upper = max(start, end);
    for (int i = lower; i <= upper; i++) {
      selectedPaths.add(images[i]['path']);
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
    final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    if (isShiftPressed) return;

    final hitIndex = _hitTestImageIndex(event.position);
    if (hitIndex != null) {
      setState(() {
        _isDragSelecting = true;
        _dragStartIndex = hitIndex;
        _dragLastIndex = hitIndex;
        _dragStartSelectedSnapshot = Set.from(selectedPaths);
        
        final path = images[hitIndex]['path'];
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
    setState(() {
      selectedPaths = Set.from(_dragStartSelectedSnapshot);
      for (int i = lower; i <= upper; i++) {
        final path = images[i]['path'];
        if (_dragSelectTargetState == true) {
          selectedPaths.add(path);
        } else {
          selectedPaths.remove(path);
        }
      }
    });
  }

  void _updateSelectionState(int index, bool select) {
    final path = images[index]['path'];
    if (select) selectedPaths.add(path);
    else selectedPaths.remove(path);
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
      double ratio = (dy - (screenHeight - scrollZoneHeight)) / scrollZoneHeight;
      ratio = ratio.clamp(0.0, 1.0);
      velocity = baseScrollSpeed * (1 + ratio * 2);
    }

    if (velocity != 0) {
      if (_autoScrollTimer?.isActive ?? false) return;
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!_isDragSelecting) {
          timer.cancel();
          return;
        }
        final newOffset = _scrollController.offset + velocity;
        if (newOffset < 0 || newOffset > _scrollController.position.maxScrollExtent) return;
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
    return local.dx >= 0 && local.dy >= 0 && local.dx < size.width && local.dy < size.height;
  }

  // === 批量操作 ===
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rotation task started...")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteSelected() async {
    if (selectedPaths.isEmpty) return;
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Delete Selected?", style: TextStyle(color: Colors.white)),
        content: Text("Delete ${selectedPaths.length} items permanently?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      for (var path in selectedPaths) {
        await Dio().post('$serverUrl/api/delete', data: FormData.fromMap({'path': path}));
      }
      setState(() {
        isSelectionMode = false;
        selectedPaths.clear();
      });
      _silentRefresh();
    }
  }

  // === 文件夹操作 ===
  void _showFolderMenu(dynamic folder) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(folder['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(color: Colors.white24),
            ListTile(leading: const Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: const Text('Rename'), onTap: () { Navigator.pop(context); _renameFolderDialog(folder); }),
            ListTile(leading: const Icon(Icons.image_aspect_ratio, color: Colors.green), title: const Text('Convert Content to WebP'), onTap: () { Navigator.pop(context); _convertWebP(folder); }),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete Folder'), onTap: () { Navigator.pop(context); _deleteFolderDialog(folder); }),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFolderDialog(dynamic folder) async {
    TextEditingController controller = TextEditingController(text: folder['name']);
    String? newName = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Rename", style: TextStyle(color: Colors.white)),
        content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Rename")),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != folder['name']) {
      await Dio().post('$serverUrl/api/rename', data: FormData.fromMap({'path': folder['path'], 'name': newName}));
      _silentRefresh();
    }
  }

  Future<void> _deleteFolderDialog(dynamic folder) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252528),
        title: const Text("Delete Folder?", style: TextStyle(color: Colors.white)),
        content: const Text("This cannot be undone.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await Dio().post('$serverUrl/api/delete', data: FormData.fromMap({'path': folder['path']}));
      _silentRefresh();
    }
  }

  Future<void> _convertWebP(dynamic folder) async {
    await Dio().post('$serverUrl/api/convert-webp', data: FormData.fromMap({'path': folder['path']}));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("WebP Conversion task started...")));
  }

  void _showTaskList() {
    final now = DateTime.now();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TapRegion(
        onTapOutside: (_) {
          if (DateTime.now().difference(now) < const Duration(milliseconds: 500)) {
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
                  const Text("Active Tasks", style: TextStyle(color: Colors.white)),
                  if (tasks.values.any((t) => t['type'] == 'done' || (t['current'] != null && t['current'] >= t['total'])))
                    TextButton(onPressed: () { TaskManager().clearDoneTasks(); }, child: const Text("Clear Done", style: TextStyle(fontSize: 12))),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: tasks.isEmpty
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text("No active tasks.", style: TextStyle(color: Colors.white54), textAlign: TextAlign.center))
                    : ListView(
                        shrinkWrap: true,
                        children: tasks.entries.map((entry) {
                          final taskId = entry.key;
                          final task = entry.value;
                          double progress = (task['current'] ?? 0) / (task['total'] ?? 1);
                          bool isDone = task['type'] == 'done' || progress >= 1.0;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(task['message'] ?? 'Processing...', style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(value: isDone ? 1.0 : progress, backgroundColor: Colors.white10, minHeight: 4, valueColor: AlwaysStoppedAnimation<Color>(isDone ? Colors.green : Colors.blue)),
                                  const SizedBox(height: 4),
                                  Text(isDone ? 'COMPLETED' : "${(progress * 100).toInt()}%", style: TextStyle(color: isDone ? Colors.green : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                                ])),
                                if (isDone) Padding(padding: const EdgeInsets.only(left: 8), child: IconButton(icon: const Icon(Icons.clear, color: Colors.white70, size: 20), onPressed: () { TaskManager().removeTask(taskId); }, tooltip: "Clear")),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    if (widget.path.isEmpty) return const Text("Home", style: TextStyle(fontWeight: FontWeight.bold));
    List<String> parts = widget.path.split('/').where((p) => p.isNotEmpty).toList();
    List<Widget> crumbs = [];
    crumbs.add(InkWell(onTap: () { Navigator.of(context).popUntil((route) => route.isFirst); }, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 2.0), child: Icon(Icons.home, size: 18, color: Colors.grey))));
    for (int i = 0; i < parts.length; i++) {
      crumbs.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
      bool isLast = i == parts.length - 1;
      crumbs.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8), child: Text(parts[i], style: TextStyle(color: isLast ? Colors.white : Colors.white70, fontWeight: isLast ? FontWeight.bold : FontWeight.normal, fontSize: 16))));
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: crumbs));
  }

  double _calculateSectionTitleHeight() {
    return 24 + 11 + 8 + 20; 
  }

  double _calculateFoldersSectionHeight(int crossAxisCount) {
    if (folders.isEmpty) return 0.0;
    const horizontalPadding = 8.0; 
    const crossSpacing = 4.0;
    const mainSpacing = 4.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth - horizontalPadding;
    final itemWidth = (contentWidth - crossSpacing * (crossAxisCount - 1)) / crossAxisCount;
    final itemHeight = itemWidth * (3 / 2); 
    final rowCount = (folders.length / crossAxisCount).ceil();
    final gridHeight = rowCount * itemHeight + (rowCount - 1) * mainSpacing;
    return gridHeight + _calculateSectionTitleHeight();
  }

  double _calculateImagesSectionTitleHeight() {
    if (images.isEmpty) return 0.0;
    return _calculateSectionTitleHeight();
  }

  void _scrollToImage(int targetIndex, {bool smartScroll = false}) {
    if (targetIndex < 0 || targetIndex >= images.length) return;
    if (!_scrollController.hasClients) return; 

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount;
    if (screenWidth < 600) crossAxisCount = 3;
    else if (screenWidth < 950) crossAxisCount = 4;
    else if (screenWidth < 1400) crossAxisCount = 6;
    else crossAxisCount = 8;

    double currentOffset = _calculateFoldersSectionHeight(crossAxisCount) + _calculateImagesSectionTitleHeight();

    double targetRowHeight = 300.0;
    if (screenWidth >= 600 && screenWidth < 1400) {
      targetRowHeight = 360.0;
    }
    const double spacing = 4.0;
    final double contentWidth = screenWidth - (spacing * 2);

    int rowStartImageIdx = 0;
    List<int> rowStartIndices = [0];
    List<double> rowHeights = []; 

    double currentRowAspectSum = 0.0;
    
    for (int i = 0; i < images.length; i++) {
      final item = images[i];
      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0 || h <= 0) { w = 100; h = 100; }
      double aspectRatio = w / h;

      currentRowAspectSum += aspectRatio;
      double totalGapWidth = (i - rowStartImageIdx + 1 - 1) * spacing;
      double projectedHeight = (contentWidth - totalGapWidth) / currentRowAspectSum;
      bool isLast = i == images.length - 1;

      if (projectedHeight <= targetRowHeight || isLast) {
        double finalHeight = projectedHeight;
        if (isLast && projectedHeight > targetRowHeight) {
          finalHeight = targetRowHeight;
        } else if (projectedHeight > targetRowHeight * 1.5) {
          finalHeight = targetRowHeight;
        }
        
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
      int end = (r + 1 < rowStartIndices.length) ? rowStartIndices[r + 1] : images.length;
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

    if (smartScroll) {
      final double viewportHeight = _scrollController.position.viewportDimension;
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

      double centerOffset = itemTop - (viewportHeight / 2) + (actualRowHeight / 2);
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
    final result = await Navigator.push<int>(
      context,
      CupertinoPageRoute(
        builder: (context) => PhotoPreviewPage(images: images, initialIndex: initialIndex),
      ),
    );
    
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    await _silentRefresh();
    
    if (result != null && result >= 0 && result < images.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToImage(result, smartScroll: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    int folderCrossAxisCount;
    if (screenWidth < 600) folderCrossAxisCount = 3;
    else if (screenWidth < 950) folderCrossAxisCount = 4;
    else if (screenWidth < 1400) folderCrossAxisCount = 6;
    else folderCrossAxisCount = 8;

    final List<Widget> justifiedRows = _computeJustifiedRows(screenWidth);

    return Scaffold(
      appBar: AppBar(
        leading: isSelectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _toggleSelectionMode)
            : (Navigator.canPop(context) ? const BackButton() : const Icon(Icons.menu, color: Colors.transparent)),
        title: isSelectionMode ? Text("${selectedPaths.length} Selected") : _buildBreadcrumbs(),
        actions: [
          ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: TaskManager().tasksNotifier,
            builder: (context, tasks, child) {
              return IconButton(
                onPressed: _showTaskList,
                icon: tasks.isEmpty
                    ? const Icon(Icons.assignment_outlined)
                    : badges.Badge(
                        badgeContent: Text('${tasks.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10)),
                        child: const Icon(Icons.assignment_outlined),
                      ),
              );
            },
          ),
          if (isSelectionMode) IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll)
          else IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _isPointerInContentArea(e.position) ? _onPointerDown(e) : null,
        onPointerMove: (e) => _isPointerInContentArea(e.position) ? _onPointerMove(e) : null,
        onPointerUp: (e) => _isPointerInContentArea(e.position) ? _onPointerUp(e) : null,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : errorMessage != null
                ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
                : CustomScrollView(
                    controller: _scrollController,
                    cacheExtent: 2000.0, // 增大预加载范围，减少滑动白块
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      if (folders.isNotEmpty) _buildSectionTitle("FOLDERS"),
                      if (folders.isNotEmpty) _buildFolderGrid(folderCrossAxisCount),
                      if (images.isNotEmpty) _buildSectionTitle("MEDIA (${images.length})"),
                      if (images.isNotEmpty) SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 4), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => justifiedRows[index], childCount: justifiedRows.length))),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  ),
      ),
      bottomNavigationBar: isSelectionMode
          ? Container(
              color: const Color(0xFF18181B),
              child: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildBottomBtn(Icons.rotate_left, "Left -90°", () => _rotateSelected(-90)), _buildBottomBtn(Icons.rotate_right, "Right +90°", () => _rotateSelected(90)), _buildBottomBtn(Icons.delete, "Delete", _deleteSelected, color: Colors.redAccent)]))),
            )
          : null,
    );
  }

  Widget _buildBottomBtn(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) {
    return InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color), const SizedBox(height: 4), Text(label, style: TextStyle(color: color, fontSize: 12))])));
  }

  List<Widget> _computeJustifiedRows(double screenWidth) {
    if (images.isEmpty) return [];
    
    double targetRowHeight = 300.0;
    if (screenWidth >= 600 && screenWidth < 1400) {
      targetRowHeight = 360.0; 
    }
    
    const double spacing = 4.0;
    final double contentWidth = screenWidth - (spacing * 2);
    List<Widget> rows = [];
    List<dynamic> currentRowImages = [];
    double currentRowAspectRatioSum = 0.0;
    
    for (int i = 0; i < images.length; i++) {
      final item = images[i];
      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0 || h <= 0) { w = 100; h = 100; }
      double aspectRatio = w / h; 

      currentRowImages.add(item);
      currentRowAspectRatioSum += aspectRatio;

      double totalGapWidth = (currentRowImages.length - 1) * spacing;
      
      double projectedHeight = (contentWidth - totalGapWidth) / currentRowAspectRatioSum;

      if (projectedHeight <= targetRowHeight || i == images.length - 1) {
        bool isLastRow = i == images.length - 1;
        
        if (isLastRow && projectedHeight > targetRowHeight) {
          projectedHeight = targetRowHeight;
        } 
        else if (projectedHeight > targetRowHeight * 1.5) {
           projectedHeight = targetRowHeight;
        }

        rows.add(_buildJustifiedRow(currentRowImages, projectedHeight, spacing, isLastRow: isLastRow));
        currentRowImages = [];
        currentRowAspectRatioSum = 0.0;
      }
    }
    return rows;
  }

  Widget _buildJustifiedRow(List<dynamic> rowItems, double height, double spacing, {required bool isLastRow}) {
    List<Widget> children = [];
    for (int i = 0; i < rowItems.length; i++) {
      final item = rowItems[i];
      final path = item['path'];
      final fileUrl = TaskManager().getImgUrl(path);
      final isVideo = item['type'] == 'video';
      
      double w = (item['w'] as num?)?.toDouble() ?? 100;
      double h = (item['h'] as num?)?.toDouble() ?? 100;
      if (w <= 0) w = 100;
      if (h <= 0) h = 100;
      
      double itemWidth = height * (w / h);
      
      int globalIndex = images.indexOf(item);
      bool isSelected = selectedPaths.contains(path);

      children.add(
        MetaData(
          metaData: globalIndex,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: itemWidth,
            height: height,
            child: GestureDetector(
              onTap: () {
                final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                if (isSelectionMode || isShiftPressed) {
                  _handleTapSelection(globalIndex, path);
                } else {
                  if (isVideo) {
                    // === 视频逻辑：直接跳转全屏播放 ===
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (context) => VideoPlayerPage(url: fileUrl),
                      ),
                    );
                  } else {
                    // === 图片逻辑：进入画廊预览 ===
                    setState(() { _lastInteractionIndex = globalIndex; });
                    _openPreview(globalIndex);
                  }
                }
              },
              onSecondaryTap: () {
                if (!isSelectionMode) {
                  setState(() {
                    isSelectionMode = true;
                    selectedPaths.add(path);
                    _lastInteractionIndex = globalIndex;
                  });
                }
              },
              onLongPress: () {
                if (!isSelectionMode) {
                  setState(() {
                    isSelectionMode = true;
                    selectedPaths.add(path);
                    _lastInteractionIndex = globalIndex;
                  });
                  HapticFeedback.mediumImpact();
                }
              },
              child: Hero(
                tag: isSelectionMode ? "no-hero-$path" : (isVideo ? "video-$path" : fileUrl),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4), 
                      child: Container(
                        color: const Color(0xFF202023), 
                        width: double.infinity, 
                        height: double.infinity, 
                        child: isVideo 
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(color: Colors.black54),
                                const Icon(Icons.play_circle_outline, size: 48, color: Colors.white70),
                                Positioned(bottom: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: const Text("VIDEO", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))
                              ],
                            )
                          : CachedNetworkImage(
                              imageUrl: fileUrl, 
                              memCacheHeight: 1000, // 限制缩略图内存
                              fit: BoxFit.cover, 
                              fadeInDuration: Duration.zero, // 去除淡入动画
                              fadeOutDuration: Duration.zero, 
                              placeholderFadeInDuration: Duration.zero,
                              placeholder: (context, url) => Container(color: const Color(0xFF202023)), 
                              errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image, color: Colors.white24))
                            )
                      )
                    ),
                    if (isSelectionMode) Container(color: isSelected ? Colors.black45 : Colors.transparent, child: Align(alignment: Alignment.topRight, child: Padding(padding: const EdgeInsets.all(8.0), child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.tealAccent : Colors.white70, size: 28)))),
                    if (isSelectionMode && isSelected) Container(decoration: BoxDecoration(border: Border.all(color: Colors.tealAccent, width: 3), borderRadius: BorderRadius.circular(4))),
                  ],
                ),
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
        mainAxisAlignment: isLastRow ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween, 
        children: children
      )
    );
  }

  Widget _buildSectionTitle(String title) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5))));
  Widget _buildFolderGrid(int crossAxisCount) {
    return SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 4), sliver: SliverGrid(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 2 / 3), delegate: SliverChildBuilderDelegate((context, index) {
      final item = folders[index];
      final String? coverPath = item['cover_path'];
      final hasCover = coverPath != null && coverPath.isNotEmpty;
      final coverUrl = hasCover ? TaskManager().getImgUrl(coverPath) : "";
      return GestureDetector(onTap: () { if (isSelectionMode) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot open folder in selection mode"))); } else { Navigator.push(context, CupertinoPageRoute(builder: (context) => GalleryPage(path: item['path']))); } }, onLongPress: () => _showFolderMenu(item), onSecondaryTap: () => _showFolderMenu(item), child: Container(decoration: BoxDecoration(color: const Color(0xFF252528), borderRadius: BorderRadius.circular(4)), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Stack(fit: StackFit.expand, children: [if (hasCover) CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity, memCacheHeight: 400, placeholder: (context, url) => Container(color: const Color(0xFF202023)), errorWidget: (context, url, error) => const Center(child: Icon(Icons.folder, size: 40, color: Colors.amber))), if (!hasCover) const Center(child: Icon(Icons.folder, size: 40, color: Colors.amber)), Positioned(left: 0, right: 0, bottom: 0, height: 60, child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.9), Colors.transparent])))), Positioned(bottom: 8, left: 6, right: 6, child: Text(item['name'], textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500, height: 1.2)))]))));
    }, childCount: folders.length)));
  }
}

// ------------------------------------------------------------------
// 视频播放器封装组件 (带简单的 AutoPlay)
// ------------------------------------------------------------------
class SimpleVideoPlayer extends StatefulWidget {
  final String url;
  final VoidCallback? onTap;
  final bool autoPlay;

  const SimpleVideoPlayer({super.key, required this.url, this.onTap, this.autoPlay = true});

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          if (widget.autoPlay) {
            _controller.play();
          }
          _controller.setLooping(true);
        }
      }).catchError((e) {
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.error, color: Colors.red, size: 40), Text("Playback Error", style: TextStyle(color: Colors.white))]));
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: GestureDetector(
          onTap: () {
            if (widget.onTap != null) {
              widget.onTap!();
            } else {
              _controller.value.isPlaying ? _controller.pause() : _controller.play();
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              if (!_controller.value.isPlaying)
                Container(
                  color: Colors.black26,
                  child: const Center(child: Icon(Icons.play_arrow, size: 60, color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// 全屏视频播放页 (无预览模式)
// ------------------------------------------------------------------
class VideoPlayerPage extends StatelessWidget {
  final String url;

  const VideoPlayerPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: SimpleVideoPlayer(
              url: url,
              autoPlay: true, 
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}


// ------------------------------------------------------------------
// 图片预览页 (保持原样，只处理图片)
// ------------------------------------------------------------------
class PhotoPreviewPage extends StatefulWidget {
  final List<dynamic> images;
  final int initialIndex;
  const PhotoPreviewPage({super.key, required this.images, required this.initialIndex});
  @override
  State<PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}
class _PhotoPreviewPageState extends State<PhotoPreviewPage> with TickerProviderStateMixin {
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
    // 默认进入沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    
    // 初始化时只筛选出图片用于预览 (防止视频混入滑动列表)
    // 但根据需求，如果用户希望点击视频就去全屏，这里就不需要太担心列表混杂问题
    // 不过为了逻辑闭环，建议预览页的数据源和列表保持一致，只是点击入口不同
    _currentImages = List.from(widget.images);
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _breatheController = AnimationController(vsync: this, duration: const Duration(seconds: 1), lowerBound: 0.5, upperBound: 1.0);
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
    setState(() { showControls = !showControls; }); 
    if (showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
  }
  
  void _toggleAutoPlay() { setState(() { isPlaying = !isPlaying; }); if (isPlaying) { _breatheController.repeat(reverse: true); _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (timer) { if (currentIndex < _currentImages.length - 1) { _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); } else { _pageController.jumpToPage(0); } }); } else { _breatheController.stop(); _breatheController.value = 1.0; _autoPlayTimer?.cancel(); } }
  void _onVerticalDragUpdate(DragUpdateDetails details) { if (_isZoomed) return; setState(() { double dy = _dragOffset.dy + details.delta.dy; double dx = _dragOffset.dx + details.delta.dx; if (dy < 0) dy *= 0.4; _dragOffset = Offset(dx, dy); final screenHeight = MediaQuery.of(context).size.height; double progress = (_dragOffset.dy.abs() / screenHeight).clamp(0.0, 1.0); _dragScale = 1.0 - (progress * 0.4); }); }
  void _onVerticalDragEnd(DragEndDetails details) { if (_isZoomed) return; final velocity = details.primaryVelocity ?? 0; final screenHeight = MediaQuery.of(context).size.height; final threshold = screenHeight * 0.15; if (_dragOffset.dy > threshold || velocity > 800) { Navigator.pop(context, currentIndex); } else { _runResetAnimation(); } }
  void _runResetAnimation() { _resetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350)); _offsetAnimation = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(CurvedAnimation(parent: _resetController!, curve: Curves.easeOutBack)); _scaleAnimation = Tween<double>(begin: _dragScale, end: 1.0).animate(CurvedAnimation(parent: _resetController!, curve: Curves.easeOut)); _resetController!.addListener(() { setState(() { _dragOffset = _offsetAnimation!.value; _dragScale = _scaleAnimation!.value; }); }); _resetController!.forward(); }
  Future<void> _deleteCurrentPhoto() async { bool wasPlaying = isPlaying; if (wasPlaying) _toggleAutoPlay(); bool? confirm = await showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF252528), title: const Text("Confirm Delete", style: TextStyle(color: Colors.white)), content: const Text("Are you sure you want to delete this image?", style: TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red)))])); if (confirm == true) { final item = _currentImages[currentIndex]; try { await Dio().post('$serverUrl/api/delete', data: FormData.fromMap({'path': item['path']})); setState(() { _currentImages.removeAt(currentIndex); if (currentIndex >= _currentImages.length) currentIndex = _currentImages.length - 1; }); if (_currentImages.isEmpty) Navigator.pop(context, -1); else if (wasPlaying) _toggleAutoPlay(); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete failed: $e"))); } } else { if (wasPlaying) _toggleAutoPlay(); } }
  void _handleKeyEvent(RawKeyEvent event) { if (event is RawKeyDownEvent) { if (event.logicalKey == LogicalKeyboardKey.escape) Navigator.pop(context, currentIndex); else if (event.logicalKey == LogicalKeyboardKey.space) _toggleAutoPlay(); else if (event.logicalKey == LogicalKeyboardKey.arrowRight) _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) _deleteCurrentPhoto(); } }

  @override
  Widget build(BuildContext context) {
    if (_currentImages.isEmpty) return const SizedBox();
    final currentItem = _currentImages[currentIndex];
    final platform = Theme.of(context).platform;
    final isMobile = platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    final screenHeight = MediaQuery.of(context).size.height;
    double opacityProgress = (_dragOffset.dy.abs() / (screenHeight * 0.5)).clamp(0.0, 1.0);
    double bgOpacity = 1.0 - opacityProgress;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent, // Android
        statusBarIconBrightness: Brightness.light, // Android Icons
        statusBarBrightness: Brightness.dark, // iOS White Text
      ),
      child: Focus(
        autofocus: true, 
        onKey: (node, event) { _handleKeyEvent(event); return KeyEventResult.handled; }, 
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
                        scaleStateChangedCallback: (PhotoViewScaleState state) { setState(() { _isZoomed = state != PhotoViewScaleState.initial; }); }, 
                        builder: (BuildContext context, int index) { 
                          final item = _currentImages[index]; 
                          final imgUrl = TaskManager().getImgUrl(item['path']); 
                          // 只有图片会进入这里，所以放心使用图片 Provider
                          return PhotoViewGalleryPageOptions(
                            imageProvider: CachedNetworkImageProvider(imgUrl), 
                            initialScale: PhotoViewComputedScale.contained, 
                            minScale: PhotoViewComputedScale.contained, 
                            maxScale: PhotoViewComputedScale.covered * 3.0, 
                            heroAttributes: PhotoViewHeroAttributes(tag: imgUrl), 
                            onTapUp: (context, details, value) { _toggleControls(); }
                          ); 
                        }, 
                        itemCount: _currentImages.length, 
                        loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator(color: Colors.white24)), 
                        pageController: _pageController, 
                        onPageChanged: (index) { setState(() { currentIndex = index; }); }, 
                        backgroundDecoration: const BoxDecoration(color: Colors.transparent)
                      )
                    )
                  )
                )
              ), 
              IgnorePointer(
                ignoring: !showControls, 
                child: Opacity(
                  opacity: bgOpacity, 
                  child: Stack(
                    children: [
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
                              top: MediaQuery.of(context).padding.top + 10
                            ), 
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black87, Colors.transparent], 
                                begin: Alignment.topCenter, 
                                end: Alignment.bottomCenter
                              )
                            ), 
                            child: Stack(
                              alignment: Alignment.center, 
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft, 
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
                                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), 
                                    child: Text("${currentIndex + 1}/${_currentImages.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                                  )
                                ),
                                Align(
                                  alignment: Alignment.center, 
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, 
                                    children: [
                                      Text(currentItem['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis), 
                                      if (currentItem['w'] != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text("${currentItem['w']} x ${currentItem['h']} px", style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis))
                                    ]
                                  )
                                ),
                                Align(
                                  alignment: Alignment.centerRight, 
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min, 
                                    children: [
                                      AnimatedBuilder(animation: _breatheController, builder: (ctx, child) => Opacity(opacity: isPlaying ? _breatheController.value : 1.0, child: IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: isPlaying ? Colors.tealAccent : Colors.white), iconSize: 28, onPressed: _toggleAutoPlay))), 
                                      const SizedBox(width: 16), 
                                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_outline, color: Colors.redAccent), iconSize: 24, onPressed: _deleteCurrentPhoto), 
                                      const SizedBox(width: 16), 
                                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.close, color: Colors.white), iconSize: 28, onPressed: () => Navigator.pop(context, currentIndex))
                                    ]
                                  )
                                )
                              ]
                            )
                          )
                        )
                      ), 
                      if (!isMobile) ...[
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250), 
                          curve: Curves.easeInOut, 
                          left: showControls ? 10 : -50, 
                          top: 0, 
                          bottom: 0, 
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250), 
                            opacity: showControls ? 1.0 : 0.0, 
                            child: Center(child: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 30), onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease)))
                          )
                        ), 
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250), 
                          curve: Curves.easeInOut, 
                          right: showControls ? 10 : -50, 
                          top: 0, 
                          bottom: 0, 
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250), 
                            opacity: showControls ? 1.0 : 0.0, 
                            child: Center(child: IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 30), onPressed: () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease)))
                          )
                        )
                      ]
                    ]
                  )
                )
              )
            ]
          )
        ),
      ),
    );
  }
}