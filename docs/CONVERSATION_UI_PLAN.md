# 方案 D：会话式收发界面改造方案

日期：2026-11-05  
适用执行模型：千问 3.8 Flash  
文档状态：方案已整理，尚未实施；不代表业务代码已经修改或验证通过。  
目标：共享 Dart UI/provider 代码，宽屏设备列表与会话详情常驻两栏，窄屏列表进入会话详情。

本文所有文件路径均相对仓库根目录；命令按指定工作目录执行，不相对本文所在的 `docs/` 目录。

## 1. 审核结论与必要修正

方案方向可行，但不能简化为“换几个页面布局”。需要新增会话记录层，并对现有 Dart provider/controller 内的导航行为做有限调整。

| 原判断 | 审核后的准确表述 |
| --- | --- |
| 一套代码，四端生效 | macOS、Windows、Android、iOS 共享实现，但必须分别构建和冒烟。Linux 可复用 UI，不等于已验收。 |
| 顺带支持 Web，共六端 | Flutter 框架支持 Web，不代表本仓库的 Rust、isolate、原生插件和网络能力已支持 Web。本次不承诺 Flutter Web 收发。 |
| 完全不碰平台代码 | 作为本次实施边界成立：不改原生工程、权限、platform channel。现有平台能力继续复用。 |
| 传输层完全不动 | Rust、协议、isolate 和绑定不动；Dart 应用层传输 provider/controller 的导航与记录接入需要修改。 |
| 现有 session 状态足够 | 足够展示当前传输，不足以提供跨传输、跨重启的设备会话历史。 |
| 先搬 SendPage、ProgressPage、ReceivePage | 不推荐。旧页面携带取消、路由、自动结束、唤醒与任务栏副作用，直接嵌入右栏容易出错。 |

宽度判定来自 `app/lib/widget/responsive_builder.dart`：

- `<700`：mobile。
- `700～799`：tablet，仍不是 desktop。
- `>=800`：desktop。
- 单位为 Flutter 逻辑像素，不是截图物理像素。
- 本方案会话两栏采用 `>=800`；`700～799` 仍单栏。不要修改全局阈值影响其他页面。
- `ResponsiveBuilder` 读取整个窗口的 MediaQuery 宽度，不是右侧内容剩余宽度。两栏组件还需检查自身 LayoutBuilder 约束。

## 2. 范围与推荐路径

推荐采用“保留旧收发入口，新增会话入口，逐批接入真实收发”的路径。

第一版核心交付：

1. 设备会话列表，支持选中设备、在线/未发现状态及最后一条记录摘要。
2. 宽屏两栏、窄屏列表进入详情；调整窗口宽度不丢选中设备、输入草稿和传输状态。
3. 文字气泡、文件卡片、时间分组、传输状态与进度。
4. 会话输入栏、现有能力支持的附件选择、接收确认与明确取消。
5. 有边界的本地会话历史，重启可查看；删除记录不删除真实文件。
6. 保留原发送、接收、设置、多选发送及链接分享路径。

第一版不做：

- 不移除旧页面，不一次性重构首页导航体系。
- 不实现聊天协议、已读回执、真正的长期连接、离线投递、自动重连发送。
- 不新增截图、屏幕录制、视频播放、剪贴板监听等能力。
- 不照搬 Flix 品牌、图标或操作系统窗口装饰；参考的是信息组织和交互。
- 不自动迁移旧接收历史。旧历史仅有 senderAlias，没有可靠设备指纹和完整双向记录。
- 不扩展 WebRTC、浏览器链接收发为会话传输；这些入口继续走原逻辑。
- 不修改安全校验、PIN、保存目标、SAF、相册、通知、协议和网络发现实现。
- 不增加依赖，不升级 Flutter，不改版本号，不手写生成代码。

仓库的 `AGENTS.md` 限制 AI 生成的上游贡献。本方案适用于本地定制；对上游提交此规模功能需要另行满足仓库贡献政策。

## 3. 已核实的代码事实

| 文件 | 当前职责及改造注意事项 |
| --- | --- |
| `app/lib/pages/home_page.dart` | HomeTab 三入口、PageView、NavigationRail/NavigationBar、桌面拖入文件。 |
| `app/lib/pages/home_page_controller.dart` | 首页导航与共享 PageController；实施前需读取，不创建第二个 HomePage。 |
| `app/lib/pages/tabs/send_tab.dart` | 文件选择和附近设备列表，旧路径保留。 |
| `app/lib/pages/tabs/send_tab_vm.dart` | 点设备会直接 startSession；多发送模式切换 background 与页面导航。 |
| `app/lib/provider/network/send_provider.dart` | 创建 session、校验和、请求、PIN、上传、取消及页面跳转。 |
| `app/lib/provider/network/server/controller/receive_controller.dart` | 接收确认、自动接受、记录历史、结果、取消与页面跳转。 |
| `app/lib/provider/file_transfer_provider.dart` | 高频可变状态，以 sessionId/fileId 保存进度；清理 session 会删除进度。 |
| `app/lib/provider/receive_history_provider.dart` | 旧接收历史最多 30 条，仅接收方向，受保存历史开关控制。 |
| `app/lib/model/persistence/receive_history_entry.dart` | 仅保存 senderAlias，没有设备指纹，不宜据此合并新会话。 |
| `app/lib/provider/persistence_provider.dart` | SharedPreferences 及便携模式持久化入口。 |
| `app/lib/provider/selection/selected_sending_files_provider.dart` | 全局文件选择，清空还会触发缓存清理，不能拿它充当每个会话的草稿。 |

特别注意：

- `startSession` 返回 `Future<void>`，不是 sessionId。
- `background` 同时控制旧页面和完成后的清理，不能用 `background:true` 代替“会话 UI 模式”。
- 文字 preview 在 prepare 阶段已可显示，但发送成功取决于接收方确认；不能直接显示“已读”。
- 接收文字历史当前在用户确认前即写入；新增会话记录不能依赖旧历史来推断接受或拒绝。
- 发送收到 204 会标记完成后立刻 closeSession；后台文件全部成功甚至不先发布 finished 状态就清理。
- 仅 watch 当前 session 可能漏掉成功终态，必须在真实完成分支、清理前记录摘要。
- 接收端只有一个 active session，发送端可以有多个；会话列表不代表新增了并发接收能力。
- 失败的接收 session 可能需要等待发送端重试，不能为了显示历史提前 closeSession。
- `_cancelBySender`、quickSave 完成和 PIN 等分支也有导航或弹窗，不能只处理正常成功路径。

## 4. 实施不变量

执行模型必须逐条遵守：

1. 会话展示状态不是传输状态。选中、返回、缩放窗口、关闭记录面板不触发网络取消。
2. 取消只能来自明确的用户取消动作或已有网络取消事件。
3. 对接收操作必须同时核对方向和 sessionId，不得仅用 `serverProvider.session ?? sendSession` 决定对象。
4. 设备身份用非空 fingerprint。IP 是可变化的地址，alias 是可变化的展示名称。
5. 同一 fingerprint 多个地址显示一个会话；发送时取最新可用 Device，保留 IPv6 scope。
6. 缺少可信身份时不与已有会话自动合并；展示为临时会话并禁止长期自动关联。
7. 保留 `event.certFingerprint ?? event.info.fingerprint` 与发送端 pinnedTo，UI 不替代安全校验。
8. 不把发现设备显示成真实持续连接。使用“在线/未发现”等准确文案，不伪造“已连接”。
9. 先在内存形成终态快照，再清理传输；磁盘保存不得阻塞网络响应或把成功转为失败。
10. 终态记录按稳定键 upsert，不能每次 rebuild、每次进度或重复事件都追加气泡。
11. 重启只恢复历史，不恢复任务、token、stream、asset、file descriptor 或取消对象。
12. 文件 URI 和相册结果通过现有打开逻辑处理，不能假定所有 path 都是可直接 File 操作的路径。
13. 通知、唤醒、任务栏和缓存资源须保持原生命周期，不挂在气泡组件 dispose 上。
14. 不改 `packages/`、`server/`、`cli/` 及 `app/android|ios|macos|windows|linux`。

