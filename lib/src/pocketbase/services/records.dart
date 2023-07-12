import 'dart:async';

import 'package:drift/drift.dart';

import '../../../pocketbase_drift.dart';

class $RecordService extends $Service<RecordModel> implements RecordService {
  $RecordService($PocketBase client, String collection)
      : super(client, collection);

  late final _base = RecordService(client, service);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  @override
  RecordModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  Selectable<RecordModel> search(String query) {
    return client.db.search(query, service: service).map(
          (p0) => itemFactoryFunc({
            ...p0.data,
            'created': p0.created,
            'updated': p0.updated,
            'id': p0.id,
          }),
        );
  }

  Selectable<RecordModel> pending() {
    return client.db
        .$query(service, filter: 'synced = false')
        .map(itemFactoryFunc);
  }

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    int? batch,
  }) async* {
    final items = await pending().get();
    final total = items.length;
    yield RetryProgressEvent(current: 0, total: total);
    for (var i = 0; i < total; i++) {
      final item = items[i];
      try {
        final id = item.id;
        if (item.data['deleted'] == true) {
          await delete(
            id,
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        } else if (item.data['new'] == true) {
          await create(
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        } else {
          await update(
            id,
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        }
      } catch (e) {
        print('error retry $item: $e');
      }
      yield RetryProgressEvent(current: i + 1, total: total);
    }
    yield RetryProgressEvent(current: total, total: total);
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback,
  ) {
    return _base.subscribe(topic, (e) {
      onEvent(e);
      callback(e);
    });
  }

  @override
  Future<void> unsubscribe([String topic = ""]) {
    return _base.unsubscribe(topic);
  }

  Future<void> onEvent(RecordSubscriptionEvent e) async {
    if (e.record != null) {
      if (e.action == 'create') {
        await client.db.$create(
          service,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'update') {
        await client.db.$update(
          service,
          e.record!.id,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'delete') {
        await client.db.$delete(
          service,
          e.record!.id,
        );
      }
    }
  }

  Stream<RecordModel?> watchRecord(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<RecordModel?>(
      onListen: () async {
        await getFullList(fetchPolicy: fetchPolicy);
        if (fetchPolicy.isNetwork) {
          await subscribe(id, (e) {});
        }
      },
      onCancel: () async {
        if (fetchPolicy.isNetwork) {
          await unsubscribe(id);
        }
      },
    );
    final stream = client.db
        .$query(
          service,
          filter: "id = '$id'",
        )
        .map(itemFactoryFunc)
        .watchSingleOrNull();
    controller.addStream(stream);
    return controller.stream;
  }

  Stream<List<RecordModel>> watchRecords({
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<List<RecordModel>>(
      onListen: () async {
        await getFullList(fetchPolicy: fetchPolicy);
        if (fetchPolicy.isNetwork) {
          await subscribe('*', (e) {});
        }
      },
      onCancel: () async {
        if (fetchPolicy.isNetwork) {
          await unsubscribe('*');
        }
      },
    );
    final stream = client.db.$query(service).map(itemFactoryFunc).watch();
    controller.addStream(stream);
    return controller.stream;
  }

  @override
  Future<RecordAuth> authRefresh({
    String? expand,
    String? fields,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authRefresh(
      expand: expand,
      fields: fields,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<RecordAuth> authWithOAuth2(
    String providerName,
    OAuth2UrlCallbackFunc urlCallback, {
    List<String> scopes = const [],
    Map<String, dynamic> createData = const {},
    String? expand,
    String? fields,
  }) {
    return _base.authWithOAuth2(
      providerName,
      urlCallback,
      scopes: scopes,
      createData: createData,
      expand: expand,
      fields: fields,
    );
  }

  @override
  Future<RecordAuth> authWithOAuth2Code(
    String provider,
    String code,
    String codeVerifier,
    String redirectUrl, {
    Map<String, dynamic> createData = const {},
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    return _base.authWithOAuth2Code(
      provider,
      code,
      codeVerifier,
      redirectUrl,
      createData: createData,
      body: body,
      query: query,
      headers: headers,
      expand: expand,
      fields: fields,
    );
  }

  @override
  Future<RecordAuth> authWithPassword(
    String usernameOrEmail,
    String password, {
    String? expand,
    String? fields,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authWithPassword(
      usernameOrEmail,
      password,
      expand: expand,
      fields: fields,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  String get baseCollectionPath => _base.baseCollectionPath;

  @override
  Future<void> confirmEmailChange(
    String emailChangeToken,
    String userPassword, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmEmailChange(
      emailChangeToken,
      userPassword,
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
  Future<void> confirmVerification(
    String verificationToken, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmVerification(
      verificationToken,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<AuthMethodsList> listAuthMethods({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.listAuthMethods(
      query: query,
      headers: headers,
    );
  }

  @override
  Future<List<ExternalAuthModel>> listExternalAuths(
    String recordId, {
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.listExternalAuths(
      recordId,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> requestEmailChange(
    String newEmail, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestEmailChange(
      newEmail,
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

  @override
  Future<void> requestVerification(
    String email, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestVerification(
      email,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> unlinkExternalAuth(
    String recordId,
    String provider, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.unlinkExternalAuth(
      recordId,
      provider,
      body: body,
      query: query,
      headers: headers,
    );
  }
}
