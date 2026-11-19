import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';

Future<bool> confirmLogout(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: OnepointDesign.surface,
        titleTextStyle: OnepointDesign.heading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
              key: const ValueKey('cancel-logout'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              key: const ValueKey('confirm-logout'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('로그아웃')),
        ],
      ),
    ) ==
    true;
