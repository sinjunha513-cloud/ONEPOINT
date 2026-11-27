import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/video_upload_service.dart';
import '../widgets/onepoint_app_bar.dart';
import '../widgets/onepoint_icon.dart';

class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key, this.lessonId, this.service});

  final String? lessonId;
  final VideoUploadService? service;

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final _service = widget.service ?? VideoUploadService();
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
          title: _titleController.text,
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
          content: Text(_isFeedback
              ? '피드백 영상을 등록했습니다. 공개 피드에서 확인해 보세요.'
              : '공개 피드에 영상을 등록했습니다.'),
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
        appBar: OnepointAppBar(
          title: _isFeedback ? '레슨 피드백 영상 등록' : '숏폼 영상 등록',
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.public, color: Color(0xFFC7F000)),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                '전체 공개 · 로그인한 모든 이용자가 영상과 설명을 공개 피드에서 볼 수 있어요.',
                                style: TextStyle(
                                    color: Colors.white70, height: 1.5))),
                      ])),
              InkWell(
                onTap: _uploading ? null : _pickVideo,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: MediaQuery.sizeOf(context)
                      .width
                      .clamp(240, 380)
                      .toDouble(),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF24A9FF)),
                  ),
                  child: _selectedVideo == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OnepointIcon('video-upload', width: 63, height: 36),
                            SizedBox(height: 8),
                            Text('영상 선택하기',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600)),
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
              ...[
                TextField(
                  controller: _titleController,
                  enabled: !_uploading,
                  maxLength: 120,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(_isFeedback ? '피드백 제목 (선택)' : '영상 제목',
                      '공개 피드에 표시할 제목을 적어 주세요.'),
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
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC7F000),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  onPressed: _upload,
                  icon: Icon(_error == null
                      ? Icons.cloud_upload_rounded
                      : Icons.refresh_rounded),
                  label: Text(_error == null ? '전체 공개로 업로드' : '같은 영상 다시 시도'),
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
        fillColor: const Color(0xFF252525),
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
          borderSide: const BorderSide(color: Color(0xFF24A9FF), width: 2),
        ),
      );
}
