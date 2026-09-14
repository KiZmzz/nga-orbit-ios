# NGA Orbit UI 设计图生成任务书

## 1. 任务目标

为一款原生 iOS NGA 论坛客户端设计完整、高保真的产品 UI。

生成结果将作为后续 SwiftUI 实现的正式设计基准，不是情绪板、概念草图或营销海报。所有页面、组件、间距和状态都必须真实可实现，并能支持论坛高信息密度与长时间阅读。

请先生成一张统一的 Design Overview，展示 4 个核心页面；风格确认后，再分别生成每个页面的完整大图与状态变体。

## 2. 产品背景

- 产品名称：`NGA Orbit`
- 平台：原生 iOS，最低 iOS 17
- 技术：SwiftUI
- 定位：克制、专注、适合长时间阅读的 NGA 第三方客户端
- 核心路径：版块目录 → 主题列表 → 帖子详情
- 一级导航：首页 / 版块 / 消息 / 我的
- 联网功能只展示 NGA 官方网页或现有接口能够支持的能力，不虚构服务端功能
- 不设计跨设备阅读同步、私信已读回执、官方推送等未经验证的能力

## 3. 核心视觉方向

### 3.1 总体风格

整套 UI 使用统一、成熟的“液态玻璃”设计语言。液态玻璃必须贯穿背景、导航、卡片、筛选器、列表、操作栏与弹层，不能只是在少数组件上增加透明度。

视觉关键词：

- 原生 iOS
- 光学玻璃
- 半透明与折射
- 背景感知模糊
- 清晰的边缘高光
- 分层景深
- 克制、沉浸、高级
- 高信息密度但不拥挤
- 长文阅读舒适

### 3.2 玻璃层级

使用三种明确层级：

1. 导航玻璃：最清透，用于顶部导航、底部 Tab Bar、浮动按钮。
2. 内容玻璃：轻微着色，用于首页卡片、版块卡片、主题列表、消息列表。
3. 阅读玻璃：透明度最低、雾化程度最高，用于长文正文和引用区域，必须保证中文正文对比度。

每个玻璃表面应具备：

- 背景模糊与轻微折射
- 1px 左右的冷白或青色半透明边缘
- 很轻的顶部高光
- 克制的内阴影和投影
- 与背景内容产生真实层次，而不是纯色透明矩形

### 3.3 色彩

- 主背景：午夜海军蓝 `#071421`
- 次背景：深海蓝绿 `#0D3440`
- 品牌强调：海洋青绿 `#287C7A`
- 暖色强调：琥珀金 `#D39B52`
- 警示与未读：朱红 `#C34A36`
- 主文字：冷白 `#F5F7F7`
- 次文字：雾灰蓝 `#AABAC2`

允许少量暖金色光源与深海青色环境光，但不能出现霓虹、彩虹渐变或赛博朋克效果。

### 3.4 字体与可读性

- 使用接近 iOS 系统中文字体的字形
- 页面标题明确但不过度巨大
- 正文以阅读舒适为第一目标
- 元数据可弱化，但不能小到无法辨认
- 所有中文必须正确、清晰，不得生成乱码或错误汉字
- 正文背景不能过度透明

## 4. Design Overview 交付要求

第一轮生成一张横向设计总览图，包含 4 个等宽竖屏 iPhone 页面，从状态栏到页面底部完整展示，不使用倾斜透视和手机模型外壳。

页面顺序：

1. 首页
2. 主题列表
3. 帖子详情
4. 消息

四个页面必须使用完全一致的颜色、字体、玻璃材质、圆角、间距和图标体系。

## 5. 页面一：首页

### 页面目标

提供继续阅读、收藏版块和热门主题的快速入口。

### 必须出现

- 状态栏
- 品牌标题 `NGA`
- 副标题 `聚集热爱 · 分享真实`
- 右上角账户头像与在线状态
- `继续阅读` 大型卡片
- 继续阅读卡片内容：主题标题、版块、阅读进度、进入箭头
- `我的版块` 标题与查看全部入口
- 4 个紧凑版块卡片，例如：
  - 艾泽拉斯国家地理
  - 游戏综合
  - 生活杂谈
  - 数码硬件
- `今日热门` 主题列表
- 底部 Tab Bar：首页 / 版块 / 消息 / 我的
- 当前选中：首页

