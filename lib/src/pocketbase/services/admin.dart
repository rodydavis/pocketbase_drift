import '../../../pocketbase_drift.dart';
import 'service.dart';

class $AdminsService extends $Service<AdminModel> implements AdminService {
  $AdminsService($PocketBase client) : super(client, 'admin');

  late final _base = AdminService(client);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  @override
  AdminModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  @override
  Future<AdminAuth> authWithPassword(
    String email,
    String password, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authWithPassword(
      email,
      password,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> confirmPasswordReset(
    String passwordResetToken,
    String password,
    String passwordConfirm, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmPasswordReset(
      passwordResetToken,
      password,
      passwordConfirm,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<AdminAuth> refresh({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.refresh(
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> requestPasswordReset(
    String email, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestPasswordReset(
      email,
      body: body,
      query: query,
      headers: headers,
    );
  }
}
