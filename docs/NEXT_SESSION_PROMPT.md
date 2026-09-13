# Next Session Prompt

把下面整段内容复制给新会话。

---

项目路径：

```text
D:\python\namida-bilibili-provider
```

先阅读：

```text
docs/INTERFACE_REFERENCE.md
docs/BILIBILI_ACCOUNT_LAYER.md
docs/INTERFACE_GAP_ANALYSIS.md
```

当前项目已经完成：

```text
Stage 0-7
普通公开 Bilibili 视频播放 provider
standalone Flutter real playback

Stage 8   账号基础：CookieStore / BilibiliAccountSession / 当前账号 / 账号切换 / signOut / setAnonymous
Stage 9   收藏夹：favlist 链接解析、收藏夹列表、收藏夹内容分页、OnlineMedia 映射、收藏/取消收藏
Stage 9b  扫码登录（QR）+ 应用内登录/收藏夹 UI（已在 Windows 手动验证）
```

现有可用接口（不要重复实现）：

```text
BilibiliCookies / BilibiliCookieStore / BilibiliCookieStoreState / InMemoryBilibiliCookieStore
ConditionalBilibiliCookieStore / PlainTextFileBilibiliCookieStore（package:bilibili_provider/io.dart）
BilibiliAccountSession / BilibiliSessionState / BilibiliCookieValidity
BilibiliAccountAuthProvider
BilibiliAccountManager
    restore / signIn / signInWithCookies / signInWithQrCode / switchAccount
    signOut / signOutAll / setAnonymous
    getCurrentAccount / validateActiveCookies
    createMediaProvider / onAccountChanged / signedInAccounts
BilibiliQrLogin / BilibiliQrLoginStage / BilibiliQrLoginStatus
BilibiliAccountClient
    getNav / getMyInfo / generateQrLogin / pollQrLogin
    getCreatedFavoriteFolders / getFavoriteFolderInfo / getFavoriteResources
    paginateFavoriteResources / getAllFavoriteMedia / getFavoriteResourcesFromUri
    addFavorite / removeFavorite / dealFavorite
BilibiliAccountParser
BilibiliFavListUrlParser
BilibiliProvider.resolveById        # 补齐收藏夹条目的 CID
BilibiliHttpTransport               # 唯一挂载 Cookie 的位置
```

现在进入下一阶段：**继续实现账号/个人数据层的历史、关注/订阅、用户播放列表。**

不要 fork Namida，不要重写 Namida，不要依赖 youtipie。参考公开源码的接口形状：

```text
lib/youtube/controller/youtube_history_controller.dart
lib/youtube/controller/youtube_subscriptions_controller.dart
lib/youtube/controller/youtube_playlist_controller.dart
lib/youtube/controller/youtube_info_controller.dart
```

本轮建议实现：

```text
Stage 10  历史记录
  - GET x/v2/history（分页、cursor/max、business 过滤）
  - 映射为 OnlineMedia（沿用 BilibiliAccountParser.toOnlineMedia 的模式）
  - 可选 mark watched / 删除单条历史（写操作，需要 bili_jct csrf）
  - 历史条目同样没有 CID，必须走 BilibiliProvider.resolveById

Stage 11  关注 / 订阅
  - GET x/relation/followings（分页）
  - 关注 UP 主模型：mid / uname / face / sign / 认证信息 / 粉丝数
  - 可选：UP 主投稿/动态列表 -> OnlineMedia
  - 可选：关注 / 取关（写操作，需要 csrf）

Stage 12  用户播放列表 / 合集
  - GET x/polymer/web-space/seasons_series_list
  - GET x/polymer/web-space/seasons_archives_list
  - 映射为 OnlineMedia 列表
```

架构要求：

```text
provider-neutral DTO 继续放在 online_media_provider（尽量不改）
Bilibili 专属模型放在 bilibili_provider/lib/src/models/
HTTP 调用放进 BilibiliAccountClient，复用 BilibiliHttpTransport
parser 放在 bilibili_provider/lib/src/parser/
fixtures 放在 bilibili_provider/test/fixtures/
不要破坏 BilibiliProvider.resolve / getPlayback / resolveById 行为
新增 API 一律 additive；需要新 DTO 时放在 models/bilibili_account_api_models.dart 或新文件
```

安全要求（与 Stage 8-9 一致，测试必须覆盖）：

```text
默认匿名；只有显式 signIn 之后才带 Cookie
Cookie / SESSDATA / bili_jct / csrf 不得进入日志或异常 message
新增类型的 toString() 必须脱敏
写操作必须显式传入/读取 csrf，绝不自动重试
只访问用户自己有权访问的内容
不实现 DRM / 会员 / 付费 / 地区限制绕过
不做浏览器 cookie 窃取
```

测试要求：

```text
offline tests 不访问网络，全部使用 MockClient + fixtures
online tests 继续 @Tags(['online'])，且尽量不依赖账号 cookie
写操作要断言：无 csrf 时不发请求、csrf 不出现在异常里
分页要有 maxPages 之类的硬上限
```

Stage 报告格式：

```text
Stage
Implemented
Files changed
Tests
Observed behavior
Problems
Next step
```