## 5. 建议架构与数据合同

### 5.1 三类状态分离

| 层 | 建议文件 | 保存内容 |
| --- | --- | --- |
| UI 状态 | `app/lib/provider/conversation_ui_provider.dart` | 选中 peerKey、窄屏详情显示状态、每设备纯文字草稿。 |
| 会话摘要 | `app/lib/provider/conversation_provider.dart` | 有界历史、设备展示信息、去重索引、更新与清除动作。 |
| 展示投影 | `app/lib/provider/conversation_view_provider.dart` | 合并附近设备、历史和活跃收发；为组件提供轻量视图。 |
| 既有传输 | 原 sendProvider/serverProvider/fileTransferProvider | 继续拥有任务、取消、协议交互、实时文件进度。 |

使用仓库现有 Refena API；不得引入 Riverpod。普通 UI 状态用 NotifierProvider；记录异步保存可用 ReduxProvider，参考旧历史测试和持久化约定。

### 5.2 模型

建议放在 `app/lib/model/conversation/`，采用 dart_mappable；模型和枚举可先集中在一个文件，避免一个批次创建大量文件。

| 模型 | 必需字段 |
| --- | --- |
| ConversationPeer | peerKey、fingerprint、最近 alias、deviceType；历史不持久化“在线”。 |
| ConversationEntry | entryId、peerKey、direction、localSessionId、创建时间、完成时间、kind、outcome、files、可选 text、error。 |
| ConversationFileSummary | fileId、展示文件名、类型、大小、最终状态、可选 path、savedToGallery、可选 error。 |

统一约定：

- peerKey 为设备 fingerprint 派生的稳定键；临时 peerKey 不与长期会话混用。
- entryId 使用 `direction + localSessionId`，每次传输一条气泡；批量文件放在该气泡内。
- 草稿发送动作在拿到真实 sessionId 时创建记录，不另造一条不可关联的乐观记录。
- 同一传输的重试更新原卡片；再次发送是新的 session，生成新记录。
- summary 不持有 SendingFile/ReceivingFile 原对象，不保存 bytes、缩略图二进制、PIN、token、证书、任务。
- 持久化时间统一 UTC；UI 转本地时区，按日期分组。
- outcome 使用独立展示枚举，不修改共享 SessionStatus。覆盖准备、等待、传输、完成、部分失败、拒绝、忙碌、取消。
- 校验和进度和上传进度分开展示，不能把 hash=100% 当上传完成。
- 204 只说明对方完成确认/未选择文件，不说明“已读”；对非文字无文件接受显示“无文件被接收”。
- 重启遇到未结束记录标记“上次传输未完成”，不可自动重新发送。

### 5.3 两个集成接口

以下是职责合同，不是要求照抄未经验证的 Refena API：

- `ensureTransferEntry`：在实际 session 创建后登记设备、方向、文件摘要和 sessionId。
- `upsertTransferSnapshot`：在明确状态事件与清理前同步更新内存摘要，持久化排队执行。

用于区分展示路径的应用层枚举建议名为 `TransferPresentation`：

- `legacy`：完全保留原页面跳转。
- `conversation`：会话容器展示状态，不跳旧收发页；PIN/权限等必要交互继续弹出。
- `startSession` 新增可选 presentation，默认 legacy，不修改旧调用点语义。
- 每个发送 session 单独保存 presentation；不得用全局当前 tab 猜测正在运行任务的模式。
- 接收请求在创建时固定本次 presentation；切换用户开关不改变已经接受的传输。
- presentation 可以保存在 Dart 应用状态或独立映射，清理时同步移除；不进 isolate，不进协议。

### 5.4 生命周期接入清单

| 接入时机 | 记录要求 | 导航要求 |
| --- | --- | --- |
| 发送创建 session 后 | 建立记录并返回/回调真实 sessionId | conversation 不 push SendPage。 |
| 403/409/429、PIN 取消、异常 | 更新明确失败/取消结果 | 保留 PIN 弹窗；不意外打开旧页。 |
| prepare 204/无文件接受 | 先记录结果，再 closeSession | legacy 原跳转保留；conversation 留在详情。 |
| 文件进入上传阶段 | 更新阶段和接受/跳过摘要 | conversation 不替换为 ProgressPage。 |
| `_finish` 后台成功 | 清理前直接形成完成快照 | 不依赖 finished 状态曾被发布。 |
| 本端取消/远端取消 | 先记录取消来源，再调用原取消逻辑 | 切会话不调用这些动作。 |
| 接收 prepare | 建立待确认记录 | 根据固定 presentation 选择旧页或会话提示。 |
| 接收文字接受 | 沿用 acceptFileRequest({}) | 不自动接受，不伪造已读。 |
| 接收文件结果 | 更新单文件结果/真实保存位置 | 保留旧历史写入，不额外重复写旧历史。 |
| 接收完成/quickSave | 清理前记录终态 | conversation 不 pushRoot 新 HomePage。 |
| aborted/end/cancel | 按匹配 session 更新 | conversation 不 popUntil ReceivePage。 |

不要通过拦截全局 Routerino 来屏蔽页面。分支只围绕已有导航语句做，网络处理顺序不重写。

## 6. 布局、交互与兼容策略

### 6.1 入口与响应式

- 新增“会话”入口，原收发/设置保留；新 HomeTab 建议追加在 enum 末尾，避免改变原 index。
- enum、PageView children、导航 destinations、控制器索引必须一致，逐一核对。
- 新会话请求显示开关默认关闭，用户主动启用后，新原生 HTTP 接收请求进入会话 UI。
- 会话入口主动发起的任务使用 conversation；原 SendTab 发起的任务保持 legacy。
- 若正在进行 legacy 接收，会话入口只读显示当前传输；接受/拒绝仍由原页面负责，不提供第二套按钮。
- 链接上传/下载与 WebRTC 始终 legacy。判断条件应来自现有请求路径，不猜测平台名称。
- 窄屏详情在同一会话容器内切换，用 PopScope 返回列表；无需 push 第二个 HomePage。
- 宽度切换时保持同一份 UI/provider 状态，不把新旧布局同时挂载并注册重复监听。
- 宽屏默认左列约 260 逻辑像素、右列至少 360；扣除首页侧栏后空间不足则单栏。
- `>=800` 且本组件可用宽度 `>=620` 才两栏。窗口 700～799 一律单栏。

### 6.2 会话详情

- 顶部展示设备名称、准确的发现状态；离线仍可查看历史，但禁用发送。
- 气泡区使用 ListView.builder，不用一次性 Column 构建全部历史。
- 长文字允许选取复制；超长文字折叠展开，不能固定成 100 高度后丢失内容。
- 自动滚到底仅在用户接近底部或主动发送时发生；用户浏览旧消息不强制跳动。
- 文件显示名称、大小、进度、最终状态；文件不存在或无可打开路径时给提示。
- 接收待确认卡片只对当前匹配 session 提供接受/拒绝；提交期间防重复点击。
- 返回列表、切设备不拒绝待确认请求。待确认状态在列表保留提示。
- 输入栏在软键盘上方，SafeArea/窗口高度变化后不溢出；发出的内容不 trim 丢失换行。
- 防重复发送锁只针对正在提交的一次动作，不把整个 session 时长当成 UI 阻塞。

### 6.3 第一版附件边界

- 纯文字草稿按 peerKey 保存；不使用全局 selectedSendingFilesProvider 保存每设备文字草稿。
- 附件采用“选取并立即发送”的小流程，不支持跨设备持久化附件草稿。
- 复用 FilePickerOption/PickFileAction 的现有平台支持能力，只渲染当前可用选项。
- 由于现有 picker 会写全局 selection，第一版会话附件仅在全局 selection 为空且无活跃发送时允许。
- 选择器打开期间锁住会话发送及设备切换；取消不产生空传输。
- 不用 ClearSelectionAction 来临时保存/还原选择；它会清缓存。提交后沿用既有安全清理时机。
- 发送前做不可变文件快照，发送中切设备不能把后续选择混进原任务。
- 若上述复用无法证明不会影响缓存生命周期，停止本批，报告需要独立选择结果接口；不得自行改原生 picker。

