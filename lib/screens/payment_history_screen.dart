import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/payment_environment.dart';
import '../services/payment_service.dart';

String paymentLabel(dynamic value) => switch (value) {
      'pending' => '결제 대기',
      'paid' => '결제 완료',
      'failed' => '결제 실패',
      'cancelled' => '취소',
      'refunded' => '전액 환불',
      'partial_refunded' => '부분 환불',
      _ => '미확인',
    };
String payoutLabel(dynamic value) => switch (value) {
      'pending' => '레슨 완료 대기',
      'ready' => '정산 가능',
      'completed' => '지급 완료',
      'held' => '정산 보류',
      'cancelled' => '정산 취소',
      _ => '미확인',
    };
String lessonPaymentLabel(dynamic value) => switch (value) {
      'pending' => '코치 수락 대기',
      'accepted' => '결제 대기',
      'confirmed' => '예약 확정',
      'completed' => '레슨 완료',
      'cancelled' => '예약 취소',
      'rejected' => '거절',
      _ => '미확인',
    };
String won(dynamic amount) =>
    '${NumberFormat('#,###').format(amount is num ? amount : 0)}원';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen(
      {super.key,
      this.adminMode = false,
      this.coachMode = false,
      this.service});
  final bool adminMode;
  final bool coachMode;
  final PaymentService? service;
  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late final _service = widget.service ?? PaymentService();
  final List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _summary;
  String? _cursor;
  String? _error;
  bool _paymentEnabled = false;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_busy || _cursor == null)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enabled = await _service.isPaymentTestEnabled();
      if (!mounted) return;
      setState(() => _paymentEnabled = enabled);
      if (!enabled) {
        setState(() {
          _payments.clear();
          _summary = null;
          _cursor = null;
        });
        return;
      }
      final result = await _service.list(cursor: more ? _cursor : null);
      final summary = widget.adminMode ? await _service.summary() : null;
      if (!mounted) return;
      setState(() {
        if (!more) _payments.clear();
        _payments.addAll((result['payments'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map)));
        _cursor = result['nextCursor'] as String?;
        _summary = summary;
      });
    } catch (error) {
      if (mounted) setState(() => _error = paymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> data) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PaymentDetailScreen(
                initial: data,
                service: _service,
                adminMode: widget.adminMode,
                coachMode: widget.coachMode)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.adminMode
                ? '결제 관리'
                : widget.coachMode
                    ? '정산 예정 내역'
                    : '나의 결제 내역'),
            actions: [
              IconButton(
                  onPressed: _busy ? null : () => _load(),
                  icon: const Icon(Icons.refresh))
            ]),
        body: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (paymentDemo)
                const Card(
                    color: Color(0xFF1A1C29),
                    child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('체험 결제 내역 · 실제 결제 및 계좌 지급 없음'))),
              if (!_busy && !_paymentEnabled && _error == null)
                const _PaymentSetupCard(),
              if (_summary != null)
                Card(
                    color: const Color(0xFF1A1C29),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('거래 현황',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              _row('결제 완료', '${_summary!['paidCount']}건'),
                              _row('총 승인 금액',
                                  won(_summary!['grossApprovedAmount'])),
                              _row('환불',
                                  '${_summary!['refundCount']}건 · ${won(_summary!['refundedAmount'])}'),
                              _row('완료 레슨 거래액',
                                  won(_summary!['completedAmount'])),
                              _row('플랫폼 수수료 합계',
                                  won(_summary!['platformFeeTotal'])),
                              _row('코치 정산 예정액',
                                  won(_summary!['coachReadyTotal'])),
                            ]))),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Text(_error!),
                      TextButton(
                          onPressed: () => _load(), child: const Text('다시 확인'))
                    ])),
              if (!_busy &&
                  _paymentEnabled &&
                  _error == null &&
                  _payments.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child:
                        Text('아직 결제 내역이 없습니다.', textAlign: TextAlign.center)),
              for (final data in _payments)
                Card(
                    color: const Color(0xFF1A1C29),
                    child: ListTile(
                        onTap: () => _open(data),
                        title: Text(
                            '${data['instructorName']} 코치 · ${won(data['amount'])}',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                style: const TextStyle(color: Colors.white70),
                                '${paymentLabel(data['paymentStatus'])} · ${payoutLabel(data['payoutStatus'])}${data['refundStatus'] == 'requested' ? '\n환불 요청 접수' : ''}')),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white54))),
              if (_busy)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator())),
              if (!_busy && _cursor != null)
                OutlinedButton(
                    onPressed: () => _load(more: true),
                    child: const Text('더 보기')),
            ])),
      );
}

