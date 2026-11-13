import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../widgets/career_pdf_view.dart';

class CareerPdfService {
  Future<Map<String, dynamic>?> pickAndUpload() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (selection == null) return null;
    final file = selection.files.single;
    final bytes = file.bytes;
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024 ||
        !String.fromCharCodes(bytes.take(1024)).contains('%PDF-')) {
      throw StateError('5MB 이하의 PDF 파일을 선택해 주세요.');
    }
    final id = 'pdf_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    await FirebaseStorage.instance
        .ref('coach_documents/$uid/$id.pdf')
        .putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('로그인 계정이 변경되었습니다.');
    }
    final result =
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('validateCareerPdf')
            .call({'fileId': id, 'fileName': file.name});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> open(BuildContext context, String uid, String fileId) async {
    final Uint8List? bytes = await FirebaseStorage.instance
        .ref('coach_documents/$uid/$fileId.pdf')
        .getData(5 * 1024 * 1024);
    if (bytes == null) throw StateError('PDF를 찾을 수 없습니다.');
    if (!context.mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('경력 PDF')),
                body: CareerPdfView(bytes: bytes))));
  }
}
