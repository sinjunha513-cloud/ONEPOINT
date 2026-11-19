import 'package:flutter/material.dart';

import '../config/onepoint_design.dart';
import 'onepoint_icon.dart';

class OnepointBottomBar extends StatelessWidget {
  const OnepointBottomBar(
      {super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;
  static const _names = ['home', 'feed', 'upload', 'chat', 'profile'];
  static const _labels = ['홈', '피드', '업로드', '채팅', '마이페이지'];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Center(
          heightFactor: 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: OnepointDesign.lime.withValues(alpha: .14),
                    blurRadius: 12),
              ],
            ),
            child: Row(
              children: List.generate(
                  5,
                  (index) => Expanded(
                        child: Semantics(
                          label: _labels[index],
                          button: true,
                          selected: currentIndex == index,
                          child: Tooltip(
                            message: _labels[index],
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onTap(index),
                              child: SizedBox(
                                height: 48,
                                child: Center(
                                    child: OnepointIcon(
                                  'nav-${_names[index]}-${currentIndex == index ? 'active' : 'idle'}',
                                  width: 48,
                                  height: 46,
                                )),
                              ),
                            ),
                          ),
                        ),
                      )),
            ),
          ),
        ),
      );
}
