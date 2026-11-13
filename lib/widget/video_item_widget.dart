import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/storage_video_source_native.dart'
    if (dart.library.html) '../services/storage_video_source_web.dart' as media;

class VideoItemWidget extends StatefulWidget {
  final String videoUrl;
  final bool isPlaying;
  final BoxFit fit;

  const VideoItemWidget({
    super.key,
    required this.videoUrl,
    this.isPlaying = true,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoItemWidget> createState() => _VideoItemWidgetState();
}

class _VideoItemWidgetState extends State<VideoItemWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  Future<void> Function()? _cleanup;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final generation = ++_generation;
    VideoPlayerController? controller;
    Future<void> Function()? cleanup;
    try {
      final path = widget.videoUrl;
      if (path.startsWith('videos/') || path.startsWith('lesson_feedback/')) {
        final bytes =
            await FirebaseStorage.instance.ref(path).getData(100 * 1024 * 1024);
        if (bytes == null) throw StateError('영상을 찾을 수 없습니다.');
        final source = await media.videoSource(bytes);
        controller = source.controller;
        cleanup = source.cleanup;
      } else {
        // Existing feed URLs remain readable; private feedback always uses paths.
        controller = VideoPlayerController.networkUrl(Uri.parse(path));
      }
      if (!mounted || generation != _generation) {
        await controller.dispose();
        await cleanup?.call();
        return;
      }
      _cleanup = cleanup;
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted || controller != _controller) return;

      setState(() => _isInitialized = true);
      if (widget.isPlaying) controller.play();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant VideoItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposePlayer();
      _isInitialized = false;
      _hasError = false;
      _initializePlayer();
      return;
    }
    if (_isInitialized) {
      if (widget.isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      } else if (!widget.isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  Future<void> _disposePlayer() async {
    final controller = _controller;
    final cleanup = _cleanup;
    _controller = null;
    _cleanup = null;
    await controller?.dispose();
    await cleanup?.call();
  }

  @override
  void dispose() {
    ++_generation;
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            SizedBox(height: 12),
            Text(
              '영상을 불러올 수 없습니다.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
          if (!_controller!.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 48,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
