import 'package:flutter/material.dart';
import '../widgets/onepoint_bottom_bar.dart';
import 'main_screen.dart'; // 1. 새로 만든 홈 대시보드
import 'shortform_feed_screen.dart'; // 2. 숏폼 피드
import 'video_upload_screen.dart'; // 3. 영상 업로드
import 'chat_list_screen.dart'; // 4. 채팅 목록
import 'my_page_screen.dart'; // 5. 마이페이지

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack을 사용하면 탭을 이동해도 화면 상태가 유지됩니다.
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const MainScreen(),
          ShortformFeedScreen(isActive: _currentIndex == 1),
          const VideoUploadScreen(),
          ChatListScreen(onFindCoach: () => setState(() => _currentIndex = 0)),
          const MyPageScreen(),
        ],
      ),
      bottomNavigationBar: OnepointBottomBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
