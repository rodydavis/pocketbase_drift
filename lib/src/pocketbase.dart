part of '../pocketbase_drift.dart';

PocketBase createPocketBaseClient(
  String url, {
  String lang = "en-US",
  AuthStore? authStore,
}) {
  return PocketBase(
    url,
    lang: lang,
    authStore: authStore,
    httpClientFactory: createHttpClient,
  );
}
