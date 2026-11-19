import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'onepoint_logo.dart';
import 'onepoint_icon.dart';
import '../config/onepoint_design.dart';
import '../screens/lesson_badges_screen.dart';
import '../screens/lesson_requests_screen.dart';
import '../screens/notifications_screen.dart';
import '../services/lesson_badge_service.dart';
import '../services/matching_service.dart';
import '../services/payment_service.dart';
import '../services/notification_inbox_service.dart';
import 'onepoint_lesson_icon.dart';

/// A shared brand header, keeping the screen name and its existing actions.
class OnepointAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OnepointAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showSectionTitle = true,
    this.sectionSubtitle,
    this.firestore,
    this.auth,
  });

  final String title;
  final List<Widget>? actions;
  final bool showSectionTitle;
  final String? sectionSubtitle;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  @override
  Size get preferredSize => Size.fromHeight(80 + (showSectionTitle ? 68 : 0));

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: OnepointDesign.background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 80,
        elevation: 0,
        title: const Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR GAME. YOUR GROWTH.',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        color: OnepointDesign.muted)),
                SizedBox(height: 4),
                OnepointLogo(),
              ],
            ),
          ),
        ),
        actions: actions ??
            [
              IconButton(
                tooltip: '내 뱃지',
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 48),
                icon: const OnepointIcon('badge', width: 29, height: 36),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LessonBadgesScreen(
                            service: LessonBadgeService(
                                firestore: firestore, auth: auth)))),
              ),
              IconButton(
                tooltip: '내 레슨',
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 48),
                icon: const OnepointLessonIcon(),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LessonRequestsScreen(
                            service: MatchingService(
                                firestore: firestore, auth: auth),
                            paymentService:
                                PaymentService(firestore: firestore)))),
              ),
              IconButton(
                tooltip: '알림',
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 48),
                icon: const OnepointIcon('bell', width: 27, height: 27),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NotificationsScreen(
                            service: NotificationInboxService(
                                firestore: firestore, auth: auth)))),
              ),
              const SizedBox(width: 8),
            ],
        bottom: !showSectionTitle
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(68),
                child: Container(
                  height: 68,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: sectionSubtitle == null
                      ? null
                      : BoxDecoration(
                          color: OnepointDesign.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OnepointDesign.heading),
                        if (sectionSubtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(sectionSubtitle!,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  color: Colors.white70)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
      );
}
