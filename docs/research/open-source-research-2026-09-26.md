# macOS AI 用量菜单栏工具调研

日期：2026-09-26。仅阅读上游文档、源码和发布元数据；没有安装或运行第三方应用，没有修改 VPNUsage 应用代码，也没有调用用户的 VPN 查询接口。本文不保存用户的查询地址或凭据。资源占用结论属于架构判断，不是本机实测。

## 候选对比与选择

用户确认主要监控 Codex/ChatGPT 与 Claude。下面的 Star 数是本日 GitHub REST API 快照，随时间变化；不作为性能测量。这里的 Codex 额度指订阅内 Codex 的会话/周等限制，不能解释为覆盖 ChatGPT 每一种产品功能的统一总额度。

| 项目 | Star | 最新稳定版 / 发布日 | 实现与风格 | VPN 接入判断 |
|---|---:|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar) | 21,931 | v0.67.0 / 2026-09-26 | 原生 Swift，多服务、丰富显示选项；MIT | 有用户插件；保留全部既定需求建议小范围 fork + 原生 provider |
| [OpenUsage](https://github.com/robinebers/openusage) | 4,267 | v0.7.12 / 2026-09-17 | 当前稳定版已是原生 Swift，统一多服务面板；MIT | ProviderRuntime 与通用 used/limit 模型适合扩展；新增原生 provider 后补配置和菜单栏样式 |
| [ClaudeBar](https://github.com/tddworks/ClaudeBar) | 1,503 | v0.4.93 / 2026-09-24 | 原生 Swift，主题丰富，有脚本扩展 | manifest 可自动生成设置；未找到明确 LICENSE，暂不列为 fork 首选 |
| [AI Usage](https://github.com/burakgon/ai-usage-menubar) | 25 | v0.2.1 / 2026-07-29 | SwiftUI/AppKit、Liquid Glass，精简额度监控；MIT | 新增 UsageProvider 和 ProviderID，再接配置/双行 UI；代码面较小但社区规模小 |

Star、活动和许可证元数据来源：[CodexBar API](https://api.github.com/repos/steipete/CodexBar)、[OpenUsage API](https://api.github.com/repos/robinebers/openusage)、[ClaudeBar API](https://api.github.com/repos/tddworks/ClaudeBar)、[AI Usage API](https://api.github.com/repos/burakgon/ai-usage-menubar)。四者均有 Codex 与 Claude 额度支持，具体登录来源依项目与服务而异。前三者最近推送在 2026-09-26，AI Usage 在 2026-07-29；这不等于保证维护响应速度。

### OpenUsage

稳定版 v0.7.12 的 ProviderRuntime 通过 auth store、usage client、mapper 输出 ProviderSnapshot，支持带 used/limit 的 progress、可选单位和原始数值，因此将字节用量归一化为 GB 在模型上自然可行。菜单栏可固定每服务最多两个指标，双指标会堆叠；这不是已支持“自定义名称在上、百分比在下”，该样式仍需确认/改造。[扩展指南](https://github.com/robinebers/openusage/blob/v0.7.12/docs/adding-a-provider.md) · [菜单栏](https://github.com/robinebers/openusage/blob/v0.7.12/docs/menu-bar.md)

它包含本地日志费用统计、快捷键、更新与 PostHog 依赖。稳定版官方隐私文档明确：匿名日活和崩溃报告不可通过设置关闭，额外匿名分析默认开启但可关闭；另有公共价格数据下载。不能把它描述成“完全无遥测、只请求用量API”的极简工具。[稳定版依赖](https://github.com/robinebers/openusage/blob/v0.7.12/Package.swift) · [隐私说明](https://github.com/robinebers/openusage/blob/v0.7.12/docs/privacy.md)

### ClaudeBar

稳定版已经允许 manifest + 脚本输出 JSON，扩展可以同时提供 quota 和 metrics，配置字段会出现在设置中。现有约束是每段随全局刷新，`probe.interval` 被忽略，secret 字段在 UserDefaults 而非 Keychain。菜单栏可选最多三种服务，有双额度堆叠，不等同自定义名称/数值两行。[扩展文档](https://github.com/tddworks/ClaudeBar/blob/v0.4.93/docs/features/extensions/README.md) · [菜单栏文档](https://github.com/tddworks/ClaudeBar/blob/v0.4.93/docs/features/menu-bar/README.md)

GitHub API 的 license 为 null，main 递归文件树未发现 LICENSE，稳定版 LICENSE 路径返回 404。这里只能确认授权文件未找到，不据此断言具体法律权利；若选作修改/再分发底座，需先核清授权。[仓库文件树](https://github.com/tddworks/ClaudeBar)

### AI Usage：轻量方向的备选

稳定版 README 明确无用量历史、后台日志扫描、遥测或本地服务器，只有 Sparkle 一个运行时包依赖；作者报告轮询间隔内 CPU 为 0.0%，这是作者观察，不是本次独立测试。源码可确认关闭 popover 会清空 contentViewController，并用 Task.sleep 等待下一轮刷新。[README](https://github.com/burakgon/ai-usage-menubar/blob/v0.2.1/README.md) · [关闭面板释放实现](https://github.com/burakgon/ai-usage-menubar/blob/v0.2.1/AIUsage/MenuBar/MenuBarController.swift#L421) · [刷新实现](https://github.com/burakgon/ai-usage-menubar/blob/v0.2.1/AIUsage/Store/UsageStore.swift#L334)

该项目要求 macOS 26+，用户本机满足；但 25 Star、30 次提交的验证面明显小于 CodexBar。其 ProviderID 为固定枚举，UsageProvider 协议只需 fetch 返回 snapshot；VPN 可接，但不是复制配置就能动态增加任意服务。[模型源码](https://github.com/burakgon/ai-usage-menubar/blob/v0.2.1/AIUsage/Models/ProviderModels.swift)

### 体积、性能与外观的证据边界

GitHub 发布资产：CodexBar universal ZIP 74.49 MB；OpenUsage DMG 21.42 MB；ClaudeBar DMG 18.65 MB；AI Usage DMG 3.90 MB。这是十进制压缩下载大小，格式、打包内容和架构可能不同，**既不是安装后体积，更不是 RAM 排名**。[CodexBar 发布 API](https://api.github.com/repos/steipete/CodexBar/releases/latest) · [OpenUsage 发布 API](https://api.github.com/repos/robinebers/openusage/releases/latest) · [ClaudeBar 发布 API](https://api.github.com/repos/tddworks/ClaudeBar/releases/latest) · [AI Usage 发布 API](https://api.github.com/repos/burakgon/ai-usage-menubar/releases/latest)

若后续允许试用，应在同机、仅启用 Codex+Claude、统一刷新周期下比较：启动后空闲 RSS/CPU、刷新峰值、面板打开与关闭、CPU 时间/唤醒次数，以及已有会话日志较多时的扫描成本。本轮尚未进行这组测量。

官方外观参考：[CodexBar](https://raw.githubusercontent.com/steipete/CodexBar/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/screenshots/current-merged-menu-redacted.png)、[OpenUsage](https://raw.githubusercontent.com/robinebers/openusage/v0.7.12/assets/screenshot.jpg)、[ClaudeBar](https://raw.githubusercontent.com/tddworks/ClaudeBar/v0.4.93/docs/screenshots/Screenshot-dark.png)、[AI Usage](https://raw.githubusercontent.com/burakgon/ai-usage-menubar/v0.2.1/docs/images/ai-usage-menubar-dark.png)。图片展示项目风格，不代表本次实机测试。

还筛查了 methol-dev/usage-bar（1 Star）、Balanced02/ai-usage-bar（1 Star）、stavrop/ai-usage-monitor（3 Star），与用户偏好多 Star 的条件不够匹配。SwiftBar（4,550 Star、MIT）适合通用脚本菜单栏，但不自带统一的多家 AI 登录和额度适配，因此本轮不作为一体化首选。[SwiftBar](https://github.com/swiftbar/SwiftBar)

综合推荐优先 CodexBar：保留社区维护的 AI 适配，只扩展 VPN。若资源占用优先级高于社区规模，则把 AI Usage 留作实测对照；OpenUsage 是偏好多服务统一面板时的备选。

## CodexBar：适合保留 AI 能力的扩展底座

**结论：可以基于 CodexBar 增加 VPN 用量；但只安装用户插件，不能完整满足此前确认的独立双行菜单栏、可编辑显示名、钥匙串保存和独立 1～60 分钟轮询要求。** 数据请求与详情展示已经有插件接口，差距主要在宿主的菜单栏展示、配置和凭据存储。

研究基线为稳定版 **v0.67.0**，GitHub 发布于 2026-09-26，对应提交 `e0286a895055e60ddaefa6a5f176f246aa2f05e4`；同时检查 main 提交 `3c97aa79eea732eb8c6d9345e24ce6fdfe249a30`。稳定版已经包含本文所述用户插件功能，两者的 `docs/plugins.md` 内容一致。因此不必仅为插件框架追踪 main。后文源码链接固定到稳定版提交，避免 main 更新后含义变化。[稳定版发布](https://github.com/steipete/CodexBar/releases/tag/v0.67.0) · [稳定版提交](https://github.com/steipete/CodexBar/commit/e0286a895055e60ddaefa6a5f176f246aa2f05e4) · [main 核查基线](https://github.com/steipete/CodexBar/commit/3c97aa79eea732eb8c6d9345e24ce6fdfe249a30)

### 稳定版已有的扩展能力

- 本地 `.js` / `.ts` 文件可通过 Settings → Plugins → Install 安装，或者放入用户 provider 目录。它们调用 `defineProvider`，声明名称、图标、访问 origin、设置项和 `fetchUsage`。
- `ctx.http.getJSON` 可执行 HTTPS GET，`ctx.settings.get` / `getSecret` 读取用户设置；宿主自动为 `plain` / `secure` 字段生成普通或遮蔽输入框。
- 返回 `primary.usedPercent` 可复用额度进度，`details` 可放已用 GB、总 GB、剩余 GB、每月重置日等文本；详情行还支持进度字段。不应把 GB 伪装为美元 `cost`，该模型要求三字母货币代码。
- 插件运行于嵌入式 QuickJS，不需要 Node 或单独常驻 shell。没有 Node、文件读写、任意进程执行等 API；网络受声明 origin、超时、响应大小和重试次数约束。

以上是稳定版官方契约，不是仅存在于计划中的 API。[插件文档](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/plugins.md) · [自动生成设置界面的源码](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesPluginsPane.swift#L123)

### 与已确认需求逐项对照

| 用户需求 | 仅用户插件的覆盖程度 | 保持原需求所需调整 |
|---|---|---|
| 拉取 Just My Socks 用量 | 有 HTTPS GET 和 JSON 解析，技术路径可行；尚未运行验证 | 编写小型适配器、验证接口字段与错误响应 |
| 详情中的百分比、已用/总额/剩余 GB、重置日 | 支持百分比窗口和文本详情 | 插件负责计算和格式化，不编造精确重置时刻 |
| 菜单栏独立常驻 `VPN` / `1.6%` 两行 | 不完整；插件目前是下拉卡片或合并模式中的标签页 | 为插件增加独立 status item 和布局接入，或把 VPN 注册为内置 provider |
| 上方更小的自定义名称 | 插件名称来自代码 manifest；plain 名称设置不会自动替换宿主标题 | 新增可编辑 displayName 配置，并应用到渲染；分别控制两行字体 |
| 可视化修改查询 URL | 可声明 secure 输入框，固定允许 origin；修改为其他主机需声明/重新批准相应 origin | 若延续钥匙串要求，应由原生设置层保存地址；URL 校验与错误信息去凭据 |
| 独立 1～60 分钟轮询，默认 5 分钟 | 当前插件随宿主刷新批次；宿主提供固定 1/2/5/15/30 分钟、手动和自适应 | 新增每实例轮询配置；不把插件自定义文本字段误认为宿主计时器配置 |
| 凭据存入 macOS 钥匙串 | 不支持现成等价行为；插件 secure 值写入配置 JSON | 增加 Keychain 支持，或在原生 VPN provider 中单独实现 |
| 超额时显示真实百分比 | 通用插件窗口被夹到 0～100 | 详情可用文本显示真实比例；常驻显示需保留未截断值 |
| 失败保留旧数据并明确标错 | 插件 Store 保留 snapshot 并记录 error；已有 snapshot 时通用卡片优先显示数据，错误主要可在设置页查看 | 若要求常驻异常标记、详情错误与最后成功时间，需补齐展示 |

独立常驻项的限制可从两处交叉确认：插件文档说明关闭 Merge Icons 时仍采用 appended-card placement；`lazyStatusItem` 和菜单栏布局函数接收内置 `UsageProvider`。`topLevel: true` 的含义是获得下拉 provider switcher 标签，不等于创建独立系统菜单栏项。[插件展示范围](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/plugins.md#provider-switcher-tabs) · [独立 status item](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/StatusItemController%2BStatusItemVending.swift#L76) · [布局入口](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/StatusItemController%2BMenuBarLayout.swift#L38)

上游已有一至两行 token 布局、Provider name、百分比、紧凑 stacked 样式，可复用这一套渲染设计。但它不代表第三方插件自动获得同等展示能力，也不能据此承诺上下两行分别设置字号已经现成支持。[稳定版 UI 文档](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/ui.md)

百分比夹取和失败状态的结论来自源码：窗口映射使用 `min(100, max(0, rawPercent))`；刷新失败只更新错误值；卡片使用 `if let snapshot ... else if let error`。[百分比映射](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBarCore/Plugins/ProviderPluginSnapshotMapper.swift#L238) · [插件刷新](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/UsageStore%2BUserPlugins.swift#L64) · [插件卡片](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/StatusItemController%2BUserPlugins.swift)

### URL 查询参数凭据：文档与实现需要区分

Just My Socks 查询使用 URL 参数携带查询凭据。插件文档的安全章节宣称秘密不放进 URL，但稳定版实际请求构造路径会接受脚本传入的完整 URL，检查 HTTPS origin、方法、fragment/user/password 等；检查过的实现没有扫描 URL 是否包含 `getSecret` 返回值。`getSecret` 本身给脚本提供字符串。因此“secure 设置 → 拼接允许 origin 下的查询地址 → GET”在源码层面看可以执行，不能把文档这句话直接解释为会拒绝所有 query 凭据。

这仍是**源码推断，未安装应用、未运行插件、未用真实凭据端到端验证**。不应将凭据改放 plain 字段来绕开安全语义。更明确的差距是 `secure` 仅代表遮蔽输入及秘密值处理：设置绑定写入 `pluginSecrets`，配置 Store 编码 JSON 后用私有权限写盘，不能声称它等同钥匙串。若保持此前确认的本机 Keychain 要求，需要原生适配。[HTTP 请求构造](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBarCore/Plugins/ProviderPluginHTTPResponse.swift#L173) · [origin 校验](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBarCore/Plugins/ProviderPluginManifest.swift#L427) · [secret 设置绑定](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesPluginsPane.swift#L295) · [配置写盘](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBarCore/Config/CodexBarConfigStore.swift#L54)

### 刷新与资源占用

CodexBar 的 macOS 宿主为原生应用，插件使用进程内 JavaScript 引擎；与另起 Node/Electron 常驻服务相比有结构优势，但**源码和安装包体积都不能证明实际 RAM、CPU、Energy Impact 最低**。本轮不提供未经测量的内存数字。

稳定版自适应刷新按交互活跃度从 2 分钟放缓到 30 分钟，低电量模式或高温时采用 30 分钟；普通 Adaptive 不扫描本机代理活动。另一个 Adaptive (agent-aware) 模式经用户同意后会周期检查进程和已知会话文件。插件与内置 provider 共用刷新批次，重复工作有协调与取消控制。[刷新文档](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/refresh-loop.md) · [插件加入刷新批次](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/UsageStore.swift#L810)

面向“Codex + Claude + VPN、尽量省资源”的配置建议：

1. 仅启用实际使用的 provider；采用普通 Adaptive，或者固定 5～15 分钟。若强调 VPN 严格每 5 分钟，需要单独计时配置，不能依赖自适应模式。
2. 关闭 Usage & Spend 的本地成本跟踪、不启用 Agent Sessions/agent-aware 扫描；API 配额和本地按价估算费用是不同数据。
3. 不开启可选 OpenAI Web Extras。上游明确记录过隐藏 ChatGPT WebView 的耗电问题，并已将新安装默认值改为关闭。
4. 不需要时关闭 provider storage 扫描、服务状态检查，以及打开菜单刷新全部 provider。
5. 关闭菜单栏的随机 blink 动画。收益需实测，不应宣称这是主要耗电来源。

[成本控制设置源码](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesSpendDashboardPane.swift) · [Web Extras 耗电问题与默认值修复](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/solutions/performance-issues/openai-web-extras-default-off-codexbar-20260307.md) · [一般设置](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesGeneralPane.swift#L147) · [存储扫描设置](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesAdvancedPane.swift#L55) · [动画设置](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/Sources/CodexBar/PreferencesMenuBarPane.swift#L127)

### 如果后续决定改造，推荐路线

**保留原需求时，推荐基于稳定 tag 做小范围 fork，增加原生 VPN provider，尽量复用现有布局和刷新体系。** 这样仍保有 Codex、Claude 等上游适配能力，又能局部实现 Keychain、用户名称、独立周期、超额真实读数与上下两行字号。相较全面泛化插件菜单栏和安全存储，这更适合当前只增加一个 VPN 来源；后续确有多个非 AI 来源，再抽象通用 Resource Usage provider。

可分成数据适配、配置/Keychain、菜单栏渲染三个独立变更。数据适配优先只发一次受超时限制的 URLSession GET，避免额外常驻进程。上游 provider 作者指南已有 descriptor、fetch strategy、UI implementation 等注册步骤，并要求 provider-specific UI/配置留在 provider 模块。[官方 provider 作者指南](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/provider.md)

另一条路线是“用户插件 + 下拉 VPN 卡片”，它几乎不需要维护 fork，但必须接受常驻双行和钥匙串等要求的落差；目前不建议把这条路线描述成完整替换现有 VPNUsage。也可以先用上游 CodexBar 管 AI、保留现有 VPNUsage 管 VPN，用实际体验判断是否值得合并。

维护策略建议：以稳定 tag 为基线，保留 upstream remote，把扩展分为少量独立提交；升级时先审阅稳定版差异，再验证 API fixture、菜单栏字号/宽度、Keychain、睡眠唤醒、错误状态以及仅启用 Codex/Claude/VPN 的资源表现。不要跟 main 每次变化同步。定制构建需要避免直接使用上游自动更新渠道覆盖本地修改；CodexBar 的 Sparkle 指向自己的官方 appcast，应禁用或换成自行维护渠道，上游也明确 unsigned/Homebrew 构建的更新行为不同。[Sparkle 文档](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/sparkle.md)

许可证为 MIT，允许修改与再分发，需保留版权和许可声明；若重新发布打包版本，还应保留相应第三方依赖声明。这是基于仓库许可证文本的说明。[MIT LICENSE](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/LICENSE) · [第三方许可](https://github.com/steipete/CodexBar/blob/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/THIRD_PARTY_LICENSES.md)

界面参考可使用上游仓库的[合并菜单截图](https://raw.githubusercontent.com/steipete/CodexBar/e0286a895055e60ddaefa6a5f176f246aa2f05e4/docs/screenshots/current-merged-menu-redacted.png)。截图属于官方开发资料，展示界面风格，不保证每项配置均为默认状态。
