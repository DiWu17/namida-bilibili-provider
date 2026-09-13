import 'dart:async';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:flutter/material.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'bilibili_format.dart';

/// Referer required by Bilibili image CDNs.
const Map<String, String> _imageHeaders = <String, String>{
  'Referer': 'https://www.bilibili.com/',
};

/// Account panel for the standalone player.
///
/// Owns the interactive parts of the account layer: restoring a saved login,
/// signing in with a pasted cookie header, refreshing the profile, switching to
/// anonymous, signing out, and deleting the saved cookie file.
///
/// It never displays a cookie value. The dialog only reports which cookie
/// *names* were recognized, because names are not credentials.
class BilibiliAccountCard extends StatefulWidget {
  const BilibiliAccountCard({
    super.key,
    required this.manager,
    required this.cookieStore,
    required this.storageDescription,
  });

  final BilibiliAccountManager manager;

  /// Runtime switch that decides whether the manager may persist cookies.
  final ConditionalBilibiliCookieStore cookieStore;

  /// Human-readable location of the cookie file, shown in the login dialog.
  final String storageDescription;

  @override
  State<BilibiliAccountCard> createState() => _BilibiliAccountCardState();
}

class _BilibiliAccountCardState extends State<BilibiliAccountCard> {
  StreamSubscription<BilibiliAccountSession>? _subscription;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.manager.onAccountChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    unawaited(_restore());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      await widget.manager.restore();
      if (!widget.manager.isAnonymous) {
        await widget.manager.getCurrentAccount(forceRefresh: true);
      }
    } on OnlineMediaException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = '无法读取已保存的登录状态。';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.manager.isAnonymous) {
        await widget.manager.restore();
      } else {
        await widget.manager.getCurrentAccount(forceRefresh: true);
      }
    } on OnlineMediaException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = '刷新账号信息失败。';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _signIn() async {
    await showBilibiliLoginDialog(
      context,
      manager: widget.manager,
      cookieStore: widget.cookieStore,
      storageDescription: widget.storageDescription,
    );
  }

  Future<void> _setAnonymous() async {
    await widget.manager.setAnonymous();
  }

  Future<void> _signOut() async {
    await widget.manager.signOut();
  }

  Future<void> _clearStoredCookies() async {
    await widget.manager.signOutAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = widget.manager;
    final account = manager.activeAccountDetails;
    final validity = manager.cookieValidity;
    final signedIn = !manager.isAnonymous;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Avatar(account: account),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        account?.name ?? (signedIn ? '已登录' : '未登录（匿名访问）'),
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(manager),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: '账号操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'refresh':
                          unawaited(_refreshProfile());
                        case 'anonymous':
                          unawaited(_setAnonymous());
                        case 'signOut':
                          unawaited(_signOut());
                        case 'clear':
                          unawaited(_clearStoredCookies());
                      }
                    },
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'refresh',
                        child: Text('刷新账号信息'),
                      ),
                      if (signedIn)
                        const PopupMenuItem<String>(
                          value: 'anonymous',
                          child: Text('继续浏览但不再发送 Cookie'),
                        ),
                      if (signedIn)
                        const PopupMenuItem<String>(
                          value: 'signOut',
                          child: Text('退出当前账号'),
                        ),
                      const PopupMenuItem<String>(
                        value: 'clear',
                        child: Text('清除已保存的 Cookie 并退出'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: Text(signedIn ? '换一个账号登录' : '登录'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '公开视频不需要登录。登录后可以浏览你自己的收藏夹。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (validity.requiresSignIn) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '登录已失效，请重新登录。',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  static String _subtitle(BilibiliAccountManager manager) {
    if (manager.isAnonymous) {
      return '匿名：请求不携带任何 Cookie';
    }
    final account = manager.activeAccountDetails;
    final mid = account?.mid ?? manager.activeSession.mid;
    final parts = <String>[
      if (mid != null) 'mid $mid',
      manager.cookieValidity.state.name,
      if (!manager.cookieValidity.isAuthenticated) '需要重新登录',
    ];
    return parts.join(' · ');
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account});

  final BilibiliAccountInfo? account;

  @override
  Widget build(BuildContext context) {
    final avatar = account?.avatar;
    if (avatar == null) {
      return const CircleAvatar(radius: 22, child: Icon(Icons.person_outline));
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.black12,
      foregroundImage: NetworkImage(avatar.toString(), headers: _imageHeaders),
      child: const Icon(Icons.person_outline),
    );
  }
}