## 7. 历史持久化与隐私

第一阶段内存验证，随后增加持久化；在持久化批次完成前不能宣称支持重启历史。

- 新增独立存储键，如 `ls_conversation_history_v1`，不复用/改写旧历史键。
- 复用 PersistenceService，支持现有便携模式；不新增 SQLite、外部服务或文件格式体系。
- 建议初始边界：最多 50 个设备、总计 500 条结束记录、序列化内容最多 2 MiB。
- 容量超限按最旧结束记录裁剪；活跃传输的内存记录不裁剪，结束后再进入持久化限额。
- 过长单条文字/错误信息允许仅持久化有界摘要，必须保存截断标志，UI 明示“历史内容已截断”。
- 不把完整附件或图片 bytes 编进 JSON；图片预览来自可访问的真实保存结果。
- 进度变化只刷新 UI，不写磁盘；摘要变化串行合并写入，防旧写入覆盖新状态。
- 删除记录和清空操作也走相同队列；防未完成的旧保存把已删除记录写回。
- JSON 无效时跳过坏记录并记脱敏日志，不删除其他设置，不让启动失败。
- 与现有保存历史开关一致：关闭后新内容不落盘，当前运行可显示；不静默删除已有历史。
- 清空当前会话/全部会话仅清记录，不删真实文件、不取消任务。
- 清除活跃任务的记录后隐藏其历史内容，仍保留最小去重状态；后续进度或完成不得重新补回被用户清除的内容。
- 文案说明文字和文件位置为本地明文记录，删除历史不等于删除文件。
- 不把文字正文、路径、PIN 或 token 写进调试 observer 描述；新增摘要 provider 应提供脱敏 describeState。

## 8. 给 Flash 的分批执行清单

所有新文件名是建议合同，实际创建前检查是否已有同职责实现。每次只执行一批，默认最多 3 个手写业务文件；测试和生成文件单独列出。大批次在开始前拆成子批，不为凑数量混入无关修改。

| 批次 | 文件范围 | 单一产出 | 完成门槛 |
| --- | --- | --- | --- |
| P0 基线 | 只读 AGENTS、首页控制器、收发 provider、相关测试 | 确认现状、工具链、导航/终态分支清单 | 不改业务文件，报告已有失败和环境缺失。 |
| P1 模型 | 新 conversation 模型、生成文件、模型测试 | 设备键、传输摘要、方向与终态合同 | 序列化、去重键、空身份测试通过。 |
| P2 内存状态 | conversation_provider、conversation_ui_provider、测试 | 摘要 upsert、草稿、选中、清除 | 重复事件、双向同 sessionId、清除后晚到事件测试通过。 |
| P3 显示投影 | conversation_view_provider、测试 | 合并附近设备/历史/活跃收发 | 同指纹不同 IP 合并；同 alias 不同指纹不合并。 |
| P4 布局组件 | 新 conversation_panel、conversation_list、conversation_entry_tile | 两栏/单栏和只读气泡 | 使用注入视图的 widget 测试；无需 Rust 初始化。 |
| P5 入口 | 新 conversation_tab、home_page、必要控制器修改 | 添加独立会话入口，旧入口保留 | 原索引/共享 PageController 正常，宽度切换和返回正常。 |
| P6a 发送模式 | send_provider、presentation 定义、测试 | 默认 legacy，可标记 conversation | 每个 session 独立；旧调用签名兼容；路由测试通过。 |
| P6b 发送记录 | send_provider、必要摘要转换工具、测试 | 接入真实 session 与全部终态 | 204 和后台成功清理前能记录；错误不伪成功。 |
| P6c 输入栏 | 新 conversation_composer、conversation_tab、测试 | 先接通纯文字发送 | 双击只发一次；文字保持原样；离线禁止发送。 |
| P7a 接收模式 | receive_controller、应用层 presentation 状态、测试 | 默认 legacy，受开关选新模式 | 不改自动接受规则；链接/WebRTC 不进入新模式。 |
| P7b 接收记录 | receive_controller、摘要转换工具、测试 | 接收准备/结果/取消/清理前记录 | sessionId 匹配，旧历史不重复新增，失败 session 不提前关闭。 |
| P7c 接收操作 | conversation_panel、必要操作 provider、测试 | 接受/拒绝/取消卡片 | 返回不拒绝，重复按钮无二次决策，legacy 请求无双按钮。 |
| P8 持久化 | persistence_provider、conversation_provider、测试 | 存储、裁剪、重启、隐私 | 写入顺序、坏 JSON、截断、清空不复活测试通过。 |
| P9a 用户控制 | settings_tab、相关设置/persistence、测试 | 新接收展示开关与历史清除入口 | 默认关闭；切换不改变活跃请求；关闭历史不落盘。 |
| P9b 附件 | composer、必要选择协调 provider、测试 | 已支持能力的附件即选即发 | 不破坏原 selection/缓存；不支持的按钮不出现。 |
| P10 文案 | en.json、zh-CN 对应实际源文件、生成文件 | 本地化所有新文案 | 沿用实际 locale 文件名，slang 与 i18n 测试通过。 |
| P11 回归 | 必要测试及验收记录 | 全量检查与四端冒烟结果 | 未跑平台明确标“未验证”，不得写四端全部通过。 |

P4 可在 P3 完成后使用 fake 数据进行 widget 测试；fake 只能存在测试目录，生产页面不能保留假在线/假消息。

P7 与 P9a 依赖同一个固定请求模式合同：开关接入完成前接收统一 legacy，不提前开放不完整接收 UI。

### 每批执行方式

1. 先阅读本批允许修改的真实文件与直接依赖，不扫描全仓库。
2. 用中文输出本批目标、文件清单、要保持的行为和测试。
3. 确认没有与用户已有改动冲突；有冲突先停，不覆盖。
4. 小步修改；关键状态、记录时机和资源生命周期补充解释性注释。
5. 运行格式化、分析和本批测试；失败时只修本批问题。
6. 将结论更新到第 11 节，完成本批后停止，等待下一批授权。

## 9. 测试与验收

### 9.1 必须覆盖的自动化测试

- 同设备换 IP、改名仍保持会话；同名不同设备分开。
- 收发双向 localSessionId 相同也不会冲突。
- 同一终态事件重复到达不多一条气泡。
- 204 文字确认、204 非文字空接受、后台文件成功均不会丢终态。
- hash 阶段与上传阶段进度不会混淆。
- busy、拒绝、PIN 取消、网络异常、部分失败、本端取消、远端取消结果准确。
- 活跃接收与另一个发送同时存在，操作不会命中错误 session。
- 窗口宽度 699/700/799/800，以及内部空间不足，布局符合合同。
- 窄屏返回只关闭详情，传输和待确认请求仍存在。
- 切设备、窗口缩放、软键盘弹起不丢草稿、不重复注册监听。
- legacy/conversation 混合任务不会互相改变导航模式。
- 清除记录后晚到进度/结束不会把内容恢复。
- 写入串行、保存历史关闭、坏 JSON、容量裁剪、重启未完成记录、截断提示。
- widget 测试使用注入的显示数据与动作，不启动实际 Rust 服务。
- 传输集成测试参考现有 Refena mock/override 方式；确需可测试性调整只抽取应用层小接口，不改真实网络算法。

### 9.2 命令

从 `app/` 运行，必须用固定工具链。已核实 `.fvmrc` 为 Flutter 3.41.9。

```bash
fvm flutter pub get
fvm dart run build_runner build
fvm dart run slang
fvm flutter analyze
fvm flutter test
```

