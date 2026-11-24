import 'package:cloud_functions/cloud_functions.dart';

class MediaPlaybackService {
  MediaPlaybackService({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;
  Future<Uri> url({required String videoId, String? lessonId}) async {
    final result = await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable('getMediaPlayback')
        .call({
      'kind': lessonId == null ? 'feed' : 'feedback',
      'videoId': videoId,
      if (lessonId != null) 'lessonId': lessonId
    });
    final value = Uri.parse((result.data as Map)['url'] as String);
    if (value.scheme != 'https') throw StateError('재생 주소를 확인할 수 없습니다.');
    return value;
  }
}
