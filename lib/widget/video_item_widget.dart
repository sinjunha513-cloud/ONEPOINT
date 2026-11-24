import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/media_playback_service.dart';

class VideoItemWidget extends StatefulWidget {
  const VideoItemWidget(
      {super.key,
      required this.videoUrl,
      this.videoId,
      this.lessonId,
      this.isPlaying = true,
      this.autoplay = true,
      this.fit = BoxFit.cover,
      this.service});
  final String videoUrl;
  final String? videoId, lessonId;
  final bool isPlaying, autoplay;
  final BoxFit fit;
  final MediaPlaybackService? service;
  @override
  State<VideoItemWidget> createState() => _VideoItemWidgetState();
}

class _VideoItemWidgetState extends State<VideoItemWidget> {
  static _VideoItemWidgetState? _active;
  VideoPlayerController? _controller;
  bool _ready = false, _loading = false, _error = false, _muted = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.isPlaying && widget.autoplay) _start();
  }

  Future<void> _start() async {
    if (_loading || !widget.isPlaying) return;
    if (_active != this) _active?._stop();
    _active = this;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
    });
    VideoPlayerController? controller;
    try {
      final uri = widget.videoId != null
          ? await (widget.service ?? MediaPlaybackService())
              .url(videoId: widget.videoId!, lessonId: widget.lessonId)
          : Uri.parse(widget.videoUrl);
      if (!mounted || generation != _generation) return;
      controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      _muted = widget.autoplay;
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      await controller.play();
      if (mounted && generation == _generation) {
        setState(() {
          _ready = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      if (mounted && generation == _generation) {
        setState(() {
          _controller = null;
          _ready = false;
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _stop() {
    ++_generation;
    final c = _controller;
    _controller = null;
    _ready = false;
    _loading = false;
    if (_active == this) _active = null;
    c?.dispose().catchError((Object _) {});
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.videoId != widget.videoId ||
        oldWidget.lessonId != widget.lessonId ||
        !widget.isPlaying) {
      _stop();
      _error = false;
    }
    if (widget.isPlaying && !_ready && !_loading && widget.autoplay) _start();
  }

  @override
  void dispose() {
    ++_generation;
    if (_active == this) _active = null;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_loading)
          const CircularProgressIndicator()
        else
          IconButton(
              iconSize: 48,
              onPressed: widget.isPlaying ? _start : null,
              tooltip: _error ? '영상 다시 불러오기' : '영상 재생',
              icon: Icon(_error ? Icons.refresh : Icons.play_circle_outline)),
        if (_error)
          const Text('영상을 불러오지 못했습니다.\n다시 시도해 주세요.',
              textAlign: TextAlign.center),
      ]));
    }
    final c = _controller!;
    return GestureDetector(
        onTap: () async {
          if (c.value.isPlaying) {
            await c.pause();
          } else {
            await c.play();
          }
          if (mounted) setState(() {});
        },
        child: Stack(alignment: Alignment.center, children: [
          ColoredBox(
              color: Colors.black,
              child: SizedBox.expand(
                  child: FittedBox(
                      fit: widget.fit,
                      child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c))))),
          if (!c.value.isPlaying)
            const Icon(Icons.play_circle_fill, size: 54, color: Colors.white),
          Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                  tooltip: _muted ? '소리 켜기' : '소리 끄기',
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    _muted = !_muted;
                    await c.setVolume(_muted ? 0 : 1);
                    if (mounted) setState(() {});
                  },
                  icon: Icon(_muted ? Icons.volume_off : Icons.volume_up))),
        ]));
  }
}
