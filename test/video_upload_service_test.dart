import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/video_upload_service.dart';

void main() {
  test('숏폼과 레슨 피드백의 권한 오류를 구분한다', () {
    final error = FirebaseException(
      plugin: 'firebase_storage',
      code: 'unauthorized',
    );

    expect(videoUploadError(error), contains('다시 로그인'));
    expect(
      videoUploadError(error, lessonFeedback: true),
      contains('이 레슨의 수강생 또는 코치'),
    );
  });

  test('영상 삭제 서버의 권한 및 연결 오류를 안내한다', () {
    expect(
      videoDeleteError(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Permission denied',
        ),
      ),
      contains('본인이 올린 영상'),
    );
    expect(
      videoDeleteError(
        FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Unavailable',
        ),
      ),
      contains('연결하지 못했습니다'),
    );
  });
}
