import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const koreaTimeZone = 'Asia/Seoul';
const koreaUtcOffset = Duration(hours: 9);

DateTime koreaNow() => DateTime.now().toUtc().add(koreaUtcOffset);

DateTime toKoreaTime(DateTime value) => value.toUtc().add(koreaUtcOffset);

DateTime koreaComponentsToUtc(
  DateTime date, {
  required int hour,
  required int minute,
}) =>
    DateTime.utc(date.year, date.month, date.day, hour - 9, minute);

DateTime? timestampDate(dynamic value) => switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime date => date,
      _ => null,
    };

const _koreanWeekdays = ['월', '화', '수', '목', '금', '토', '일'];

String formatKoreaDate(DateTime value) =>
    '${DateFormat('yyyy.MM.dd').format(value)} (${_koreanWeekdays[value.weekday - 1]})';

String formatKoreaDateTime(dynamic value, {String fallback = '일정 미정'}) {
  final date = timestampDate(value);
  if (date == null) return fallback;
  final korea = toKoreaTime(date);
  return '${formatKoreaDate(korea)} ${DateFormat('HH:mm').format(korea)} KST';
}

String formatKoreaTimeRange(dynamic start, dynamic end,
    {String fallback = '일정 미정'}) {
  final startDate = timestampDate(start);
  final endDate = timestampDate(end);
  if (startDate == null || endDate == null) return fallback;
  final koreaStart = toKoreaTime(startDate);
  final koreaEnd = toKoreaTime(endDate);
  return '${formatKoreaDate(koreaStart)} ${DateFormat('HH:mm').format(koreaStart)}'
      '–${DateFormat('HH:mm').format(koreaEnd)} KST';
}

String formatKoreaClockRange(dynamic start, dynamic end,
    {String fallback = '시간 미정'}) {
  final startDate = timestampDate(start);
  final endDate = timestampDate(end);
  if (startDate == null || endDate == null) return fallback;
  return '${DateFormat('HH:mm').format(toKoreaTime(startDate))}'
      '–${DateFormat('HH:mm').format(toKoreaTime(endDate))} KST';
}

DateTime koreaDateOnly(DateTime value) {
  final korea = toKoreaTime(value);
  return DateTime(korea.year, korea.month, korea.day);
}

bool sameKoreaDate(DateTime value, DateTime date) {
  final korea = toKoreaTime(value);
  return korea.year == date.year &&
      korea.month == date.month &&
      korea.day == date.day;
}
