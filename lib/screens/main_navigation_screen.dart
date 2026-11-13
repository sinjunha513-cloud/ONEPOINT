import 'package:flutter/material.dart';
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
          const ChatListScreen(),
          const MyPageScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF0B132B), // 미드나잇 블루 배경
          selectedItemColor: const Color(0xFFC6FF00), // 볼트 라임 선택 색상
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.bolt),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              label: '피드',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline),
              label: '업로드',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: '채팅',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: '마이페이지',
            ),
          ],
        ),
      ),
    );
  }
}
