import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

typedef UploadProgress = void Function(double progress);
typedef UploadTaskReady = void Function(UploadTask task);

class VideoUploadService {
  VideoUploadService({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static const int maxVideoBytes = 100 * 1024 * 1024;

  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Future<int> validateVideo(XFile videoFile) async {
    final length = await videoFile.length();
    if (length <= 0) throw StateError('비어 있는 영상은 업로드할 수 없습니다.');
    if (length > maxVideoBytes) {
      throw StateError('영상은 100MB 이하만 업로드할 수 있습니다.');
    }
    return length;
  }

  Future<String> uploadVideoAndCreateFeed({
    required XFile videoFile,
    required String title,
    String description = '',
    UploadProgress? onProgress,
    UploadTaskReady? onTaskReady,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw StateError('제목은 1자 이상 120자 이내로 입력해 주세요.');
    }
    if (description.trim().length > 2000) {
      throw StateError('설명은 2000자 이내로 입력해 주세요.');
    }
    final user = _signedInUser();
    await validateVideo(videoFile);
    final profile = await _firestore.collection('users').doc(user.uid).get();
    final name = _text(profile.data()?['name']) ?? user.displayName ?? '수강생/코치';
    final extension = _extension(videoFile);
    final ref = _storage.ref().child(
        'videos/${user.uid}/${DateTime.now().microsecondsSinceEpoch}.$extension');
    final url = await _upload(
      videoFile,
      ref,
      onProgress: onProgress,
      onTaskReady: onTaskReady,
    );
    try {
      await _firestore.collection('feed_videos').add({
        'userId': user.uid,
        'userName': name,
        'title': cleanTitle,
        'description': description.trim(),
        'videoUrl': url,
        'storagePath': ref.fullPath,
        'likes': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await _deleteQuietly(ref);
      rethrow;
    }
    return url;
  }

  Future<String> uploadLessonFeedback({
    required XFile videoFile,
    required String lessonId,
    String description = '',
    UploadProgress? onProgress,
    UploadTaskReady? onTaskReady,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(lessonId)) {
      throw StateError('레슨 정보가 올바르지 않습니다.');
    }
    if (description.trim().length > 2000) {
      throw StateError('설명은 2000자 이내로 입력해 주세요.');
    }
    final user = _signedInUser();
    await validateVideo(videoFile);
    final results = await Future.wait([
      _firestore.collection('lesson_requests').doc(lessonId).get(),
      _firestore.collection('users').doc(user.uid).get(),
    ]);
    final lesson = results[0];
    final profile = results[1];
    final lessonData = lesson.data();
    if (!lesson.exists || lessonData == null) {
      throw StateError('연결된 레슨을 찾을 수 없습니다.');
    }
    final participants = (lessonData['participantIds'] as List<dynamic>? ?? [])
        .whereType<String>();
    if (!participants.contains(user.uid)) {
      throw StateError('해당 레슨의 수강생과 코치만 영상을 올릴 수 있습니다.');
    }
    if (!const ['accepted', 'confirmed', 'completed']
        .contains(lessonData['status'])) {
      throw StateError('수락 또는 확정된 레슨에만 피드백 영상을 올릴 수 있습니다.');
    }
    final extension = _extension(videoFile);
    final ref = _storage.ref().child(
        'lesson_feedback/$lessonId/${user.uid}/${DateTime.now().microsecondsSinceEpoch}.$extension');
    final url = await _upload(
      videoFile,
      ref,
      customMetadata: {'lessonId': lessonId, 'uploaderUid': user.uid},
      onProgress: onProgress,
      onTaskReady: onTaskReady,
    );
    try {
      await _firestore
          .collection('lesson_requests')
          .doc(lessonId)
          .collection('feedback_videos')
          .add({
        'uploaderUid': user.uid,
        'uploaderName':
            _text(profile.data()?['name']) ?? user.displayName ?? '레슨 참여자',
        'lessonId': lessonId,
        'storagePath': ref.fullPath,
        'description': description.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await _deleteQuietly(ref);
      rethrow;
    }
    return url;
  }

  Future<void> deleteFeedVideo(String videoId) async {
    _validateDocumentId(videoId, '영상');
    await _functions.httpsCallable('deleteVideo').call({
      'kind': 'feed',
      'videoId': videoId,
    });
  }

  Future<void> deleteLessonFeedback({
    required String lessonId,
    required String videoId,
  }) async {
    _validateDocumentId(lessonId, '레슨');
    _validateDocumentId(videoId, '영상');
    await _functions.httpsCallable('deleteVideo').call({
      'kind': 'feedback',
      'lessonId': lessonId,
      'videoId': videoId,
    });
  }

  void _validateDocumentId(String value, String label) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
      throw StateError('$label 정보가 올바르지 않습니다.');
    }
  }

  User _signedInUser() {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    return user;
  }

  String _extension(XFile file) {
    final raw = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'mp4';
    return const {'mp4', 'mov', 'webm', 'm4v'}.contains(raw) ? raw : 'mp4';
  }

  String _contentType(String extension) => switch (extension) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'm4v' => 'video/x-m4v',
        _ => 'video/mp4',
      };

  Future<String> _upload(
    XFile videoFile,
    Reference ref, {
    Map<String, String>? customMetadata,
    UploadProgress? onProgress,
    UploadTaskReady? onTaskReady,
  }) async {
    final extension = _extension(videoFile);
    final metadata = SettableMetadata(
      contentType: _contentType(extension),
      customMetadata: customMetadata,
    );
    final task = kIsWeb
        ? ref.putData(await videoFile.readAsBytes(), metadata)
        : ref.putFile(File(videoFile.path), metadata);
    onTaskReady?.call(task);
    StreamSubscription<TaskSnapshot>? subscription;
    if (onProgress != null) {
      subscription = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        onProgress(total <= 0 ? 0 : snapshot.bytesTransferred / total);
      });
    }
    try {
      final snapshot = await task;
      onProgress?.call(1);
      return await snapshot.ref.getDownloadURL();
    } finally {
      await subscription?.cancel();
    }
  }

  Future<void> _deleteQuietly(Reference ref) async {
    try {
      await ref.delete();
    } catch (_) {
      // Preserve the original metadata write error.
    }
  }

  String? _text(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}

String videoDeleteError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FirebaseFunctionsException) {
    final message = error.message ?? '';
    if (RegExp(r'[가-힣]').hasMatch(message)) return message;
    return switch (error.code) {
      'unauthenticated' => '로그인한 뒤 다시 시도해 주세요.',
      'permission-denied' => '본인이 올린 영상만 삭제할 수 있습니다.',
      'not-found' => '이미 삭제됐거나 존재하지 않는 영상입니다.',
      'unavailable' ||
      'deadline-exceeded' =>
        '영상 삭제 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      _ => '영상을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  return '영상을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.';
}

String videoUploadError(Object error, {bool lessonFeedback = false}) {
  if (error is StateError) return error.message.toString();
  if (error is FirebaseException) {
    return switch (error.code) {
      'canceled' => '업로드를 취소했습니다. 같은 영상을 다시 시도할 수 있습니다.',
      'unauthenticated' => '로그인한 뒤 다시 시도해 주세요.',
      'unauthorized' || 'permission-denied' => lessonFeedback
          ? '이 레슨의 수강생 또는 코치만 피드백 영상을 올릴 수 있습니다. 레슨 상태도 확인해 주세요.'
          : '영상 업로드 권한을 확인하지 못했습니다. 다시 로그인한 뒤 계정 상태를 확인해 주세요.',
      'quota-exceeded' => '저장소 사용 한도를 확인해 주세요.',
      'retry-limit-exceeded' ||
      'unavailable' =>
        '네트워크 연결이 불안정합니다. 같은 영상을 다시 시도해 주세요.',
      'object-not-found' => '업로드된 영상을 찾을 수 없습니다. 다시 업로드해 주세요.',
      _ => '영상을 업로드하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  return '영상을 업로드하지 못했습니다. 잠시 후 다시 시도해 주세요.';
}
