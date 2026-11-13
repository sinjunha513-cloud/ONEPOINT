import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/video_upload_service.dart';

class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key, this.lessonId});

  final String? lessonId;

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _service = VideoUploadService();
  XFile? _selectedVideo;
  int? _selectedBytes;
  UploadTask? _task;
  bool _uploading = false;
  double _progress = 0;
  String? _error;

  bool get _isFeedback => widget.lessonId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      final bytes = await _service.validateVideo(video);
      if (!mounted) return;
      setState(() {
        _selectedVideo = video;
        _selectedBytes = bytes;
        _error = null;
        _progress = 0;
      });
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = videoUploadError(error, lessonFeedback: _isFeedback));
      }
    }
  }

  Future<void> _upload() async {
    if (_selectedVideo == null) {
      setState(() => _error = '영상을 먼저 선택해 주세요.');
      return;
    }
    if (!_isFeedback && _titleController.text.trim().isEmpty) {
      setState(() => _error = '제목을 입력해 주세요.');
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
      _error = null;
    });
    try {
      void progress(double value) {
        if (mounted) setState(() => _progress = value.clamp(0, 1));
      }

      void taskReady(UploadTask task) {
        _task = task;
      }

      if (_isFeedback) {
        await _service.uploadLessonFeedback(
          videoFile: _selectedVideo!,
          lessonId: widget.lessonId!,
          description: _descriptionController.text,
          onProgress: progress,
          onTaskReady: taskReady,
        );
      } else {
        await _service.uploadVideoAndCreateFeed(
          videoFile: _selectedVideo!,
          title: _titleController.text,
          description: _descriptionController.text,
          onProgress: progress,
          onTaskReady: taskReady,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFeedback ? '레슨 피드백 영상을 등록했습니다.' : '숏폼 영상을 등록했습니다.'),
        ),
      );
      _titleController.clear();
      _descriptionController.clear();
      setState(() {
        _selectedVideo = null;
        _selectedBytes = null;
        _progress = 0;
      });
      if (Navigator.of(context).canPop()) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = videoUploadError(error, lessonFeedback: _isFeedback));
      }
    } finally {
      _task = null;
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _cancel() async {
    final task = _task;
    if (task == null) return;
    await task.cancel();
  }

  String _sizeLabel(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB / 100MB';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_isFeedback ? '레슨 피드백 영상 등록' : '숏폼 영상 등록'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InkWell(
                onTap: _uploading ? null : _pickVideo,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: _selectedVideo == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_call_rounded,
                                size: 48, color: Color(0xFF38BDF8)),
                            SizedBox(height: 8),
                            Text('갤러리에서 영상 선택',
                                style: TextStyle(color: Colors.white70)),
                            SizedBox(height: 4),
                            Text('최대 100MB',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 48, color: Colors.greenAccent),
                              const SizedBox(height: 8),
                              Text(
                                _selectedVideo!.name,
                                style: const TextStyle(color: Colors.white),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              if (_selectedBytes != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _sizeLabel(_selectedBytes!),
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              if (!_isFeedback) ...[
                TextField(
                  controller: _titleController,
                  enabled: !_uploading,
                  maxLength: 120,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('숏폼 제목', '영상 내용을 짧게 알려 주세요.'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _descriptionController,
                enabled: !_uploading,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration(
                  _isFeedback ? '레슨 피드백 설명 (선택)' : '설명 (선택)',
                  _isFeedback
                      ? '자세 교정, 연습 방법 등 영상 설명을 남겨 주세요.'
                      : '영상에 대한 설명을 남겨 주세요.',
                ),
              ),
              if (_uploading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  '업로드 중 ${(_progress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: .5)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_uploading)
                OutlinedButton.icon(
                  onPressed: _task == null ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('업로드 취소'),
                )
              else
                FilledButton.icon(
                  onPressed: _upload,
                  icon: Icon(_error == null
                      ? Icons.cloud_upload_rounded
                      : Icons.refresh_rounded),
                  label: Text(_error == null ? '업로드' : '같은 영상 다시 시도'),
                ),
            ],
          ),
        ),
      );

  InputDecoration _decoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 2),
        ),
      );
}
