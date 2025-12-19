import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import '../config.dart';
import 'tv_focusable_widget.dart';

class GalleryFolderItem extends StatelessWidget {
  final Map<String, dynamic> folder;
  final String coverUrl;
  final bool isSelected;
  final bool isSelectionMode;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;

  const GalleryFolderItem({
    super.key,
    required this.folder,
    required this.coverUrl,
    required this.isSelected,
    required this.isSelectionMode,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover = coverUrl.isNotEmpty;

    return TVFocusableWidget(
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252528),
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: Colors.tealAccent, width: 2)
              : null,
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
                    child: Icon(Icons.folder, size: 40, color: Colors.amber),
                  ),
                ),
              if (!hasCover)
                const Center(
                  child: Icon(Icons.folder, size: 40, color: Colors.amber),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder['name'],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    if (folder['count'] != null)
                      Text(
                        "${folder['count']} items",
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white54,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.tealAccent,
                      size: 32,
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

class GalleryVideoItem extends StatelessWidget {
  final Map<String, dynamic> video;
  final String thumbUrl;
  final bool isSelected;
  final bool isSelectionMode;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;

  const GalleryVideoItem({
    super.key,
    required this.video,
    required this.thumbUrl,
    required this.isSelected,
    required this.isSelectionMode,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final path = video['path'];

    return TVFocusableWidget(
      autofocus: autofocus,
      isSelected: isSelected,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      onLongPress: onLongPress,
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
                              colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
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
                            colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
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
                        video['name'],
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
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? Colors.tealAccent : Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),
            Positioned(top: 4, right: 4, child: VideoResolutionTag(path: path)),
          ],
        ),
      ),
    );
  }
}

class GalleryImageItem extends StatelessWidget {
  final Map<String, dynamic> image;
  final String fileUrl;
  final String thumbUrl;
  final double width;
  final double height;
  final bool isSelected;
  final bool isSelectionMode;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;

  const GalleryImageItem({
    super.key,
    required this.image,
    required this.fileUrl,
    required this.thumbUrl,
    required this.width,
    required this.height,
    required this.isSelected,
    required this.isSelectionMode,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    // Assuming type is image, so no video logic needed for this specific widget
    // If needed we can add isVideo flag.

    return SizedBox(
      width: width,
      height: height,
      child: TVFocusableWidget(
        autofocus: autofocus,
        isSelected: isSelected,
        key: ValueKey(image['path']),
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                color: const Color(0xFF202023),
                child: CachedNetworkImage(
                  imageUrl: fileUrl,
                  memCacheHeight: 500,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: const Color(0xFF202023)),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
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
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? Colors.tealAccent : Colors.white70,
                      size: 28,
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
