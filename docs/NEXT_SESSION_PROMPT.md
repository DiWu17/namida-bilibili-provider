# Next Session Prompt

把下面整段内容复制给新会话。

---

项目路径：

```text
D:\python\namida-bilibili-provider
```

先阅读：

```text
docs/INTERFACE_GAP_ANALYSIS.md
docs/NAMIDA_INTEGRATION.md
reference_patch/
```

当前项目已经完成：

```text
Stage 0-7
普通公开 Bilibili 视频播放 provider
standalone Flutter real playback
Namida reference integration analysis
```

现在要进入新的阶段：**对齐 Namida / YoutiPie 的账号与个人数据接口方案，为 Bilibili 实现独立的账号/个人数据层。**

目标不是 fork Namida，也不是重写 Namida，而是：

```text
Bilibili provider 侧把 login、cookie、账号信息、收藏夹、历史、订阅、
用户播放列表等能力做好；
未来 Namida 只需要写很薄的 adapter。
```

请参考 Namida 公开源码：

```text
https://github.com/namidaco/namida
```

重点参考这些文件和接口：

```text
lib/youtube/controller/youtube_account_controller.dart
lib/youtube/controller/youtube_playlist_controller.dart
lib/youtube/controller/youtube_subscriptions_controller.dart
lib/youtube/controller/youtube_history_controller.dart
lib/youtube/controller/youtube_info_controller.dart
lib/base/audio_handler.dart
```

以及 YoutiPie 用法：

```text
YoutiAccountManager.signIn(...)
YoutiPie.cookies
YoutiPie.activeAccountDetails
YoutiPie.userplaylist
YoutiPie.userchannel
YoutiPie.history
YoutiPie.feed
YoutiPie.search
YoutiPie.comment
YoutiPie.commentAction
YoutiPie.notificationsAction
YoutiPie.sponsorblock
YoutiPie.returnyoutubedislike
YoutiPie.potoken
```

注意：

```text
YoutiPie 是 private dependency，只用于理解接口设计。
不要把 Bilibili 数据伪装成 YouTube 数据。
不要实现 DRM / 会员 / 付费 / 地区限制绕过。
不要做浏览器 cookie 窃取。
所有认证信息必须由用户显式提供或通过正常登录流程获得。
默认 debug logging 必须关闭。
绝对不要打印 Cookie / SESSDATA / csrf / Authorization。
```

第一阶段建议实现：

```text
1. Bilibili 登录/账号基础
   - BilibiliAuthProvider 扩展
   - CookieStore
   - BilibiliAccountSession
   - getCurrentAccount()
   - signOut()
   - setAnonymous()
   - cookie 校验 / 过期处理

2. 用户信息
   - x/web-interface/nav
   - x/space/myinfo
   - 当前用户 mid / name / avatar / 登录状态
   - 账号切换接口

3. 收藏夹
   - 解析收藏夹链接
     https://space.bilibili.com/<mid>/favlist?fid=<id>&ftype=create
   - 获取收藏夹列表
   - 获取收藏夹视频
   - 映射为 OnlineMedia / OnlineMediaPart
   - 支持分页
   - 支持收藏/取消收藏普通视频

4. 历史记录
   - 获取当前账号历史
   - 映射为 OnlineMedia
   - 可选 mark watched

5. 订阅 / 关注
   - 获取关注列表
   - 获取关注 UP 主
   - 获取 UP 主投稿或动态（如果需要）

6. 用户播放列表
   - 获取用户创建的播放列表 / 合集
   - 获取播放列表内容
   - 映射为 OnlineMedia 列表
```

架构要求：

```text
provider-neutral DTO 继续放在 online_media_provider
Bilibili 账号 API 实现放在 bilibili_provider
HTTP 调用放在 BilibiliClient 或新的 BilibiliAccountClient
parser 放在 bilibili_provider/lib/src/parser
fixtures 放在 bilibili_provider/test/fixtures
不要破坏现有 BilibiliProvider.resolve/getPlayback 行为
```

推荐新增文档：

```text
docs/BILIBILI_ACCOUNT_LAYER.md
docs/INTERFACE_GAP_ANALYSIS.md   # 持续更新
```

推荐新增 package 或目录二选一：

```text
packages/bilibili_provider/lib/src/account/
```

或：

```text
packages/bilibili_account/
```

不要一次实现所有搜索、评论、弹幕、直播、番剧、下载和账户同步。

按照 Stage 方式推进并每阶段报告：

```text
Stage
Implemented
Files changed
Tests
Observed behavior
Problems
Next step
```

测试要求：

```text
普通 offline tests 不访问网络
online tests 继续使用 @Tags(['online'])
不要每次 commit 都强制依赖 Bilibili 网络
```

安全要求：

```text
默认匿名
用户显式提供 cookie 或登录后才走认证接口
Cookie 不写入 git
Cookie 不写入日志
Cookie 不进入异常 message
只访问用户正常有权访问的内容
```

请先阅读 `docs/INTERFACE_GAP_ANALYSIS.md`，然后：

```text
1. 检查当前仓库结构
2. 确认哪些接口已完成 / 未完成
3. 设计 BilibiliAccountClient 和 DTO
4. 优先实现 CookieStore + 当前账号信息 + 收藏夹
5. 写 offline fixture tests
6. 报告第一阶段
```
