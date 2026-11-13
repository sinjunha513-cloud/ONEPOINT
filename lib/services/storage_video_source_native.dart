import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

Future<({VideoPlayerController controller, Future<void> Function() cleanup})>
    videoSource(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('onepoint-video-');
  final file = File('${directory.path}/video.mp4');
  await file.writeAsBytes(bytes, flush: true);
  return (
    controller: VideoPlayerController.file(file),
    cleanup: () async {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  );
}
