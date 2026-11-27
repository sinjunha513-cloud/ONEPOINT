import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/matching_service.dart';

void main() {
  test(
      'lesson errors use lesson-specific fallbacks without payment setup instructions',
      () {
    for (final code in [
      'invalid-argument',
      'not-found',
      'unavailable',
      'failed-precondition',
      'internal',
      'aborted'
    ]) {
      final text = lessonWorkflowError(
          FirebaseFunctionsException(code: code, message: 'internal'));
      expect(text, contains('레슨'));
      expect(text, isNot(contains('결제')));
      expect(text, isNot(contains('토스')));
    }
  });
  test('specific safe Korean validation errors are retained', () {
    const message = '시그니처 뱃지 정보를 확인해 주세요.';
    expect(
        lessonWorkflowError(FirebaseFunctionsException(
            code: 'invalid-argument', message: message)),
        message);
    expect(
        lessonWorkflowError(FirebaseFunctionsException(
            code: 'failed-precondition',
            message: '확정된 수업 종료 시간이 지난 후에 완료를 확인할 수 있습니다.')),
        contains('종료 시간'));
  });
}