### 设计要求

- 首页可以使用一张沉浸式论坛主题配图作为背景层，但不能牺牲文字可读性
- 继续阅读卡片应是首页最强视觉焦点
- 版块卡片保持紧凑，避免四张巨大的空卡片
- 热门列表要体现真实论坛信息密度

## 6. 页面二：版块主题列表

### 页面目标

展示当前版块身份、筛选能力和高密度主题列表。

### 必须出现

- 返回按钮
- 右上角更多菜单
- 版块封面或环境背景
- 版块图标
- 版块标题 `艾泽拉斯国家地理`
- 版块简介、今日主题数、关注数
- 已关注状态
- 筛选器：全部 / 精华 / 热帖
- 主题列表，每项包含：
  - 主题标题
  - 作者头像与名字
  - 回复数
  - 相对时间
  - 可选标签：置顶 / 精华 / 热
- 右下角浮动发表按钮
- 底部 Tab Bar，当前选中：版块

### 设计要求

- 版块头部与列表之间层级明确
- 主题列表不能全部做成厚重独立大卡片，应使用共享玻璃容器、细分隔线或轻量玻璃行
- 一屏至少展示 6 条主题

## 7. 页面三：帖子详情

### 页面目标

突出长文阅读体验，同时保留楼层、作者和论坛操作。

### 必须出现

- 返回按钮
- 标题 `主题详情`
- 更多菜单
- 主题标题示例：`魔兽世界怀旧服：关于60年代副本节奏的思考`
- 主题标签、版块、浏览数、回复数
- 楼主头像、用户名、等级/用户组、发布时间
- 关注按钮
- 正文
- 主题操作：赞同 / 收藏 / 分享
- `全部回复` 区域
- 至少 2 个回复楼层
- 楼层号，例如 `#1`
- 引用块
- 回复操作、点赞数、更多菜单
- 底部固定回复栏 `回复本帖`
- 图片入口和发送按钮

### 设计要求

- 阅读页可以延续液态玻璃，但正文必须使用更浓、更稳定的磨砂玻璃
- 正文字号、行距和段落宽度适合中文长文
- 楼层之间有清楚分隔，不能像聊天软件气泡
- 引用块是嵌套玻璃层，视觉上弱于正文
- 阅读页不显示底部一级 Tab Bar

## 8. 页面四：消息

### 页面目标

展示互动提醒、私信和系统消息。

### 必须出现

- 标题 `消息`
- 右上角更多菜单或刷新入口
- 分段筛选：互动 / 私信 / 系统
- 当前选中：互动
- 至少 7 条消息
- 每条消息包含：
  - 真实感头像
  - 用户名
  - 消息类型，如 `回复了你的帖子`、`赞了你的回复`、`关注了你`
  - 两行内容摘要
  - 时间
  - 未读红点
- 底部 Tab Bar，当前选中：消息

### 设计要求

- 使用轻量玻璃列表，不要每条消息都成为厚重卡片
- 已读与未读状态必须明显但克制
- 红色只用于未读点和必要警示

## 9. 后续需要补充生成的页面

核心方向确认后，分别生成以下页面或状态：

1. 版块目录
2. 我的/账户
3. 用户资料
4. 收藏主题
5. 私信会话详情
6. 发帖编辑器
7. 回复编辑器
8. 搜索状态
9. 加载状态
10. 空状态
11. 网络错误与登录提示
12. 深色液态玻璃与更明亮液态玻璃两套对比

## 10. 功能真实性约束

允许展示的联网功能：

- 浏览版块、主题和帖子
- 论坛搜索
- 发帖、回复、引用
- 收藏主题、楼层和版块
- 点赞/反对
- 私信
- 用户资料
- 关注与拉黑
- 消息提醒

不应虚构：

- 跨设备阅读进度
- 对方已读回执
- 官方实时推送
- 无依据的个性化推荐
- 在线聊天状态
- NGA 未提供的会员或社交能力

客户端本地能力可以展示：

- 最近阅读
- 本地阅读进度
- 草稿
- 离线缓存
- 字号与阅读设置

## 11. 禁止项