- 只在依赖未解析时 pub get；新增模型才 build_runner；新增本地化才 slang。
- 每批用 `fvm dart format <本批具体文件>`，遵循 150 列，不全量格式化无关代码。
- 每批先跑本批具体测试文件，P11 再跑全量测试。
- 生成文件按仓库规则处理，禁止手改 `.mapper.dart` 或 `lib/gen/`。
- codegen 可能把旧 mocks 重排成 80 列。只处理可确认本次生成造成的格式噪声，不覆盖用户改动。
- 没有 FVM/SDK/依赖/设备时记录缺失，不切换系统 flutter/dart 伪造通过。
- 本次不改 Rust，因此不要求新增 Rust 测试；不得为 UI 改造运行 FRB codegen。

### 9.3 四端冒烟

| 平台 | 至少验证 |
| --- | --- |
| macOS | 宽屏两栏、缩小转单栏、长文字选取复制、拖入旧发送路径、最小化收发通知。 |
| Windows | 两栏与窄窗、路径/打开文件、PIN、原发送/链接分享仍正常。 |
| Android | 软键盘、系统返回、SAF/相册现有保存、前台通知、附件选择取消。 |
| iOS | 软键盘/SafeArea、系统文件选择、权限拒绝、保存/打开、前后台切换的原有行为。 |

至少包含 macOS 与 Android 互传文字和文件；有设备后再完成 Windows/iOS 的真实互传。跨平台共享代码不是跨平台测试证据。Linux 与 Web 单独标注范围，不计入“四端验收通过”。

## 10. 可直接交给千问 3.8 Flash 的提示词

将下面提示词与本文件一起提供。不要要求模型一次完成全部改造。

```text
你在 LocalSend 仓库执行 docs/CONVERSATION_UI_PLAN.md。
所有文件路径均相对仓库根目录；命令按方案指定的工作目录执行，不相对 docs/ 目录。
先读取 AGENTS.md、CLAUDE.md 和方案对应章节，再读取本批相关实际代码。
本次只执行【批次编号】，其他批次禁止实施。

目标：【从第 8 节复制本批单一产出】
允许修改：【列出本批具体文件，测试文件另列】
验收：【复制本批完成门槛及第 9 节相关测试】

约束：
1. Rust、协议、isolate、原生工程、依赖、Flutter 版本均不改。
2. 用 Refena，不用 Riverpod；不得猜测 API，先参考仓库真实用法。
3. legacy 为默认，旧入口兼容；background 不是会话显示开关。
4. 返回、缩放、选设备不取消传输；接收动作校验方向与 sessionId。
5. 完成摘要在清理前形成；进度不落盘；重复事件 upsert 不追加。
6. 中文说明与关键逻辑注释；只改本批文件，不顺手优化其他代码。
7. 只用 fvm flutter / fvm dart；不手改生成文件、不自动提交 Git。
8. 如 API 不符、需要越界、测试依赖缺失或用户改动冲突，停止并明确报告。

先给出本批文件级操作清单，然后按已授权范围实现和验证。
完成后只输出：修改文件、行为变化、测试结果、剩余问题。
更新 docs/CONVERSATION_UI_PLAN.md 第 11 节本批状态，然后停止，等待我授权下一批。
```

模型上下文不足时，只提供第 4～5 节合同、当前批次、第 9 节相关用例及上一批结果。不要反复让它全量重写方案或读取无关平台源码。

## 11. 执行状态与交接

本文件创建时，以下全部未执行。实施者逐批更新，不得一次性勾完。

- [x] P0 基线核实。（见下方交接记录）
- [x] P1 模型与序列化。（见下方交接记录）
- [x] P2 内存摘要和 UI 状态。（见下方交接记录）
- [x] P3 显示投影。（见下方交接记录）
- [x] P4 响应式只读组件。（见下方交接记录）
- [x] P5 会话入口。（见下方交接记录）
- [x] P6a 发送展示模式。（见下方交接记录）
- [x] P6b 发送生命周期记录。（见下方交接记录）
- [x] P6c 纯文字输入发送。（见下方交接记录）
- [x] P7a 接收展示模式。（见下方交接记录）
- [ ] P7b 接收生命周期记录。
- [ ] P7c 接收操作。
- [ ] P8 有界持久化与隐私。
- [ ] P9a 用户开关与清除。
- [ ] P9b 附件发送。
- [ ] P10 文案与代码生成。
- [ ] P11 全量回归及四端验收。

每批交接追加如下信息：

| 字段 | 填写要求 |
| --- | --- |
| 批次/日期 | 如 P1 / 实际日期。 |
| 实际变更文件 | 明确手写、测试、生成文件，列出偏离建议的原因。 |
| 已验证行为 | 对应具体测试/人工步骤，不写笼统“全部正常”。 |
| 命令与结果 | 实际命令、通过/失败/未运行及原因。 |
| 已知问题 | 明确遗留边界，不让后续模型重新猜测。 |
| 下一批入口 | 下一步只读哪些文件，使用哪些已存在接口。 |

### P0 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P0 / 2026-11-05 |
| 实际变更文件 | 仅本文档第 11 节；未改任何业务文件、测试、生成文件（符合 P0 只读约束）。 |
| 已验证行为（代码阅读核实） | 1) `HomeTab` enum 为 receive/send/settings 三值，`HomePage` 的 PageView children、NavigationRail/NavigationBar destinations 均由 `HomeTab.values` 驱动，控制器 `ChangeTabAction` 用 `tab.index` jumpToPage——P5 追加枚举值必须放在末尾并同步三处。2) `sendProvider.startSession` 返回 `Future<void>` 不返回 sessionId；`background:true` 时不 push SendPage，`_finish` 中后台全成功直接 `closeSession`（不发布 finished 状态），证实第 3 节注意事项。3) 发送终态分支：401 PIN（取消→canceledBySender）、403 declined、409 recipientBusy、429 tooManyAttempts、其他异常 finishedWithErrors；prepare 204 或 fileMap 为空 → 置 finished 后非后台立即 ChangeTab(send)+popUntilRoot+closeSession。4) 接收终态分支：quickSave 完成 → closeSession+pushRootImmediately(HomePage)+OpenFileDialog；`_cancelBySender`（waiting 时 popUntil ReceivePage）；`onCancelReceived` 只匹配 remoteSessionId+ip+status==sending。5) 接收文字历史在用户确认前即写入（onPrepareUpload 的 message 分支），会话记录不得依赖它推断接受/拒绝。6) `fileTransferProvider` 是 ChangeNotifierProvider，`closeSession` 经 `removeSession` 删除进度，进度不落盘。7) `ClearSelectionAction`/`RemoveSelectedFileAction` 空选择时触发 `ClearCacheAction`，证实不能拿全局 selection 当会话草稿。8) `ReceiveHistoryEntry` 仅 senderAlias 无 fingerprint；旧历史上限 30 条、受 `isSaveToHistory()` 控制。9) `ResponsiveBuilder` 读 `MediaQuery.of(context).size.width`（整窗口），阈值 <700/≥700/≥800，与第 1 节一致。10) PersistenceService 通过 SharedPreferences 的 `getReceiveHistory`/`setReceiveHistory`（StringList+逐条 JSON）持久化。 |
| 命令与结果 | `git status --porcelain`：通过（仅未跟踪 `docs/`，无用户改动冲突）。工具链：初检时 fvm 未安装、系统 Flutter 3.47.7 ≠ 钉定版本；随后用户安装 fvm（homebrew）与 Flutter 3.41.9，补跑验证通过：`fvm flutter --version` 输出 Flutter 3.41.9；`app/` 下 `fvm flutter pub get` 成功解析 workspace；`fvm flutter analyze` 无问题（No issues found）；`fvm flutter test` 全部 91 个测试通过，基线无已有失败。 |
| 已知问题 | 无工具链遗留。注意：后续批次新模型需 `fvm dart run build_runner build`（仅依赖解析时 pub get，仅新增本地化时 slang）；生成物格式噪声按第 9.2 节约定处理。 |
| 下一批入口 | P1 只读：`app/lib/model/persistence/receive_history_entry.dart`（dart_mappable 用法范例）、`app/build.yaml`（mapper 配置与 renamed 方法约定）、`packages/core` 无涉。新建 `app/lib/model/conversation/` 下模型 + `.mapper.dart` 生成物 + `app/test/unit/model/` 测试；不修改现有文件。 |

