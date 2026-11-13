import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CareerPdfView extends StatefulWidget {
  const CareerPdfView({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<CareerPdfView> createState() => _CareerPdfViewState();
}

class _CareerPdfViewState extends State<CareerPdfView> {
  late final _url = web.URL.createObjectURL(web.Blob(
      [widget.bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf')));
  @override
  void dispose() {
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.src = _url;
        frame.title = '경력 PDF';
        frame.style.width = '100%';
        frame.style.height = '100%';
        frame.style.border = '0';
      });
}
