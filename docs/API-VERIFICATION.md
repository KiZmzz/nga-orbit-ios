# NGA 接口实测记录

核查日期：2026-09-07。此文档严格区分实际验证和历史资料。实现是原创 Swift 代码，没有复制 MNGA 实现或引入其 Rust 组件。

## 资料与维护状态

| 来源 | 最近提交 | 用途 |
| --- | --- | --- |
| [wolfcon/NGA-API-Documents](https://github.com/wolfcon/NGA-API-Documents) | 2021-04-20 | 历史 App API 和网页登录入口 |
| [AgMonk/nga-api-doc](https://github.com/AgMonk/nga-api-doc/blob/main/README_v2.md) | 2023-08-07 | PHP 接口、编码、响应结构 |
| [MNGA](https://github.com/BugenZhao/MNGA/commits/main/) | 2026-08-05 | 近期接口变更的研究参考；无许可，不作为代码底座 |
| [open-nga](https://github.com/mlzzen/open-nga) | 2026-08-12 | Android 对照参考 |

MNGA 2026 年 3 月调整部分 JSON 接口，7 月迁移默认站点到 `bbs.nga.cn`，8 月将部分 `img*.nga.178.com` 图片主机迁移到 `img*.nga.cn`。原型仅采用公开可观察的协议事实，自行实现。

## 实际请求

三个域名依次独立匿名探测，不自动跨域携带 Cookie：

```text
https://bbs.nga.cn/thread.php?fid=414&page=1&__output=11
https://ngabbs.com/thread.php?fid=414&page=1&__output=11
https://nga.178.com/thread.php?fid=414&page=1&__output=11
```

| 项目 | 结果 | 结论 |
| --- | --- | --- |
| 三个域名匿名主题列表 | HTTP 403 | 不可认定为接口失效 |
| bbs.nga.cn 错误正文 | `error` 第一项为 `15:访客不能直接访问` | 应通过正常网页流程完成访客验证 / 登录 |
| Content-Type | `text/json;charset=UTF-8` | 不应只接受 application/json |
| Swift 探针 | 同样返回访问验证提示 | 原生网络可达，未验证已登录读帖成功 |
| iOS 原生构建 | 通过 | SwiftUI / WebKit / NGAKit 可链接 |
| 真机签名、安装、启动 | 通过，iPhone 16 / iOS 27 | 已观察到首页正常渲染 |
| 兼容解析测试 | 10 项通过 | 合成输入验证，不代表线上全部格式已覆盖 |

没有保存真实用户 Cookie、账号密码、包含网页挑战内容的完整原始响应。访客验证脚本交由 WebKit 正常执行，网络层不执行 JavaScript、不计算或伪造官方 App 签名。

## 原型使用的协议

### 列表

```text
GET /thread.php
fid=<Int，可为负数>
page=<从 1 开始>
__output=11
__inchst=UTF8
```

### 帖子详情

```text
GET /read.php
tid=<主题 ID>
page=<从 1 开始>
__output=11
__inchst=UTF8
```

### 用户中心

- `app_api.php?__lib=user&__act=detail|subjects|replys`：用户资料、发布主题与回复。
- `nuke.php?__lib=topic_favor_v2&__act=list_folder&uid=<uid>`：他人公开收藏夹；收藏夹内容仍由 `thread.php?favor=<folder>` 读取。
- `nuke.php?__lib=follow_v2&__act=follow`：关注/取关用户。
- `nuke.php?__lib=message&__act=message`：发起私信，以及查询/修改私信黑名单。

用户接口没有返回的资料不在客户端推导。关注、私信和拉黑要求当前网页会话已登录；公开收藏夹受用户自身的公开设置限制。

网络请求使用可识别的 `NGAReaderPrototype/0.1` User-Agent，不伪装成官方客户端。Cookie 来自当前选择域名的 WebKit 存储，并经过域名、有效期检查。跨主机或降级 HTTP 的网络重定向被拒绝，不把凭据发往第三方站点。

### 网页会话

访客验证加载所选 NGA 主站。登录入口来自历史文档：

```text
/nuke.php?__lib=login&__act=account&login
```

完整登录流程仍需用户在真机操作验证。`ngaPassportUid` 与 `ngaPassportCid` 非空只用于显示「已读取登录会话」，不据此宣称服务端认证成功。网页登录没有读取密码字段。

## 解析策略

- 输出优先 UTF-8；响应指定 GBK / GB18030 时使用 GB18030 解码。`__inchst=UTF8` 仅影响输入。
- 支持 `data` 外层对象，以及直接包含 `__T` / `__R` 的响应。
- 数字键字典按数字顺序遍历，兼容数组。主题 ID 去重。
- 仅处理已知脚本前缀、对象裸键和字符串内控制字符；不对远程文本使用 eval，也不全局删除制表符。
- 空数据和解析失败分别处理；缺少 `__T` / `__R` 会报错，不生成空白成功状态。
- 匿名作者显示「匿名用户」。时间戳按秒解释。
- 图片支持完整 HTTP(S) 地址和 `./mon_...` 附件路径；图片地址升级 HTTPS。未知 BBCode 保留可见文字。
- 分页按响应中的条数元数据判断；缺失时暂用列表 35 / 回复 20 的历史默认值，待真实样本校准。

## 下一次真机验证

### 真机反馈：首次安装联网

首次安装启动后，用户在网页验证中遇到系统「似乎已断开与互联网的连接」，截图显示 5G。此报错来自设备网络层，不是 NGA 的 HTTP 403；仅凭信号图标不能证明 App 已获得联网权限。

已增加启动时原生 HEAD 请求（无 Cookie）、`NWPathMonitor` 路径状态、`CTCellularData` 权限状态。系统首次授权弹窗由 iOS 决定；App 不会伪装系统弹窗或修改权限。确认被系统限制时提示前往 App 设置；网页提供重新加载，联网恢复后自动重试。相关 API：[Apple CTCellularData](https://developer.apple.com/documentation/coretelephony/ctcellulardata/restrictedstate)。

更新后在同一 iPhone 真机启动并读取无敏感信息的调试输出，得到 `NGA connectivity: HTTP 403`。确认手机 App 到站点的网络请求已经可达；这不是登录成功，也不是帖子接口成功。尚未直接观察到 iOS 首次授权框（系统可能已记录权限），不能把实现了启动请求等同于复现了首次安装弹窗。

### 尚待完成的会话验证

1. 网页访客验证后读一个公开版块。
2. 登录后读需要账号权限的版块，并核验进程重启后的会话恢复。
3. 对照网页核验标题、作者、回复数量、楼层、第二页和最后一页。
4. 选择有中文、嵌套引用、图片、匿名楼层的主题验证正文。
5. 在「清除本机 NGA 会话」后确认已登录内容不再能靠本地会话访问。

如访问依然失败，下一步记录脱敏的 HTTP 状态、顶层字段名和解析错误，不输出 Cookie 或整段个人帖子内容。不要将旧文档的所有 API 标记为当前可用。