### P1 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P1 / 2026-11-05 |
| 实际变更文件 | 手写：`app/lib/model/conversation/conversation_models.dart`（模型+枚举集中单文件，符合 5.2 建议）。生成：`app/lib/model/conversation/conversation_models.mapper.dart`（build_runner 产物，未手改）。测试：`app/test/unit/model/conversation_models_test.dart`。另：仅改本文档第 11 节；未修改任何现有业务文件。偏离说明：枚举最初按 app 层 SendMode 先例用 plain enum，实测 dart_mappable 4.8 报 "Unknown type"，改回 isolate 层 `@MappableEnum` 做法（FileType/DeviceType 同样）；codegen 曾重写 `mocks.mocks.dart`/`assets.gen.dart`，已按仓库规则还原。 |
| 已验证行为 | 合同内容：`ConversationPeer`（peerKey/fingerprint可空/alias/deviceType，`stablePeerKey`=小写指纹派生、`temporaryPeerKey`=一次性 uuid、`peerKeyFor(null/空/空白)` 产生互不相同临时键、`isStable`）；`ConversationEntry`（entryId = `direction.name:localSessionId`，双向同 sessionId 不冲突；UTC createdAt/finishedAt；text 原样保留换行）；`ConversationFileSummary`（fileId/fileName/fileType/size/独立 outcome/path/savedToGallery/error，不持传输对象）；`ConversationOutcome` 覆盖准备/等待/传输/完成/部分失败/拒绝/忙碌(409)/tooManyAttempts(429)/双向取消来源/failed/incomplete。测试：12 个用例覆盖序列化往返（Map+字符串）、去重键、空身份、UTC 时间保留，全部通过。 |
| 命令与结果 | `fvm dart run build_runner build`：成功（第二次仅写 1 输出）。`fvm dart format <本批 2 文件>`：0 changed。`fvm flutter analyze`：No issues found。`fvm flutter test test/unit/model/conversation_models_test.dart`：12/12 通过。全量 `fvm flutter test`：103/103 通过，无回归。 |
| 已知问题 | 模型层无遗留。提醒：`MappableEnum` 生成全局 mapper 注册代码在 part 文件内，首次使用需确保 `MappableBase.ensure/ensureAll` 已触发（直接调用实例 `toJson()`/`serialize()` 路径已由测试验证）；P2 若通过 `MappableType` 工具批量转换需补充 ensure。持久化上限/裁剪逻辑不在模型层（属 P8）。 |
| 下一批入口 | P2 只读：`app/lib/provider/receive_history_provider.dart`（Redux 测试范式）、`app/test/unit/provider/receive_history_provider_test.dart`（`ReduxNotifier.test` 用法）、`app/lib/provider/persistence_provider.dart`（isSaveToHistory 接口）。新建 `conversation_provider.dart`、`conversation_ui_provider.dart` + 测试；基于 P1 的 `ConversationEntry.buildEntryId`/`ConversationPeer.peerKeyFor` 实现 upsert、草稿（按 peerKey 纯文字）、选中、清除；不修改现有文件。 |

### P2 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P2 / 2026-11-05 |
| 实际变更文件 | 手写：`app/lib/provider/conversation_provider.dart`（摘要层 ReduxProvider）、`app/lib/provider/conversation_ui_provider.dart`（UI 层 NotifierProvider）。测试：`app/test/unit/provider/conversation_provider_test.dart`、`app/test/unit/provider/conversation_ui_provider_test.dart`。另：仅改本文档第 11 节；未修改任何现有业务文件与 P1 模型文件。偏离说明：终态判定 `isTerminal` 扩展放在 provider 文件内而非模型层（避免动 P1 已验收文件）；P2 无持久化依赖，`ConversationService` 构造无参（P8 再接 PersistenceService，参考 receiveHistoryProvider 演进路径）。 |
| 已验证行为 | 摘要层：1) `EnsureTransferEntryAction` 以真实 sessionId 建记录（entryId=direction:localSessionId），重复 ensure 幂等不追加；peer 按 peerKey upsert（同指纹改名合并、临时键互不合并、不与稳定键混用）。2) `UpsertTransferSnapshotAction` 原位替换（重复终态事件气泡数不变）、乱序可容忍（未 ensure 直接快照可追加）、超 500 上限只淘汰最旧终态、活跃传输永不淘汰（全活跃时宁可不裁）。3) 清除三件套（单条/按设备/全部）写 tombstone `clearedEntryIds`，晚到的 upsert/ensure 均不复活内容；清除只记录不触碰 peers/文件/传输。UI 层：selectPeer/backToList 保留选中、切设备不丢他设备草稿、空文本即删键、文字原样保留换行不 trim、clearDraft 幂等不产生新状态对象。 |
| 命令与结果 | `fvm dart format <本批 4 文件>`：初跑 2 文件被修正为 150 列，终跑 0 changed。`fvm flutter analyze`：No issues found。`fvm flutter test <本批 2 文件>`：21/21 通过。全量 `fvm flutter test`：124/124 通过（103 基线 + 21 新增），无回归。期间修复：`NotifierProvider` 构造需 `(ref) { return ...; }` 形式（Refena 3.5，仓库先例 selected_receiving_files_provider）；测试 helper 指纹参数需可空。 |
| 已知问题 | 1) tombstone 集合无上限（P8 持久化时需一并定义重启后是否恢复清除状态——重启后 tombstone 应为空，否则跨重启误杀新记录；当前内存层重启即空，天然正确）。2) `ConversationState` 未做 dart_mappable（纯内存不需要；P8 需为持久化定义独立 DTO 或补注解）。3) entries 顺序为创建顺序（最旧在前），UI 分组/倒序渲染由 P4 决定。4) 无 UI 接入，本批界面不可见变化（预期）。 |
| 下一批入口 | P3 只读：`app/lib/provider/network/nearby_devices_provider.dart`（附近设备状态与 Device 模型字段）、`favorites_provider` 及其测试（列表合并范式）。新建 `conversation_view_provider.dart` + 测试：合并 `conversationProvider` peers/entries、`nearbyDevicesProvider` 在线设备、发送/接收活跃 session 为轻量视图；门槛是同指纹不同 IP 合并为一个会话、同 alias 不同指纹不合并。使用 P1 `ConversationPeer.peerKeyFor`/P2 `ConversationState` 已定义接口。 |

### P3 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P3 / 2026-11-05 |
| 实际变更文件 | 手写：`app/lib/provider/conversation_view_provider.dart`（`ConversationPeerView` 视图类 + `buildConversationPeerViews` 纯投影函数 + `conversationPeerViewsProvider` ViewProvider 接线）。测试：`app/test/unit/provider/conversation_view_provider_test.dart`。另：仅改本文档第 11 节；未修改任何现有文件。设计决策：投影核心做成纯函数（方案 9.1"只抽取应用层小接口"），测试不建 RefenaContainer、不依赖 Rust/isolate；ViewProvider 仅做 watch 接线（仓库先例 send_tab_vm）。 |
| 已验证行为 | 门槛①同指纹不同 IP 合并：历史 peer(fp:aaaa) 与在线 Device(AAAA) 归并为单视图，取最新 Device（含最新 ip，发送时由 UI 直接取 view.device）；指纹大小写差异经 peerKeyFor 规范化不分裂。门槛②同 alias 不同指纹不合并：两台同名设备两个视图。其余：在线无历史设备进列表（entryCount=0）；离线历史 peer 保留（online=false、device=null，UI 据此禁用发送，不变量 8 用"在线/未发现"语义）；lastEntry 取 createdAt 最新；活跃发送（SessionStatus.waiting/sending）标 hasActiveSend、终态不标；接收 session 仅匹配当前发送者 hasActiveReceive（终态不标）；排序在线优先再按最后记录倒序。 |
| 命令与结果 | `fvm dart format <本批 2 文件>`：0 changed。`fvm flutter analyze`：No issues found（初跑因测试缺 import ConversationState 报错 10 个，补 import 后干净）。`fvm flutter test <本批文件>`：10/10 通过。全量 `fvm flutter test`：134/134 通过（124 基线 + 10 新增），无回归。 |
| 已知问题 | 1) 投影未接入任何 UI（P4/P5 消费）；`conversationPeerViewsProvider` 尚未被任何 widget 测试覆盖（接线需真实 container，P4 用 override 或注入 fake 视图列表测试）。2) signalingDevices 的不信任合并细节（同指纹多设备）由 `NearbyDevicesState.allDevices` 已有逻辑处理，本层未重复实现；加密关闭/无指纹设备的临时会话在投影中与历史临时 peer 自然对齐（peerKey 为 tmp: 前缀）。3) 排序规则是基线非最终 UI 合同（P4 可再分组）。 |
| 下一批入口 | P4 只读：`app/lib/widget/responsive_builder.dart`（已读，阈值 700/800）、现有 widget 测试范例 `app/test/widget/favorite_edit_dialog_test.dart`（RefenaScope overrides 范式）。新建 `conversation_panel.dart`、`conversation_list.dart`、`conversation_entry_tile.dart`（建议放 `app/lib/widget/conversation/` 或 `app/lib/pages/conversation/`，实施时定）+ widget 测试：使用注入的 `ConversationPeerView`/`ConversationEntry` fake 数据（仅测试目录），不启动 Rust；两栏条件 `>=800 且自身约束 >=620`。 |

