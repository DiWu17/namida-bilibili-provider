/// File-system backed Bilibili account stores.
///
/// Import this library only in applications that can use `dart:io` (desktop and
/// server). The main `package:bilibili_provider/bilibili_provider.dart` library
/// deliberately contains no `dart:io` code so it stays usable in web builds, and
/// so that importing the provider never implies writing credentials to disk.
///
/// ```dart
/// import 'package:bilibili_provider/bilibili_provider.dart';
/// import 'package:bilibili_provider/io.dart';
///
/// final store = PlainTextFileBilibiliCookieStore();
/// final manager = BilibiliAccountManager(cookieStore: store);
/// await manager.restore();
/// ```
library;

export 'src/account/bilibili_cookie_file_store.dart';