/// Login dialog offering Bilibili's normal scan-to-login flow, plus a manual
/// cookie fallback for cases where scanning is not possible.
///
/// The dialog owns the interaction and calls the account layer directly, so the
/// caller only decides when to open it.
Future<void> showBilibiliLoginDialog(
  BuildContext context, {
  required BilibiliAccountManager manager,
  required ConditionalBilibiliCookieStore cookieStore,
  required String storageDescription,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _LoginDialog(
      manager: manager,
      cookieStore: cookieStore,
      storageDescription: storageDescription,
    ),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({
    required this.manager,
    required this.cookieStore,
    required this.storageDescription,
  });

  final BilibiliAccountManager manager;
  final ConditionalBilibiliCookieStore cookieStore;
  final String storageDescription;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

enum _LoginMode { qr, cookie }

class _LoginDialogState extends State<_LoginDialog> {
  final TextEditingController _controller = TextEditingController();

  _LoginMode _mode = _LoginMode.qr;
  bool _remember = true;

  // Manual path.
  bool _submitting = false;
  String? _cookieError;

  // Scan path.
  bool _qrCancelled = false;
  bool _qrRunning = false;
  BilibiliQrLoginStatus? _qrStatus;
  String? _qrError;

  @override
  void initState() {
    super.initState();
    unawaited(_startQrLogin());
  }

  @override
  void dispose() {
    // Stops the polling loop in the account layer.
    _qrCancelled = true;
    _controller.dispose();
    super.dispose();
  }

  /// Applies the "remember" choice before either path persists anything.
  void _applyRemember() {
    // While false, the manager's store writes are dropped, so "do not remember"
    // cannot leak to disk.
    widget.cookieStore.persist = _remember;
  }

  Future<void> _startQrLogin() async {
    setState(() {
      _qrRunning = true;
      _qrError = null;
      _qrStatus = null;
    });
    _qrCancelled = false;
    _applyRemember();

    try {
      final session = await widget.manager.signInWithQrCode(
        pollInterval: const Duration(seconds: 2),
        timeout: const Duration(minutes: 3),
        isCancelled: () => _qrCancelled,
        onProgress: (status) {
          if (mounted) {
            setState(() {
              _qrStatus = status;
            });
          }
        },
      );
      if (!mounted) {
        return;
      }
      if (session != null) {
        Navigator.of(context).pop();
      }
    } on OnlineMediaException catch (error) {
      // Provider messages are fixed text plus platform codes; no credentials.
      if (mounted) {
        setState(() {
          _qrError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _qrError = '扫码登录失败，请检查网络后重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _qrRunning = false;
        });
      }
    }
  }

  Future<void> _submitCookie() async {
    final cookies = BilibiliCookies.fromUserInput(_controller.text);
    if (!cookies.hasSessionToken) {
      setState(() {
        _cookieError = '没有识别到 SESSDATA，请检查是否粘贴了完整的 Cookie。';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _cookieError = null;
    });
    _applyRemember();

    try {
      await widget.manager.signInWithCookies(cookies);
      await widget.manager.getCurrentAccount(forceRefresh: true);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on OnlineMediaException catch (error) {
      if (mounted) {
        setState(() {
          _cookieError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cookieError = '登录请求失败，请检查网络后重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  bool get _busy => _submitting || _qrRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('登录 Bilibili'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<_LoginMode>(
                segments: const <ButtonSegment<_LoginMode>>[
                  ButtonSegment<_LoginMode>(
                    value: _LoginMode.qr,
                    icon: Icon(Icons.qr_code_2),
                    label: Text('扫码登录'),
                  ),
                  ButtonSegment<_LoginMode>(
                    value: _LoginMode.cookie,
                    icon: Icon(Icons.key_outlined),
                    label: Text('手动输入 Cookie'),
                  ),
                ],
                selected: <_LoginMode>{_mode},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() {
                        _mode = selection.first;
                      }),
              ),
              const SizedBox(height: 16),
              if (_mode == _LoginMode.qr)
                _buildQrSection(theme)
              else
                _buildCookieSection(theme),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _remember = value;
                      }),
                title: const Text('保存到本机（下次启动自动登录）'),
                subtitle: Text(
                  _remember
                      ? '明文保存在：${widget.storageDescription}'
                      : '仅本次运行有效，不会写入磁盘',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_mode == _LoginMode.cookie)
          FilledButton(
            onPressed: _busy || !_parsedCookies.hasSessionToken
                ? null
                : _submitCookie,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
      ],
    );
  }

  BilibiliCookies get _parsedCookies =>
      BilibiliCookies.fromUserInput(_controller.text);

  Widget _buildQrSection(ThemeData theme) {
    final status = _qrStatus;
    final login = status?.login;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '用哔哩哔哩手机客户端「扫一扫」，并在手机上确认。'
          '本应用不会接触你的密码，也不会读取浏览器 Cookie。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Center(
          child: login == null
              ? const SizedBox.square(
                  dimension: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: QrImageView(
                    data: login.uri.toString(),
                    size: 200,
                    backgroundColor: Colors.white,
                    // The QR content is a login ticket, so it is never logged
                    // and never rendered as text.
                    semanticsLabel: 'Bilibili 登录二维码',
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _qrStageLabel(status),
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  _qrError != null ||
                      status?.stage == BilibiliQrLoginStage.failed
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
        ),
        if (_qrRunning) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_qrError != null ||
            (status != null &&
                status.isTerminal &&
                !status.isConfirmed)) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_startQrLogin()),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新二维码'),
            ),
          ),
        ],
      ],
    );
  }

  String _qrStageLabel(BilibiliQrLoginStatus? status) {
    if (_qrError != null) {
      return _qrError!;
    }
    if (status == null) {
      return '正在获取二维码…';
    }
    switch (status.stage) {
      case BilibiliQrLoginStage.pending:
        return '请使用哔哩哔哩客户端扫描二维码';
      case BilibiliQrLoginStage.scanned:
        return '已扫码，请在手机上确认登录';
      case BilibiliQrLoginStage.confirmed:
        return '登录成功';
      case BilibiliQrLoginStage.expired:
        return status.message ?? '二维码已过期，请点击刷新';
      case BilibiliQrLoginStage.failed:
        return status.message ?? '扫码登录失败，请点击刷新';
    }
  }

  Widget _buildCookieSection(ThemeData theme) {
    final cookies = _parsedCookies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '只有扫码不可用时才需要这样做：在你自己的浏览器里登录后，打开开发者工具 → '
          'Network → 任意 api.bilibili.com 请求 → Request Headers → 复制 Cookie 的值。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 4,
          minLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {
            _cookieError = null;
          }),
          decoration: const InputDecoration(
            labelText: 'Cookie',
            hintText: 'SESSDATA=...; bili_jct=...; DedeUserID=...',
            helperText: '支持整行粘贴、多行粘贴、带 Cookie: 前缀或引号',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (cookies.isEmpty)
          Text('尚未识别到任何 Cookie。', style: theme.textTheme.bodySmall)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '识别到：${cookies.values.keys.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
              if (!cookies.hasSessionToken)
                Text(
                  '缺少 SESSDATA：无法登录。',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (cookies.hasSessionToken && !cookies.hasCsrfToken)
                Text(
                  '缺少 bili_jct：可以浏览个人数据，但不能收藏/取消收藏。',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        if (_cookieError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_cookieError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

/// Favorite-folder browser for the signed-in account.
///
/// Loading is explicit (button) or triggered by a sign-in event; nothing is
/// fetched while anonymous.
class BilibiliFavoritesCard extends StatefulWidget {
  const BilibiliFavoritesCard({
    super.key,
    required this.manager,
    required this.onPlay,
    this.pageSize = 20,
  });

  final BilibiliAccountManager manager;

  /// Called with a provider-neutral item; the parent resolves the CID and plays.
  final ValueChanged<OnlineMedia> onPlay;

  final int pageSize;

  @override
  State<BilibiliFavoritesCard> createState() => _BilibiliFavoritesCardState();
}

class _BilibiliFavoritesCardState extends State<BilibiliFavoritesCard> {
  StreamSubscription<BilibiliAccountSession>? _subscription;
  List<BilibiliFavoriteFolder>? _folders;
  BilibiliFavoriteFolder? _selected;
  List<OnlineMedia> _items = const <OnlineMedia>[];
  int _loadedPages = 0;
  int _hiddenInvalid = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.manager.onAccountChanged.listen((session) {
      if (!mounted) {
        return;
      }
      setState(_resetLists);
      if (!session.isAnonymous) {
        unawaited(_loadFolders());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _resetLists() {
    _folders = null;
    _selected = null;
    _items = const <OnlineMedia>[];
    _loadedPages = 0;
    _hiddenInvalid = 0;
    _hasMore = false;
    _error = null;
  }

  int? get _mid =>
      widget.manager.activeAccountDetails?.mid ??
      widget.manager.activeSession.mid;

  Future<void> _loadFolders() async {
    final mid = _mid;
    if (mid == null) {
      setState(() {
        _error = '请先登录。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final folders = await widget.manager.client.getCreatedFavoriteFolders(
        mid: mid,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _folders = folders;
        _selected = null;
        _items = const <OnlineMedia>[];
        _loadedPages = 0;
        _hiddenInvalid = 0;
        _hasMore = false;
      });
    } on OnlineMediaException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '加载收藏夹失败，请检查网络。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openFolder(BilibiliFavoriteFolder folder) async {
    setState(() {
      _selected = folder;
      _items = const <OnlineMedia>[];
      _loadedPages = 0;
      _hiddenInvalid = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final folder = _selected;
    if (folder == null) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.manager.client.getFavoriteResources(
        mediaId: folder.mediaId,
        page: _loadedPages + 1,
        pageSize: widget.pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = <OnlineMedia>[..._items, ...page.media];
        _hiddenInvalid += page.entries.length - page.media.length;
        _loadedPages = page.page;
        _hasMore = page.hasMore;
      });
    } on OnlineMediaException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '加载收藏内容失败，请检查网络。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = widget.manager;
    final folders = _folders;
    final selected = _selected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('收藏夹', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    manager.isAnonymous ? '登录后可浏览' : 'mid ${_mid ?? '?'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading || manager.isAnonymous
                      ? null
                      : _loadFolders,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (folders != null) ...<Widget>[
              const SizedBox(height: 8),
              if (folders.isEmpty) const Text('这个账号还没有收藏夹。'),
              for (final folder in folders)
                ListTile(
                  dense: true,
                  selected: selected?.mediaId == folder.mediaId,
                  leading: Icon(
                    folder.isPublic ? Icons.folder_open : Icons.lock_outline,
                  ),
                  title: Text(folder.title, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${folder.mediaCount} 个内容'),
                  onTap: _loading ? null : () => unawaited(_openFolder(folder)),
                ),
            ],
            if (selected != null) ...<Widget>[
              const Divider(height: 24),
              Text(
                '${selected.title}（已加载 ${_items.length} 个'
                '${_hiddenInvalid > 0 ? '，隐藏 $_hiddenInvalid 个失效内容' : ''}）',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              if (_items.isEmpty && !_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('这个收藏夹没有可播放的内容。'),
                ),
              for (final media in _items)
                ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 64,
                    child: media.thumbnail == null
                        ? const Icon(Icons.movie_outlined)
                        : Image.network(
                            media.thumbnail.toString(),
                            headers: _imageHeaders,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.movie_outlined),
                          ),
                  ),
                  title: Text(media.title, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${media.artist ?? '未知 UP'} · '
                    '${formatDuration(media.duration)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '载入播放器',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => widget.onPlay(media),
                  ),
                  onTap: () => widget.onPlay(media),
                ),
              if (_hasMore) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading ? null : () => unawaited(_loadMore()),
                  child: const Text('加载更多'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