### P4 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P4 / 2026-11-05 |
| 实际变更文件 | 新建：`app/lib/widget/conversation/conversation_panel.dart`（响应式两栏/单栏 + 详情顶栏 + 气泡区）、`conversation_list.dart`（设备列表）、`conversation_entry_tile.dart`（只读气泡），均在 `app/lib/widget/conversation/`。修改：`app/assets/i18n/en.json`（新增顶层 `conversation` 节点：empty/selectDevice/offline/expand/collapse + `outcome` 12 个状态文案）。生成（slang 产物，未手改）：`lib/gen/strings.g.dart`、`strings_en.g.dart`。测试：`app/test/widget/conversation_panel_test.dart`。未修改任何现有页面/传输 provider。 |
| 已验证行为 | 门槛：窗口>=800 且自身>=620 才两栏（ResponsiveBuilder 判窗口 + LayoutBuilder 判自身，方案第 1 节）；700～799 单栏点选进详情；窗口 1000 但自身 600 回退单栏。单栏详情 PopScope 接管返回 + 返回按钮同容器切回列表（不 push 新页）。只读展示：双向气泡、离线设备"离线"提示保留历史、空态文案、活跃收发 spinner、超长文字(>300字符)折叠展开、文本 SelectableText 可选中复制、文件行含名称/大小/单文件结果图标。组件全部为 dumb 参数化组件（数据+回调进，不 watch provider），fake 数据仅存测试目录。 |
| 命令与结果 | `fvm dart run slang` 成功（仅 2 个生成文件变更）。`fvm dart format <本批文件>` 终跑 0 changed。`fvm flutter analyze`：No issues found。`fvm flutter test test/widget/conversation_panel_test.dart`：9/9。全量 `fvm flutter test`：143/143（134 基线 + 9 新增），含 i18n_test 通过（新 en.json 键不需补 _missing_translations，非英文 locale 回退 en）。修复过程：初版 tile 在 ListView 中 Column 未设 mainAxisSize.min 导致无限高断言、ListTile/SelectableText 缺 Material 祖先（组件自包 Material.transparency）、测试断言误用顶栏设备名判列表存在（改 byType(ListTile)）。 |
| 已知问题 | 1) 面板未接入任何页面（P5 入口）；接入时需包 Scaffold（本组件自包 Material 故也能独立渲染）。2) 自动滚到底仅做了 reverse 锚定最新的基础形态，"用户接近底部才跟随滚动"的精细规则属 P6/P7 接入批。3) 按日期分组、图片缩略图属 P7b；PIN/权限弹窗交互属 P5+。4) 图片占位仅图标，无缩略图。5) `_formatSize` 为组件内私有简单实现，若 P7 需要统一格式再抽 util。 |
| 下一批入口 | P5 只读：`app/lib/pages/home_page.dart`（HomeTab enum、PageView children、导航 destinations、控制器索引四处一致性逐一核对）、`app/lib/provider/conversation_ui_provider.dart`（选中/草稿已有）。新会话入口 tab 追加在 enum 末尾；接线壳（watch conversationPeerViewsProvider/conversationUiProvider 传给 ConversationPanel）建议单独文件 `conversation_tab.dart`，默认不改变旧页面行为；widget 测试用 RefenaScope overrides 注入。 |

### P5 交接记录（2026-11-05）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P5 / 2026-11-05 |
| 实际变更文件 | 新建：`app/lib/pages/tabs/conversation_tab.dart`（纯接线壳）、`app/test/widget/conversation_tab_test.dart`。修改：`app/lib/pages/home_page.dart`（HomeTab enum 末尾追加 `conversation(Icons.forum)` + label case + PageView children 追加 ConversationTab，四处一致性：destinations 由 HomeTab.values 自动驱动无需改）；`app/lib/widget/conversation/conversation_panel.dart`（新增 `showDetailOnNarrow` 参数，默认 true，接 P2 showDetailOnMobile 语义）；`app/assets/i18n/en.json`（conversation.title）。生成：slang 2 文件。 |
| 已验证行为 | 首页新增"会话"tab（index 3，原三 tab 索引不变——全仓 grep 确认 HomeTab 引用均按枚举名、无硬编码索引）。接线：conversationPeerViewsProvider（P3 投影，真实 watch nearby/send/server 四源）+ conversationProvider.entries + conversationUiProvider（选中/窄屏详情）→ 面板；selectPeer/backToList 路由正确。widget 测试：宽屏两栏点选并存、窄屏进入详情+返回切回列表（验证 backToList 保留 selectedPeerKey 但 showDetailOnMobile=false 的 P2 语义）、空态。测试用 `ViewProvider.overrideWithBuilder` 注入 fake 投影 + 向真实 conversationProvider dispatch EnsureTransferEntryAction 播种（气泡区渲染 entries 而非 lastEntry）。 |
| 命令与结果 | `fvm dart run slang` 成功。`fvm dart format <本批文件>` 终跑 0 changed。`fvm flutter analyze`：No issues found（初跑因误用 refena addons 的 ConsumerWidget 签名报错 9 个，改仓库先例 StatelessWidget + context.watch/context.ref 后干净）。`fvm flutter test <本批文件>`：4/4。全量：147/147（143 基线 + 4 新增），P4 面板 9 用例无回归。 |
| 已知问题 | 1) 会话 tab 现在只读：无输入栏/发送（P6a/P6b）、无接受拒绝卡片（P7c）、无清除菜单（P8）。2) 待确认的接收请求在 legacy 下仍跳旧 ReceivePage（presentation 机制属 P6a，默认 legacy 不变——本批零行为变化）。3) 首页 drop 文件仍跳 send tab（旧路径不变）。4) 测试里 RefenaScope 无 overrides 时 conversationProvider/ui 用真实实例（纯内存安全），若未来 ui 依赖持久化需改 override。 |
| 下一批入口 | P6a 只读：`app/lib/provider/network/send_provider.dart` 的 `startSession` 签名与 `_finish`/`background` 分支（P0 已核实：不返回 sessionId、后台成功直接 closeSession 不发布 finished）、`send_tab_vm.dart` 的 onTapDevice 调用点。目标：`TransferPresentation` 枚举（legacy/conversation）+ startSession 可选参数默认 legacy + 每 session 存 presentation（Dart 应用层，不进 isolate）；会话 tab 的输入栏发送走 conversation 分支不 push SendPage。门槛：旧调用点语义不变（默认 legacy），新 session 的 presentation 独立保存不用全局 tab 猜测。 |

