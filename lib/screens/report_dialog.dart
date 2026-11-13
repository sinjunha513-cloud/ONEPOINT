import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportDialog extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;

  const ReportDialog({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  static const Color pitchDark = Color(0xFF070D1B);
  static const Color midnight = Color(0xFF0B132B);
  static const Color volt = Color(0xFFC6FF00);
  static const Color warningRed = Color(0xFFFF4D4D);
  static const Color warningOrange = Color(0xFFFF9F43);

  String? _selectedReason;
  final TextEditingController _detailController = TextEditingController();
  bool _isSubmitting = false;

  // 1. 즉시 영구 정지 사유 (괄호 제거)
  final List<String> _oneStrikeReasons = [
    '부적절한 언행 및 폭언·성희롱',
    '과도한 신체 접촉 및 안전 수칙 위반',
    '음주·약물 및 불법 행위',
    '허위 자격 및 프로필 정보 불일치',
  ];

  // 2. 단계별 경고 및 누적 제재 사유 (괄호 제거)
  final List<String> _threeStrikeReasons = [
    '플랫폼 외 사적 결제 및 직거래 유도',
    '사적인 연락 및 개인정보 침해',
    '노쇼 및 일방적인 시간 변경·취소',
    '불성실한 수업 진행',
  ];

  // 3. 기타 사유 (괄호 제거)
  final String _otherReason = '기타 직접 입력';

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고 사유를 선택해 주세요.')),
      );
      return;
    }

    if (_selectedReason == _otherReason &&
        _detailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기타 사유의 상세 내용을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final bool isOneStrike = _oneStrikeReasons.contains(_selectedReason);

      // Firestore에 신고 데이터 저장
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterId': currentUser?.uid ?? 'anonymous',
        'reporterEmail': currentUser?.email ?? '',
        'reportedUserId': widget.reportedUserId,
        'reportedUserName': widget.reportedUserName,
        'reason': _selectedReason,
        'detail': _detailController.text.trim(),
        'sanctionType': isOneStrike
            ? 'ONE_STRIKE_OUT'
            : (_selectedReason == _otherReason ? 'OTHER' : 'THREE_STRIKES_OUT'),
        'status': 'PENDING',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('신고가 정상적으로 접수되었습니다. 운영진 검토 후 조치됩니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 접수 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: pitchDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.reportedUserName} 유저 신고',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),

              RadioGroup<String>(
                groupValue: _selectedReason,
                onChanged: (value) {
                  setState(() => _selectedReason = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group 1: 즉시 영구 정지 (괄호 문구 제거됨)
                    _buildCategoryHeader(
                        '즉시 영구 정지 사유', warningRed, Icons.gavel),
                    const SizedBox(height: 8),
                    ..._oneStrikeReasons
                        .map((reason) => _buildRadioTile(reason, warningRed)),

                    const SizedBox(height: 16),

                    // Group 2: 단계별 경고 및 누적 제재 (괄호 문구 제거됨)
                    _buildCategoryHeader('단계별 경고 및 누적 제재 사유', warningOrange,
                        Icons.warning_amber),
                    const SizedBox(height: 8),
                    ..._threeStrikeReasons.map(
                        (reason) => _buildRadioTile(reason, warningOrange)),

                    const SizedBox(height: 16),

                    // Group 3: 기타
                    _buildCategoryHeader('기타 사유', volt, Icons.edit_note),
                    const SizedBox(height: 8),
                    _buildRadioTile(_otherReason, volt),
                  ],
                ),
              ),

              // Detailed Description Text Field
              const SizedBox(height: 12),
              TextField(
                controller: _detailController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: _selectedReason == _otherReason
                      ? '신고 사유를 상세히 입력해 주세요 (필수)'
                      : '추가적인 증빙 설명이나 참고 사항을 적어주세요 (선택)',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: midnight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: volt),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: warningRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '신고 제출하기',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String title, Color accentColor, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: accentColor, size: 16),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: accentColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRadioTile(String reason, Color activeColor) {
    final bool isSelected = _selectedReason == reason;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedReason = reason;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : midnight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: reason,
              activeColor: activeColor,
            ),
            Expanded(
              child: Text(
                reason,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