- 不要生成纯白、扁平纸张风格
- 不要只给少数组件增加模糊背景
- 不要使用大量不透明白色卡片
- 不要使用霓虹赛博朋克风
- 不要使用彩虹渐变
- 不要使用夸张光晕
- 不要使用玩具感、泡泡感组件
- 不要使用 Android 导航模式
- 不要出现图表、数据仪表盘或装饰性 3D 物体
- 不要为了视觉效果减少论坛信息密度
- 不要让背景穿透导致正文难以阅读
- 不要复制其他产品 Logo
- 不要添加水印

## 12. 可直接复制给图像模型的总提示词

```text
Use case: ui-mockup
Asset type: authoritative high-fidelity product UI design board for direct SwiftUI implementation

Design a complete native iOS interface for “NGA Orbit”, a focused, information-dense NGA forum client. The output is the actual product design baseline, not a moodboard, marketing image, fantasy concept, or loose inspiration.

Create one landscape design overview containing four equal portrait iPhone screens shown straight-on and fully visible from status bar to bottom edge, without device frames or perspective. Screen order: 首页, 版块主题列表, 帖子详情, 消息.

Use a comprehensive premium liquid-glass design system across the entire product. The backgrounds, navigation bars, cards, segmented controls, list containers, rows, quote blocks, floating action button, reply bar, and tab bars must all belong to one coherent optical-glass hierarchy. Use background-aware blur, subtle refraction, fine cool-white edge highlights, gentle specular lighting, restrained inner shadows, and realistic depth separation. Use clearer glass for navigation, softly tinted glass for content cards, and denser frosted glass for long-form reading surfaces. Glass must feel physical and layered, not like simple transparent rectangles.

Palette: midnight navy #071421, deep ocean teal #0D3440, ocean accent #287C7A, restrained amber #D39B52, vermilion #C34A36 only for unread dots and important badges, cool white primary text, misty blue-gray secondary text. Atmospheric navy/teal backgrounds may include subtle warm amber light, but no neon or rainbow gradients.

Screen 1 首页: “NGA”, “聚集热爱 · 分享真实”, account avatar with online state, a visually dominant “继续阅读” card with thread image/title/board/progress, compact “我的版块” cards, a dense “今日热门” topic list, and bottom tabs “首页 / 版块 / 消息 / 我的” with 首页 selected.

Screen 2 版块主题列表: back and more buttons, atmospheric board header, icon and title “艾泽拉斯国家地理”, short metadata and followed state, segmented filter “全部 / 精华 / 热帖”, at least six compact topic rows with realistic author/reply/time metadata and optional 置顶/精华/热 badges, floating compose button, and bottom tabs with 版块 selected.

Screen 3 帖子详情: back and more buttons, title “主题详情”, topic title “魔兽世界怀旧服：关于60年代副本节奏的思考”, board/browse/reply metadata, author block, readable Chinese long-form body, actions “赞同 / 收藏 / 分享”, “全部回复”, at least two forum-style floors with avatar, floor number, timestamp, quote block and reply actions, and a fixed “回复本帖” bar. Do not show the primary tab bar on the reader screen. Long-form text must use denser frosted glass and remain exceptionally readable.

Screen 4 消息: title “消息”, segmented filter “互动 / 私信 / 系统” with 互动 selected, at least seven compact message rows with realistic avatar, username, action, two-line preview, timestamp and restrained unread red dots, plus bottom tabs with 消息 selected.

Use realistic iOS safe areas, system-like Chinese typography, consistent spacing, 14–20 px corner radii, large touch targets, crisp icons, and production-feasible components. Preserve authentic forum information density. All required Chinese labels must be correct and legible.

Avoid flat white paper UI, opaque white cards, simple blur-only styling, excessive transparency behind body text, neon cyberpunk, rainbow gradients, gaudy glow, toy-like bubbly controls, huge empty cards, Android patterns, fake dashboards, decorative 3D objects, copied logos, illegible small text, malformed Chinese, and watermarks.
```

## 13. 交付检查清单

生成后检查：

- [ ] 四个页面是否完整显示
- [ ] 液态玻璃是否贯穿所有层级
- [ ] 页面之间是否使用同一套设计系统
- [ ] 中文是否正确可读
- [ ] 长文区域是否具有足够对比度
- [ ] 主题列表是否保持真实信息密度
- [ ] 交互组件是否能由 SwiftUI 实现
- [ ] 是否避免虚构 NGA 不支持的服务端功能
- [ ] 是否没有水印、设备外壳和透视变形