### P6a 交接记录（2026-11-06）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P6a / 2026-11-06 |
| 实际变更文件 | 新建：`app/lib/model/conversation/transfer_presentation.dart`（纯内存枚举 legacy/conversation，无 @MappableEnum：不持久化、不被 mappable 模型引用）、`app/lib/provider/transfer_presentation_provider.dart`（`transferPresentationProvider`：sessionId→presentation 映射，只为非 legacy 记录条目）、`app/test/unit/provider/transfer_presentation_provider_test.dart`。修改：`app/lib/provider/network/send_provider.dart`（startSession 新增可选参数 `presentation` 默认 legacy；conversation 时强制 background=true 复用不开页流程；创建时 set、closeSession 时 remove、clearAllSessions 时 clearAll）。未改任何旧调用点、未动 Rust/isolate/协议。无新增 UI 文案（枚举值不展示），本批无需翻译。 |
| 已验证行为 | 门槛：旧调用点语义不变——全仓 grep 确认 startSession 仅 4 处调用且全在 `send_tab_vm.dart`（legacy 路径），可选参数默认值使其零修改兼容；presentation 每 session 独立保存（测试：a 设 conversation 不影响 b；不用全局 tab 推断）；清理同步（closeSession/clearAll 移除映射；set 显式 legacy 也移除条目）；状态不可变（set/remove 产生新 Map）。conversation ⇒ background 复用：不开 SendPage（L156 分支）、不开 ProgressPage（L415 分支）、fileMap.isEmpty 时不 ChangeTab/popUntilRoot（L389 分支），成功后自动 closeSession。 |
| 命令与结果 | `fvm flutter test test/unit/provider/transfer_presentation_provider_test.dart`：7/7。全量 `fvm flutter test`：**154/154**（147 基线 + 7 新增）。`fvm flutter analyze`：No issues found。`fvm dart format <本批文件>`：0 changed。修复过程：初版测试 `container.dispose()` 报错（RefenaContainer 的 dispose 是实现 Ref 接口的 provider 级方法，容器销毁用 `disposeContainer()`）+ import 字母序（conversation/ 在 cross_file 前）。 |
| 已知问题 | 1) conversation 分支目前无真实调用方（P6c 会话输入栏才发起 conversation 发送），P6a 仅机制就绪。2) startSession 仍不返回 sessionId（P0 已核实）；P6b 的记录逻辑在 send_provider 内部完成（自知 sessionId），若 P6c 需外部关联再新增方法不改旧签名。3) conversation session 的 background=true 意味着成功终态在 _finish 里直接 closeSession 不发布 finished——P6b 必须在 closeSession 前写入记录（方案 7.2 已点名此坑）。 |
| 下一批入口 | P6b 只读：`send_provider.dart` 的 `_finish`（L505：成功+background 直接 closeSession 分支）、`fileMap.isEmpty` 早退（L380）、`cancelSessionByReceiver`（L745）、401/403/409/429 错误分支；P2 的 `EnsureTransferEntryAction`/`UpdateTransferEntryAction`（conversation_provider.dart）；`transferPresentationProvider.get` 判断是否记录。目标：仅 conversation session 写会话记录（legacy 不写，避免双轨），全部终态覆盖，错误不伪成功；204/取消/拒绝都有对应 outcome。门槛：旧 legacy 路径仍不产生任何会话记录；重复事件 upsert 不追加。 |

### P6b 交接记录（2026-11-06）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P6b / 2026-11-06 |
| 实际变更文件 | 新建：`app/lib/provider/network/conversation_send_recorder.dart`（`ConversationSendRecorder`：onSessionCreated/update/onTransferring/onTerminalSnapshot 四个接入方法 + `outcomeFromFileStatus` 纯转换；内部 `_isConversation` guard，legacy 全部空操作）、`app/test/unit/provider/conversation_send_recorder_test.dart`。修改：`app/lib/provider/network/send_provider.dart`（接入点：创建后登记 preparing、校验和完成后 waiting、401 PIN 取消→canceledBySender、403→declined、409→busy、429→tooManyAttempts、default/外层 catch/响应解析 catch→failed+error、fileMap.isEmpty（204）→finished 先记录再 closeSession、sending→onTransferring（无 token 标 skipped）、_finish 后台成功 closeSession 前终态快照、_finish else 分支 partialFailure/finished、cancelSession→canceledBySender（先记录再取消）、cancelSessionByReceiver→canceledByReceiver）。未动 Rust/isolate/协议/旧页面。无新增 UI 文案（记录器只写数据，展示已由 P4 完成），本批无需翻译。 |
| 已验证行为 | 门槛：旧 legacy 路径不产生任何会话记录（测试：未记 presentation 时四个接入方法全空操作，entries/peers 空）；重复事件 upsert 不追加（两次 waiting+一次 transferring 仍 1 条）；错误不伪成功（failed/partialFailure 带 error，终态盖 finishedAt UTC）；204 和后台成功清理前能记录（onTerminalSnapshot 设 in closeSession 之前，测试验证状态转换全集 finished→success/failed→failure/skipped→skipped/queue・sending→pending）；tombstone 不复活（先 Remove 后 update 仍空）；未登记直接 update 不凭空造记录。entryId = 'send:sessionId'，peerKey = fp:小写指纹。 |
| 命令与结果 | `fvm flutter test <本批文件>`：9/9。全量 `fvm flutter test`：**163/163**（154 基线 + 9 新增）。`fvm flutter analyze`：No issues found。`fvm dart format lib test`：0 changed。修复过程：初版测试 CrossFile 缺 required lastModified/lastAccessed、FileDto 缺 required metadata、import 字母序（model/dto/ 在 model/file_status 前）、singleOrNull 需 package:collection（仓库先例）。 |
| 已知问题 | 1) 会话记录目前仍无真实产生源：conversation 分支需 P6c 会话输入栏发起才会触发（旧 send_tab 全 legacy 不写记录，预期行为）。2) 进度不落盘也不进记录（方案：进度只刷 UI），气泡内无实时百分比，属 P7 展示层。3) 403/409/429 分支记录后 session 仍保留在 sendProvider 中（既有行为，非本批范围）。4) 文字发送（preview 嵌入）的 kind=text/text 字段登记属 P6c（记录器 onSessionCreated 当前固定 kind=file）。 |
| 下一批入口 | P6c 只读：`conversation_panel.dart` 详情区（加输入栏位置）、`conversation_ui_provider.dart`（draft per peerKey）、`send_provider.startSession` 的 presentation 参数（P6a 已就绪）、`CrossFile` 文字构造先例（send_tab_vm 的 message 发送流程：fileType=text + bytes=UTF8 + preview）。目标：会话详情输入栏→startSession(presentation: conversation)，文字不 trim 不丢换行，kind=text 登记（记录器需支持 text），发送后自动滚底；草稿按 peerKey 已有。门槛：旧 SendTab 不受影响；离线设备禁用发送；conversation 发送全程不离开会话容器。 |

