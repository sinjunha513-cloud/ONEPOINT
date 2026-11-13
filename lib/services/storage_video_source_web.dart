// Browser video elements cannot attach Firebase Authorization headers.
// Fetch through the authenticated SDK, then use a revocable in-memory URL.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

Future<({VideoPlayerController controller, Future<void> Function() cleanup})>
    videoSource(Uint8List bytes) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));
  return (
    controller: VideoPlayerController.networkUrl(Uri.parse(url)),
    cleanup: () async {
      html.Url.revokeObjectUrl(url);
    }
  );
}
