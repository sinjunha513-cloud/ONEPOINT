import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class CareerPdfView extends StatelessWidget {
  const CareerPdfView({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) => Center(
      child: FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('PDF 앱으로 열기'),
          onPressed: () async {
            try {
              final directory = await getTemporaryDirectory();
              final file = File(
                  '${directory.path}/career_${DateTime.now().microsecondsSinceEpoch}.pdf');
              await file.writeAsBytes(bytes);
              final result =
                  await OpenFilex.open(file.path, type: 'application/pdf');
              if (result.type != ResultType.done && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF를 열 수 있는 앱을 설치해 주세요.')));
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF를 열지 못했습니다.')));
              }
            }
          }));
}
