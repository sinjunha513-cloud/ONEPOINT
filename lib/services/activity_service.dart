import 'package:cloud_functions/cloud_functions.dart';

class ActivityService {
  ActivityService({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;
  static final _synced = <String>{};
  Future<void> sync(String uid) async {
    if (_synced.contains(uid)) return;
    await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable('syncMyActivity')
        .call(<String, dynamic>{});
    _synced.add(uid);
  }
}