### P6c 交接记录（2026-11-06）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P6c / 2026-11-06 |
| 实际变更文件 | 新建：`app/lib/widget/conversation/conversation_composer.dart`（dumb 输入栏：multiline TextField + 发送按钮；提交锁 `_locked` 防双击；文字原样不 trim；离线 enabled=false 禁发不禁输入）、`app/test/widget/conversation_composer_test.dart`。修改：`app/lib/provider/network/conversation_send_recorder.dart`（onSessionCreated 新增可选 `text` 参数：非空时 kind=text、files 置空；新增静态 `extractMessageText`——判断条件与协议 preview 内嵌条件严格一致：单文件 + FileType.text + bytes 非空）、`app/lib/provider/network/send_provider.dart`（登记调用传 `text: extractMessageText(files)`）、`app/lib/widget/conversation/conversation_panel.dart`（新增 required 参数 draftText/onDraftChanged/onSendText，详情 Column 底部挂 composer，`ValueKey(peerKey)` 切设备重建不串输入）、`app/lib/pages/tabs/conversation_tab.dart`（`_sendText`：文字→UTF8 单 text CrossFile（沿用 AddMessageAction 协议格式：uuid.v4().txt）→ startSession(presentation: conversation) + clearDraft；草稿接线 updateDraft/drafts）、i18n 4 文件（conversation.composeHint/send 的 en/简体/繁体翻译）→ slang 生成。未动 Rust/isolate/协议/旧 SendTab。 |
| 已验证行为 | 门槛四项：双击只发一次（提交锁 + 清空输入框 + onChanged('')，重新输入非空才解锁——锁的是"一次提交动作"而非 session 时长，符合方案 6.2）；文字保持原样（`  hello\nworld  ` 前后空格与换行全保留，tab_test 断言 utf8 原文含尾部空格）；离线禁止发送（composer enabled=false 时 onPressed=null，tab_test 断言零 startSession 调用，历史仍可看）；conversation 发送全程不离开会话容器（background=true 复用 P6a 不开页路径，测试只断言一次调用参数）。附带：发送后 clearDraft（drafts 不含该 peerKey）、kind=text 登记原文、extractMessageText 与协议 preview 条件不分叉（多文件/非 text/无 bytes 均返回 null 仍按 file 登记）。 |
| 命令与结果 | `fvm flutter test <本批 4 文件>`：34/34（composer 8 + tab 6 + panel 12 + recorder 11）。全量 `fvm flutter test`：**175/175**（163 基线 + 12 新增）。`fvm flutter analyze`：No issues found。`fvm dart format --set-exit-if-changed lib test`：0 changed。修复过程：composer_test 误用 `test()` 传 tester 参数（flutter_test 带 WidgetTester 必须 `testWidgets`）8 处；tab_test 误用 Riverpod 式 API——`Override` 类型不存在（refena_flutter scope.dart 为 `List<ProviderOverride>`）、NotifierProvider 的 override 是 `overrideWithNotifier`（refena notifier_provider.dart:33）而非 `overrideWith`；panel_test 一处内联 ConversationPanel 构造漏传 P6c 三个新必填参数。 |
| 已知问题 | 1) 发送后未自动滚底（composer 提交即清空气泡区追加，列表滚动位置不追踪新气泡）——纯内存 widgets 量小影响有限，属 P7 展示打磨。2) composer 不处理发送失败重试：失败终态由 P6b 记录器写入气泡（failed+error），但输入内容已清空不回填。3) 会话内文件发送（非纯文字）尚未接入：面板无选文件入口，选文件仍走旧 SendTab（legacy），属 P7/P8 范围。4) 消息无实时"发送中"气泡反馈时序依赖 P6b 的 waiting/transferring 更新，文字 session 极快时可能直接从 preparing 跳终态。 |
| 下一批入口 | P7a 只读：`app/lib/provider/network/server/controller/receive_controller.dart`（prepare/insert 请求处理入口）、`server_provider.dart` 的事件路由、presentation 机制（复用 P6a 的 `transferPresentationProvider`，接收侧需在 Dart 应用层决定——受设置开关控制，默认 legacy）。目标：接收会话可按开关标记 conversation 展示模式，不改自动接受规则（autoAccept 逻辑保持）、链接/WebRTC 请求不进入新模式。门槛：legacy 接收行为零变化；presentation 判定不猜全局状态。 |

### P7a 交接记录（2026-11-06）

| 字段 | 内容 |
| --- | --- |
| 批次/日期 | P7a / 2026-11-06 |
| 实际变更文件 | 修改：`app/lib/model/conversation/transfer_presentation.dart`（新增顶层纯函数 `decideReceivePresentation({enabled, viaWebUpload})`：开关开 且 非链接上传→conversation，否则 legacy）、`app/lib/provider/persistence_provider.dart`（新键 `ls_conversation_receive_enabled`，getter 默认 false）、`app/lib/model/state/settings_state.dart`（新字段 `conversationReceiveEnabled`，@MappableClass 需重新生成 mapper——已跑 build_runner）、`app/lib/provider/settings_provider.dart`（init 读取 + `setConversationReceiveEnabled`，仿 setReceiveViaLinkAutoAccept 模式）、`app/lib/provider/network/server/controller/receive_controller.dart`（onPrepareUpload 创建 session 前固定 presentation 并 set 映射；closeSession 同步 remove）。未动 Rust/isolate/协议/自动接受逻辑/旧页面跳转。无新增用户可见文案（开关 UI 属 P9a），本批无需翻译。codegen 噪声：mocks.mocks.dart（80列重写）与 flutter run 顺带改动的 pbxproj/Podfile.lock 已按既定规则恢复。 |
| 已验证行为 | 门槛：legacy 接收行为零变化——开关默认 false 时 decideReceive 恒返回 legacy 且不写映射（不碰 set），接收的全部分支（quickSave/ReceivePage push/消息历史）代码路径未动；presentation 判定不猜全局状态——只输入两个事实：设置开关 + `server.getState().webUpload`（现有请求路径字段，L137 同款用法）；链接（web 上传页）永远 legacy 即使开关开；WebRTC 走独立路径（webrtc_receiver.dart，grep 确认不经过 receive_controller）天然隔离；创建时固定（方案 5.3：切换开关不影响已接受 session，因为判定只在 onPrepareUpload 发生一次）；清理同步（closeSession remove，onPrepareUpload 开头旧 session 的 closeSession 也走同一路径）。 |
| 命令与结果 | `fvm flutter test <本批+ P6a 回归>`：10/10（新增 3 + presentation provider 7）。全量 `fvm flutter test`：**178/178**（175 基线 + 3 新增）。`fvm flutter analyze`：No issues found。`fvm dart format --set-exit-if-changed lib test`：0 changed。`fvm dart run build_runner build`：成功（仅 settings_state.mapper 更新，mocks 噪声已恢复）。 |
| 已知问题 | 1) 开关目前无 UI（设置页开关属 P9a），只能代码/prefs 修改；且 conversation 标记在接收侧尚无可见效果——页面跳转仍走 legacy ReceivePage（P7c 才改路由，方案 L258：开关接入完成前接收统一 legacy，不提前开放不完整接收 UI）。2) 接收标记后 P7b 才写记录；本批只建映射不写会话。3) `_cancelBySender` 不关 session（既有行为），presentation 映射随后续 closeSession 清理，与 fileTransferProvider 节奏一致。4) SettingsState 新增 required 字段对旧持久化无影响（无 JSON 存档路径，init 从 prefs 默认 false）。 |
| 下一批入口 | P7b 只读：`receive_controller.dart` 的 onPrepareUpload（登记 preparing/waiting）、acceptFileRequest（skipped 文件）、onFileUpload/onFileUploadResult（transferring/终态）、closeSession（终态快照必须在清理前：removeSession 会删 fileTransferProvider 进度）、_cancelBySender（canceledBySender）、declineFileRequest（declined）；复用 P6b 的 `ConversationSendRecorder` 模式但方向为 receive（entryId = 'receive:sessionId'，EnsureTransferEntryAction/UpsertTransferSnapshotAction 已支持 direction）。目标：仅 conversation 接收 session 写会话记录，legacy 不写；旧 receiveHistoryProvider 行为不变（双轨不重复）。门槛：sessionId 匹配；失败 session 不提前关闭；记录在清理前形成。 |

## 12. 停止与撤回策略

- 第一版不删除旧页面、不覆盖旧历史、不迁移原始文件；新入口可停止使用，接收展示开关可关闭。
- 关闭会话接收开关只影响后续请求，已运行任务按原模式继续，不做静默迁移。
- 新记录保存失败仅提示/脱敏记录，不取消传输；修复记录层不修改网络层。
- 发现需修改协议、isolate、原生权限、信任校验或缓存所有权时，停止当前批次，请人工重新确认范围。
- 有未通过测试或未验证平台时，不把该批次/平台标记完成。
- 禁止通过删除用户文件、覆盖工作区、重置仓库或重建持久化设置来“恢复可运行状态”。

最终验收标准：新增会话界面可真实收发、准确保留有界记录，并且旧收发功能、安全行为和资源生命周期没有回归；不是仅凭截图相似就视为完成。
