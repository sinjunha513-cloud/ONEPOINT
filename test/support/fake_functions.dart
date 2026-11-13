import 'package:cloud_functions/cloud_functions.dart';

typedef FunctionHandler = Future<dynamic> Function(
    String, Map<String, dynamic>);

/// Transport stub only. Authorization/domain behavior is tested in the Emulator.
class FakeFunctions implements FirebaseFunctions {
  FakeFunctions(this.handler);
  final FunctionHandler handler;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable(
          (data) => handler(name, Map<String, dynamic>.from(data as Map)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callable implements HttpsCallable {
  _Callable(this.handler);
  final Future<dynamic> Function(dynamic) handler;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      _Result<T>(await handler(parameters) as T);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}
