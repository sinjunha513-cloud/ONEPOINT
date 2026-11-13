import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../screens/payment_result_screen.dart';

final paymentNavigatorKey = GlobalKey<NavigatorState>();
StreamSubscription<Uri>? _paymentLinks;

Future<void> watchPaymentLinks() async {
  final links = AppLinks();
  String? previous;
  void open(Uri uri) {
    if (uri.scheme != 'onepoint' ||
        uri.host != 'payment-result' ||
        previous == uri.toString()) {
      return;
    }
    previous = uri.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        paymentNavigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) =>
                PaymentResultScreen(parameters: uri.queryParameters))));
  }

  _paymentLinks ??= links.uriLinkStream.listen(open, onError: (Object _) {});
  final initial = await links.getInitialLink();
  if (initial != null) open(initial);
}