class _PaymentSetupCard extends StatelessWidget {
  const _PaymentSetupCard();

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF172033),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(
                Icons.credit_card_off_rounded,
                size: 48,
                color: Color(0xFF38BDF8),
              ),
              const SizedBox(height: 14),
              const Text(
                '결제 테스트 연동 준비 중',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '현재는 토스페이먼츠 테스트 상점 키가 등록되지 않아 실제 결제와 결제 내역 조회를 실행하지 않습니다. 기존 레슨은 결제 없는 흐름으로 안전하게 처리됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1524),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Text(
                  '테스트 Client Key · Secret Key 등록 → 결제 Functions 배포 → 관리자 테스트 기능 활성화 순서로 연결됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFBAE6FD)),
                ),
              ),
            ],
          ),
        ),
      );
}

Widget _row(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          child: Text(name, style: const TextStyle(color: Colors.white60))),
      const SizedBox(width: 12),
      Expanded(child: SelectableText(value, textAlign: TextAlign.right)),
    ]));

class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen(
      {super.key,
      required this.initial,
      required this.service,
      this.adminMode = false,
      this.coachMode = false});
  final Map<String, dynamic> initial;
  final PaymentService service;
  final bool adminMode;
  final bool coachMode;
  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  late final Map<String, dynamic> _data = {...widget.initial};
  bool _busy = false;
  String? _error;
  String? _refundId;
  Future<void> _completeByAdmin() async {
    final signature =
        TextEditingController(text: _data['signatureMove'] as String? ?? '');
    double? score;
    bool attended = false;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, change) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1C29),
                  titleTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  title: const Text('레슨 완료 확인'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<double>(
                        decoration: const InputDecoration(labelText: '수강생 평가'),
                        items: [
                          for (var i = 1; i <= 5; i++)
                            DropdownMenuItem(
                                value: i.toDouble(), child: Text('$i점'))
                        ],
                        onChanged: (value) => change(() => score = value)),
                    TextField(
                        controller: signature,
                        readOnly: true,
                        decoration: const InputDecoration(
                            labelText: '코치가 등록한 시그니처 뱃지',
                            suffixIcon: Icon(Icons.lock_outline_rounded))),
                    CheckboxListTile(
                        value: attended,
                        title: const Text('실제 레슨 참여를 확인했습니다.'),
                        onChanged: (value) =>
                            change(() => attended = value ?? false)),
                    const Text(
                        '완료 후 코치 정산 예정액이 정산 가능 상태가 됩니다. 실제 계좌 지급은 하지 않습니다.'),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('닫기')),
                    FilledButton(
                        onPressed: attended &&
                                score != null &&
                                signature.text.trim().isNotEmpty
                            ? () => Navigator.pop(context, true)
                            : null,
                        child: const Text('완료 확인'))
                  ],
                )));
    final move = signature.text.trim();
    signature.dispose();
    if (approved == true && mounted) {
      await _run(() => widget.service
          .complete(_data['lessonId'] as String, score!, '', move));
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
      final status = await widget.service.status(_data['paymentId'] as String);
      if (mounted) setState(() => _data.addAll(status));
    } catch (error) {
      if (mounted) setState(() => _error = paymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund() async {
    final amount = TextEditingController(
        text: '${(_data['amount'] as num) - (_data['refundedAmount'] as num)}');
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1A1C29),
              titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              title: Text(
                  widget.adminMode || widget.coachMode ? '환불 처리' : '환불 요청'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.adminMode)
                  TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '환불 금액 (원)')),
                TextField(
                    controller: reason,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '취소 / 환불 사유')),
                const SizedBox(height: 12),
                const Text(
                    '수강생 요청은 검토 후 처리합니다. 실제 환불 상태는 서버가 PG 결과를 확인한 후 반영합니다.'),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('닫기')),
                FilledButton(
                    onPressed: () {
                      if (reason.text.trim().isNotEmpty) {
                        Navigator.pop(context, true);
                      }
                    },
                    child: const Text('진행'))
              ],
            ));
    final reasonText = reason.text.trim();
    final refundAmount = int.tryParse(amount.text);
    amount.dispose();
    reason.dispose();
    if (accepted != true || !mounted) return;
    if (widget.adminMode && refundAmount == null) {
      setState(() => _error = '정수 환불 금액을 입력해 주세요.');
      return;
    }
    await _run(() async {
      if (widget.adminMode || widget.coachMode) {
        _refundId ??=
            'r_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
        await widget.service.refund(
            _data['paymentId'] as String, _refundId!, reasonText,
            amount: widget.adminMode ? refundAmount : null);
        _refundId = null;
      } else {
        await widget.service
            .requestRefund(_data['paymentId'] as String, reasonText);
        _data['refundStatus'] = 'requested';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final refundable =
        ['paid', 'partial_refunded'].contains(_data['paymentStatus']) &&
            _data['payoutStatus'] != 'completed';
    return Scaffold(
      appBar: AppBar(title: const Text('결제 상세정보'), actions: [
        IconButton(
            onPressed: _busy ? null : () => _run(() async {}),
            icon: const Icon(Icons.refresh))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (paymentDemo)
                  const Text('체험 거래 · 실제 결제 없음',
                      style: TextStyle(color: Colors.orangeAccent)),
                const SizedBox(height: 24),
                Text(won(_data['amount']),
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(paymentLabel(_data['paymentStatus']),
                    style: const TextStyle(
                        fontSize: 18, color: Color(0xFF38BDF8))),
                const SizedBox(height: 24),
                Card(
                    color: const Color(0xFF1A1C29),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _row('레슨', '${_data['lessonId']}'),
                          _row('레슨 상태',
                              lessonPaymentLabel(_data['lessonStatus'])),
                          _row('코치',
                              '${_data['instructorName'] ?? _data['instructorUid']}'),
                          if (widget.adminMode)
                            _row('수강생',
                                '${_data['studentName'] ?? _data['studentUid']}'),
                          _row('결제 금액', won(_data['amount'])),
                          _row('환불 금액', won(_data['refundedAmount'])),
                          _row('수수료율',
                              '${(_data['platformFeeBps'] as num) / 100}%'),
                          _row(
                              '플랫폼 수수료',
                              won(_data['netPlatformFee'] ??
                                  _data['platformFee'])),
                          _row(
                              '코치 정산 예정액',
                              won(_data['netCoachAmount'] ??
                                  _data['coachAmount'])),
                          _row('정산 상태', payoutLabel(_data['payoutStatus'])),
                          _row('결제 방법', '${_data['paymentMethod'] ?? '미결제'}'),
                          _row('결제일', _date(_data['paidAt'])),
                          _row('환불일', _date(_data['refundedAt'])),
                          _row('결제번호', '${_data['paymentId']}'),
                          if (widget.adminMode)
                            _row('PG 주문번호',
                                '${_data['providerOrderId'] ?? '-'}'),
                        ]))),
                if (_data['refundStatus'] == 'requested')
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('환불 요청이 접수됐습니다. 검토 중에는 정산이 보류됩니다.')),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.orangeAccent))),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (widget.adminMode &&
                      _data['lessonStatus'] == 'confirmed' &&
                      _data['payoutStatus'] != 'held')
                    OutlinedButton(
                        onPressed: _completeByAdmin,
                        child: const Text('관리자 레슨 완료 확인')),
                  if (refundable &&
                      ((!widget.adminMode && !widget.coachMode) ||
                          _data['lessonStatus'] == 'confirmed'))
                    FilledButton(
                        onPressed: _refund,
                        child: Text(widget.adminMode
                            ? '전액 / 부분 환불'
                            : widget.coachMode
                                ? '코치 취소 · 전액 환불'
                                : '환불 요청')),
                  if (_data['paymentStatus'] == 'pending' ||
                      _data['payoutStatus'] == 'held')
                    OutlinedButton(
                        onPressed: () => _run(() async {
                              await widget.service
                                  .reconcile(_data['paymentId'] as String);
                            }),
                        child: const Text('서버 결제 / 환불 상태 재확인')),
                ],
              ]))),
    );
  }

  String _date(dynamic value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    return date == null
        ? '-'
        : DateFormat('yyyy.MM.dd HH:mm').format(date.toLocal());
  }
}
