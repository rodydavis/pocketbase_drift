import 'dart:convert';

/// An unsigned JWT for tests with a mock server. `authStore.isValid` and
/// `$PocketBase.hasExpiredSession` read only its `exp` claim: by default
/// one hour from now; pass a past [expires] for an expired session.
String fakeJwt({String id = 'account', DateTime? expires}) {
  String part(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = (expires ?? DateTime.now().add(const Duration(hours: 1)))
          .millisecondsSinceEpoch ~/
      1000;
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'id': id, 'type': 'auth', 'exp': exp}),
    'unsigned',
  ].join('.');
}
