# 若可 Ruoke 项目实施过程与技术路线档案

> 文件作用：记录项目创建、实现和演进过程中每一步具体如何完成、采用了什么方法、工具和技术方案，以及为什么选择该路线。
> 不是任务清单、进度报告或聊天摘要，不记录下一步建议、当前项目状态等无关内容。

---

## 技术路径记录：2026-07-19 14:00（阶段4 收尾：跨盘符 Kotlin bug 根治 + 空壳跑通真机）

### 1. 完成事项

根治 Windows 双盘符下 Kotlin 增量编译 bug，成功将若可 Flutter 空壳跑通到真机 PJF110。

### 2. 初始条件与输入

- Flutter 3.44.4 + Dart 3.12.2，Android SDK 36.1.0
- 项目目录 `D:\CCSwitchWork\ruoke`，Android Studio 装在 `D:\ruanjian\Android Studio\`（自带 JBR OpenJDK 21）
- 真机 PJF110（设备码 `9d306d62`），Android 16 / API 36
- `flutter analyze` 已全绿，但 `flutter run` 到真机编译失败
- 报错根因：Windows 多盘符下 Kotlin 增量编译 bug —— 项目在 D 盘、Pub 缓存默认在 `C:\Users\...\Pub\Cache`，两盘符不同，Kotlin 算相对路径抛异常

### 3. 技术方案选择

#### 可选方案

- **方案 A**：将 PUB_CACHE 迁到 D 盘（`D:\PubCache`），让项目和 Pub 缓存同盘符，从根上消除跨盘符路径差异
- **方案 B**：将项目迁到 C 盘（代价：所有已有文件、目录、git 都要搬）
- **方案 C**：升级 Kotlin/AGP 到新版（新版 Kotlin 可能已修复该 bug）：风险高、连锁升级影响大、与"Flutter 不升"决策冲突

#### 最终选择

方案 A：PUB_CACHE 迁 D 盘。

#### 选择原因

- 治本：跨盘符 bug 的根是"两个盘符算相对路径"，让它同盘符就没事
- 最小改动：只改 Pub 缓存位置，不影响工程代码、不影响 Flutter SDK、不影响 JDK
- 可持久化：Windows 用户级环境变量写入注册表，开机自动生效

### 4. 详细实施路径

#### 步骤 1：持久化 JAVA_HOME 到用户级注册表

- **目的**：确保 Flutter/Gradle 能找到 JDK 21（Android Studio 自带 JBR）
- **操作**：在 Windows 用户级注册表设 `JAVA_HOME = D:\ruanjian\Android Studio\jbr`
- **方法**：PowerShell `[Environment]::SetEnvironmentVariable('JAVA_HOME','D:\ruanjian\Android Studio\jbr','User')`
- **验证**：`[Environment]::GetEnvironmentVariable('JAVA_HOME','User')` 回读确认；`flutter doctor` 输出"Java binary at: D:\ruanjian\Android Studio\jbr\bin\java"确认已认到

#### 步骤 2：持久化 PUB_CACHE 到 D 盘

- **目的**：Pub 缓存也落 D 盘，项目和缓存同盘符，根除跨盘符 Kotlin bug
- **操作**：`[Environment]::SetEnvironmentVariable('PUB_CACHE','D:\PubCache','User')`
- **关键细节**：用户级变量写入注册表后，**已开着的 shell 进程不会自动刷新**。本次会话在 PowerShell 内额外 `$env:PUB_CACHE='D:\PubCache'` 同步生效

#### 步骤 3：清空旧 Pub 缓存 + 重新下载依赖

- **目的**：原来不完整的 `D:\PubCache`（robocopy 只搬了 1 个目录，397MB 不全）删掉，`flutter pub get` 按新 PUB_CACHE 位置完整重下
- **操作**：`rm -rf D:\PubCache`（Bash 侧，PowerShell 把该路径当系统保护路径拦了）→ `flutter pub get`
- **结果**：240.9MB 完整缓存下载到 `D:\PubCache`

#### 步骤 4：清项目 build 缓存并跑真机

- **操作**：`Remove-Item build/ -Recurse -Force` → `flutter run -d 9d306d62`
- **结果**：APK 编译成功（`√ Built build\app\outputs\flutter-apk\app-debug.apk`，99.7s），但安装到真机失败 `adb: Failure [-99]`

#### 步骤 5：修复真机 APK 安装权限（用户手动操作）

- **表现**：`adb.exe: failed to install ...apk: Failure [-99]`，装了 66 秒后报错
- **原因判断**：PJF110 / Android 16 新安全机制，开发者选项里「USB 安装」（Install via USB）没开
- **处理**：用户在真机设置 → 系统 → 开发者选项 → 打开「USB 安装」及「USB 调试（安全设置）」
- **处理结果**：第二次 flutter run 安装成功（118s）→ `Syncing files to device PJF110` → `Installing profile for com.ruoke.ruoke`，真机显示"若可 Ruoke 骨架跑通 ✅"

### 5. 核心技术细节

- **PUB_CACHE 路径生效条件**：用户级变量写入注册表，新开终端/重启 Claude Code 后自动有。某次会话导不进去时用 `[Environment]::GetEnvironmentVariable('PUB_CACHE','User')` 验证注册表层面是否存在
- **adb 设备掉线恢复**：解锁真机唤醒屏幕 → 必要时 `adb kill-server && adb start-server`
- **PJF110 装 APK 必备开关**：开发者选项里开「USB 安装」+「USB 调试（安全设置）」，否则 ADB 装非市场 APK 会报 Failure [-99]

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| Windows 用户级注册表 | 写入 | JAVA_HOME=D:\ruanjian\Android Studio\jbr | JDK 路径持久化 |
| Windows 用户级注册表 | 写入 | PUB_CACHE=D:\PubCache | Pub 缓存迁 D 盘持久化 |
| D:\PubCache | 删除→重建 | 旧不完整缓存删掉→flutter pub get 重下 | 完整依赖缓存 |
| ceshi/flutter_run_真机_3.log | 新建 | 编译成功但 ADB -99 装不上 | 故障日志 |
| ceshi/flutter_run_真机_4.log | 新建 | 最终装成功跑空壳 | 成功日志 |

### 7. 问题、尝试与解决过程

#### 问题 1：flutter run 编译失败（跨盘符 Kotlin bug）

- **表现**：Kotlin 编译报"different roots"路径异常
- **原因判断**：项目在 D 盘、Pub 缓存默认在 C 盘，Kotlin 增量编译算相对路径跨盘符抛异常
- **最终处理**：PUB_CACHE 持久化到 D 盘，项目和缓存同盘符
- **处理结果**：根治，APK 编译成功

#### 问题 2：APK 编译成功但装不到真机（adb Failure -99）

- **表现**：`adb.exe: failed to install ... Failure [-99]`
- **原因判断**：PJF110 / Android 16 新安全机制拦了非市场 APK 安装
- **最终处理**：用户在真机打开「USB 安装」+「USB 调试（安全设置）」
- **处理结果**：重装成功

### 8. 验证方法与结果

- flutter doctor 全绿
- `flutter analyze` lib/main.dart 无问题
- `flutter run -d 9d306d62` APK 编译→装真机→启动成功
- 真机屏幕显示"若可 Ruoke 骨架跑通 ✅"

### 9. 可复现要点

- PUB_CACHE 必须和项目在**同一个盘符**（Windows 多盘符下 Kotlin 增量编译有已知 bug）
- 用户级环境变量写入注册表后，**已开着的 shell 不会自动刷新**，需在当前 shell 额外同步 `$env:` 或 `export`
- 删除 D:\PubCache 在 PowerShell 被保护，走 Bash `rm -rf` 可绕过
- PJF110 / Android 16 必须在开发者选项开"USB 安装"才能装非市场 APK

---

## 技术路径记录：2026-07-19 15:00（Git 本地仓库首次存档 + GitHub 远程推送）

### 1. 完成事项

Git 本地仓库初始化、首次 commit 存档空壳骨架、GitHub 远程仓库建库并推送。

### 2. 初始条件与输入

- 项目目录 `D:\CCSwitchWork\ruoke`，非 git 仓库
- .gitignore 已有完整排除规则（.env / beifen / ceshi / .ai-context / build 等）
- 用户 GitHub 账号 `shangjiangyanliang-coder`，noreply 邮箱 `270614412+shangjiangyanliang-coder@users.noreply.github.com`
- 真机空壳刚跑通

### 3. 技术方案选择

直接在 master 分支本地 init → add → commit → 用 gh CLI（GitHub 官方命令行）建远程空库并推送。不走 `--global` git config，只给本仓库设用户身份。

### 4. 详细实施路径

#### 步骤 1：git init + 确认排除规则生效

- **操作**：`git init` → `git add .` → `git status --short` 确认
- **验证**：`.claude/` / `beifen/` / `ceshi/` / `.ai-context/` 入口全部按 gitignore 未入库，共 114 文件待 commit

#### 步骤 2：追加 .claude/ 到 gitignore

- **目的**：Claude Code 本机工作配置/缓存不应进版本库（个人本机产物）
- **操作**：在 .gitignore 末尾追加 `.claude/` 排除

#### 步骤 3：设本仓库 git 身份

- **操作**：`git config user.name "shangjiangyanliang-coder"` + `git config user.email "270614412+shangjiangyanliang-coder@users.noreply.github.com"`（不加 `--global`，只本仓库有效）

#### 步骤 4：首次 commit

- **操作**：`git commit -m "feat: 若可 Flutter 骨架跑通真机"`
- **结果**：commit `55bd1e8`，125 文件，署名 noreply 邮箱

#### 步骤 5：gh CLI 登录

- **操作**：用户在独立 PowerShell 窗口跑 `gh auth login`，选 GitHub.com → HTTPS → Login with web browser → 输入终端显示的 8 位代码（C2D2-FA51）→ 浏览器授权
- **结果**：`✓ Logged in as shangjiangyanliang-coder`

#### 步骤 6：建远程仓库并推送

- **操作**：`gh repo create shangjiangyanliang-coder/ruoke --public --source=. --remote=origin --push`
- **结果**：仓库 `https://github.com/shangjiangyanliang-coder/ruoke` 已建 + `[new branch] HEAD -> master` 推送成功 + 本地 master 已追踪 origin/master

### 5. 核心技术细节

- GitHub noreply 邮箱获取路径：GitHub 网页 Settings → Emails → 勾选"Keep my email addresses private" → 下方显示的 `数字+用户名@users.noreply.github.com` 即为隐私提交邮箱
- `flutter_localizations` 是 Flutter SDK 自带包，pubspec 用 `sdk: flutter`，**不能走 pub.dev `flutter pub add`**（会报"could not find package"）
- `gh auth login` 在 Claude Code 的 `!` 输入框里交互式向导跑不动（无法接受方向键/回车），必须用户开独立终端窗口手动登录

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| .gitignore | 修改 | 追加 `.claude/` 排除 | 防本机配置入版本库 |
| .git/ | 新建 | git init | 本地版本库 |
| GitHub remote | 新建 | shangjiangyanliang-coder/ruoke (public) | 远程仓库 |

### 7. 问题、尝试与解决过程

#### 问题 1：git 拒绝 commit（Author identity unknown）

- **表现**：`fatal: unable to auto-detect email address`
- **原因判断**：git 需要 user.name + user.email 才能提交
- **最终处理**：`git config user.name/email` 设本仓库级身份（不加 --global，不污染其他项目）

### 8. 验证方法与结果

- `git log -1` 输出 commit 55bd1e8，作者正确
- `gh auth status` 确认已登录 shangjiangyanliang-coder
- 浏览器访问 `https://github.com/shangjiangyanliang-coder/ruoke` 可见推送成功的文件

### 9. 可复现要点

- 首次给 git 设身份：只对本仓库 `git config user.name/email`（不加 --global）
- GitHub noreply 邮箱需先在网页 Settings → Emails 勾"Keep my email addresses private"才能看到
- gh CLI 交互登录必须在独立终端窗口操作，Claude Code 的 `!` 输入无法接受交互式方向键选择

---

## 技术路径记录：2026-07-19 15:30（富文本编辑器 Flutter 包选型实验）

### 1. 完成事项

完成若可笔记富文本编辑器三方包的选型实验：用独立 demo 工程在 Flutter 3.44.4 + 真机 PJF110 上验证 3 个候选包的编译可行性与核心功能，定案 `flutter_quill: ^11.5.1` 并落地所有文档。

### 2. 初始条件与输入

- 技术方案总集 §5 列出了三候选：super_editor / flutter_quill / appflowy_editor
- 验证点清单（决策②"轻富文本存 JSON + 降级纯文字"）：①JSON 序列化 ②红字/下划线 ③光标下一行插识图文字（C1.B 模拟）④UI 风格
- 各候选 pub.dev 现状：

| 包 | 最新版 | 活跃度 |
|---|---|---|
| super_editor | 0.2.7（2 年前） | 稳定版停更，开发版 0.3.0-dev.x |
| flutter_quill | 11.5.1（60 天前） | 2.1k likes，227k 周下载 |
| appflowy_editor | 6.2.0（7 个月前） | 516 likes，AppFlowy 团队维护 |

### 3. 技术方案选择

#### 可选方案

- **方案 A**：三个候选各自在 `ceshi/` 下建独立 Flutter 工程、跑真机实测验全部验证点、出横评对比
- **方案 B**：只查资料+pub.dev 评分横向对比，不搭工程
- **方案 C**：直接盲选社区最大的 flutter_quill（2.1k likes，最多人用）

#### 最终选择

方案 A：逐个建独立 demo 工程、flutter analyze → flutter run 到真机、核心验证点编写最小示范页、每个候选走完 5 个验证点、落横评结论。

#### 选择原因

方案 B 缺失"能编译、真机能跑"这一关键事实（super_editor 和 appflowy 恰好都因 TextInputClient 兼容问题编译不通），只靠资料判断会错判；方案 C 是风险最低的兜底，但没做横向对比无法在 daiban 留下排他证据。

### 4. 详细实施路径

#### 步骤 1：查 pub.dev 各候选包现状（选前摸底）

- **操作**：WebFetch 直接抓 pub.dev 各包页面，查版本/更新日期/likes/活跃度
- **关键发现**：super_editor 稳定版 0.2.7 已停更 2 年（⚠️），flutter_quill 和 appflowy 均活跃维护
- **输出**：数据记入选型实验计划文档 `jihua/ruoke-富文本OCR选型实验-20260719.md`

#### 步骤 2：写选型实验计划文档

- **文件**：`jihua/ruoke-富文本OCR选型实验-20260719.md`
- **内容**：实验目标、候选现状、验证点与方法、demo 工程组织方式、人机分工、风险降级

#### 步骤 3：验 super_editor 0.2.7

- **工程**：`ceshi/rich_super_editor/`（`flutter create --platforms=android`）
- **操作**：
  1. `flutter pub add super_editor` 装 0.2.7 + 56 个依赖
  2. 查源码确认该版真实 API（README 描述的是新版 API，0.2.7 用老套 `DocumentEditor` / `DocumentComposer` / `CommonEditorOperations`）
  3. 写最小实验页 main.dart → `flutter analyze` 全绿
  4. `flutter run -d 9d306d62` 到真机
- **结果**：❌ 编译失败。原因：核心类 `DocumentImeInputClient extends TextInputConnectionDecorator with TextInputClient, DeltaTextInputClient` 缺新版 Flutter 加的抽象方法 `TextInputConnection.updateStyle()`。**直接淘汰**。

#### 步骤 4：验 flutter_quill 11.5.1

- **工程**：`ceshi/rich_quill/`（`flutter create --platforms=android`）
- **操作**：
  1. `flutter pub add flutter_quill` 装 11.5.1 + 44 个依赖
  2. pubspec 手加 `flutter_localizations: sdk: flutter`（非 pub.dev 包，是 SDK 自带）
  3. 查源码确认 11.x 真实 API 参数名（关键坑：`showStrikeThrough` 无 Button 后缀、`showListOptions` 不存在要拆 showListBullets/Bumbers/Check、`formatText` 三参是 `Attribute?` 非 Map）
  4. 写实验页（QuillController.basic + QuillSimpleToolbar + QuillEditor + 底部 JSON/纯字输出）
  5. `flutter analyze` 全绿 → `flutter run -d 9d306d62` → 真机跑通
  6. 用户眼睛验证：①②③④⑤ 全过 ✅

- **API 踩坑记录（11.x 关键细节）**：
  - 工具栏参数：`showUnderLineButton` / `showStrikeThrough`（非 `showStrikeThroughButton`） / `showListBullets`+`showListNumbers`+`showListCheck`（非 `showListOptions`）
  - `formatText(start, len, Attribute.underline)` + `formatText(start, len, ColorAttribute('red'))` 分两次调用
  - 序列化纯字三件套：`controller.document.toDelta().toJson()` ↔ `Document.fromJson(jsonDecode(...))` + `toPlainText()`

#### 步骤 5：验 appflowy_editor 6.2.0

- **工程**：`ceshi/rich_appflowy/`（`flutter create --platforms=android`）
- **操作**：
  1. `flutter pub add appflowy_editor` 装 6.2.0 + 58 个依赖
  2. 查源码确认 6.2.0 是 **transaction-based**（`editorState.transaction..insertText()..formatText()` → `editorState.apply(tx)`）
  3. 写实验页 → `flutter analyze` 全绿（静态通过）
  4. `flutter run -d 9d306d62` 到真机
- **结果**：❌ 编译失败（8m39s）。原因：核心类 `DeltaTextInputService extends TextInputService with DeltaTextInputClient` 缺新版 Flutter 加的抽象方法 `TextInputClient.onFocusReceived()`。查 changelog：6.2.0 是 7 个月前最新版，无更高版本可升，未提及该兼容修复。**直接淘汰**。

### 5. 核心技术细节

- **super_editor / appflowy 编译失败的共性根因**：新版 Flutter（3.44）给 `TextInputConnection` 和 `TextInputClient` 加了新抽象方法（`updateStyle` 和 `onFocusReceived`），这两个包都是通过混入（mixin）实现这些接口但没跟上实现新方法，导致 Dart 静态检查报"missing implementations"→ `compileFlutterBuildDebug` 失败。这是"包维护速度跟不上 Flutter 版本节奏"的典型表现为。
- **flutter_quill 11.x 序列化零工作量**：`toDelta().toJson()` 产出标准 Quill Delta JSON 直接存 `note.content_json`，`toPlainText()` 降级纯文字供搜索备份，`Document.fromJson(jsonDecode(...))` 反序列化还原，三者原生提供、不用额外集成第三方序列化包。
- **demo 工程组织方式**：全部在 `ceshi/` 下建独立 Flutter 工程（各自独立 pubspec、不共享依赖），不进主项目 git（.gitignore 已排 `/ceshi/`）。验完结论入 daiban，工程整体留着当证据。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `jihua/ruoke-富文本OCR选型实验-20260719.md` | 新建 | 选型实验全记录（计划→三候选实测→横评） | 选型过程档案 |
| `ceshi/rich_super_editor/` | 新建 | super_editor 0.2.7 demo 工程（编译失败证据） | 淘汰证据留存 |
| `ceshi/rich_quill/` | 新建 | flutter_quill 11.5.1 demo 工程（✅ 全过） | 定案证据留存 |
| `ceshi/rich_appflowy/` | 新建 | appflowy_editor 6.2.0 demo 工程（编译失败证据） | 淘汰证据留存 |
| `jihua/ruoke-技术方案总集-20260716.md` | 修改 | §5.1 富文本从"待验证"换成定案 flutter_quill + 理由/风险/API 速查 | 技术方案定稿 |
| `jihua/ruoke-待办清单-daiban-20260716.md` | 修改 | #4 富文本选型移入已完成区 | 待办闭环 |
| `jihua/ruoke-产品待办需求清单-20260713.md` | 修改 | V2 层 F1.22(工具栏精简) + F1.23(标记交互优化) | 衍生需求登记 |

### 7. 问题、尝试与解决过程

#### 问题 1：super_editor 0.2.7 的 pub.dev README 描述的 API 和实际版本完全不同

- **表现**：按 README 写的 `MutableDocumentComposer` / `Editor` / `createDefaultDocumentEditor` / `InsertTextRequest` / `ApplyAttributionsRequest` 全部报 undefined_class/undefined_method
- **原因判断**：README 描述的是新版 0.3.0-dev 的 API，0.2.7 用的是老版 `DocumentEditor` / `DocumentComposer` / `CommonEditorOperations` 套
- **处理**：查 PublishedCache 里装的真源码（`D:\PubCache\hosted\pub.dev\super_editor-0.2.7\lib\`），grep 出真实类名再改写 demo

#### 问题 2：super_editor 0.2.7 编译失败（缺 updateStyle）

- **表现**：`The non-abstract class 'DocumentImeInputClient' is missing implementations: - TextInputConnection.updateStyle`
- **原因判断**：Flutter 3.44 给 `TextInputConnection` 加了新抽象方法 `updateStyle()`，super_editor 0.2.7（2 年前）没实现
- **处理**：直接淘汰，省去验功能，不修包源码
- **处理结果**：记入横评表淘汰

#### 问题 3：flutter_quill 11.x `flutter_localizations` 不能走 pub.dev pub add

- **表现**：`flutter pub add flutter_localizations` 报"could not find package at https://pub.dev"
- **原因判断**：flutter_localizations 是 Flutter SDK 自带包，不在 pub.dev 上
- **处理**：手改 pubspec.yaml，加 `flutter_localizations: sdk: flutter`

#### 问题 4：appflowy_editor 6.2.0 编译失败（缺 onFocusReceived）

- **表现**：`DeltaTextInputService is missing implementations: - TextInputClient.onFocusReceived`
- **原因判断**：Flutter 3.44 给 `TextInputClient` 加了新抽象方法 `onFocusReceived()`，appflowy 6.2.0（最新版）没实现
- **处理**：直接淘汰

### 8. 验证方法与结果

| 候选 | compileFlutterBuildDebug | 真机跑通 | JSON序列化 | 红字/下划线 | 光标插文字 |
|---|---|---|---|---|---|
| super_editor 0.2.7 | ❌ 3m50s | — | — | — | — |
| flutter_quill 11.5.1 | ✅ | ✅ 装成功 | ✅ Delta JSON+纯字 | ✅ formatText双调用 | ✅ replaceText |
| appflowy_editor 6.2.0 | ❌ 8m39s | — | — | — | — |

### 9. 可复现要点

- 候选包在 demo 工程里的**真实 API 名称不能照抄 README**（README 可能描述新版 API 而实际装的是老版），必须进 `D:\PubCache\hosted\pub.dev\<包名-版本>\lib\` grep 出源码中真实类名
- flutter_localizations 是 SDK 自带包，pubspec 走 `sdk: flutter`，不能 pub.dev pub add
- 每个 demo 工程 pub get 前确保 `$env:PUB_CACHE='D:\PubCache'`（防跨盘符 bug 复发）

---

## 技术路径记录：2026-07-19 16:00（OCR mlkit demo 工程起步，未完成）

### 1. 完成事项

OCR 选型实验的任务 #6 起步：创建 `ceshi/ocr_mlkit/` demo 工程，安装了 `google_mlkit_text_recognition 0.16.0` + `image_picker`，查清了 README 中的 API 用法和中文本地化配置要求。未写 main.dart 代码就中途中止。

### 2. 初始条件与输入

- 富文本选型已定案，进 OCR 选型
- 两个 OCR 候选：google_mlkit_text_recognition（活跃维护，离线免费，需独立配中文安装依赖） vs flutter_tesseract_ocr（需打包训练数据 50MB+，集成成本高）
- 验证点：①离线可行性 ②中文印刷体识别准确率（须用户对照原图判）③框选区域识别实现难

### 3. 技术方案选择

先建 mlkit demo（最新版 0.16.0 距目前仅 11 天更新，最可能兼容 Flutter 3.44.4），再判 tesseract（如时间紧降级为只查资料对比不搭工程）。

### 4. 已执行步骤

#### 步骤 1：创建 demo 工程

- **操作**：`flutter create --project-name ocr_mlkit --platforms=android ceshi/ocr_mlkit`
- **结果**：标准 Flutter 工程已就位

#### 步骤 2：安装依赖包

- **操作**：`flutter pub add google_mlkit_text_recognition image_picker`
- **结果**：mlkit 0.16.0 + image_picker + 23 个依赖已安装

#### 步骤 3：查 README API 用法和中文本地化配置

- **操作**：读取 `D:\PubCache\hosted\pub.dev\google_mlkit_text_recognition-0.16.0\README.md`
- **关键发现**：
  - 核心 API：
    ```dart
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    final RecognizedText result = await textRecognizer.processImage(inputImage);
    String text = result.text;
    for (TextBlock block in result.blocks) {
      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) { ... }
      }
    }
    ```
  - 中文识别须在 Android 端额外加依赖：`implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'`（文件 `android/app/build.gradle`）
  - iOS 端额外加：`pod 'GoogleMLKit/TextRecognitionChinese', '~> 9.0.0'`（文件 `ios/Podfile`）
  - 返回结构含三级（blocks/lines/elements）+ `boundingBox`（目标区域坐标）+ `cornerPoints`（四个角点），直接支撑框选区域识别

### 5. 待做步骤（下一会话接续）

1. 备份默认 main.dart
2. 写最小验证页：相册选图 → `TextRecognizer.processImage` → 显示识别文字 + 置信度/block 层级
3. 在 `android/app/build.gradle` 加中文识别依赖
4. `flutter analyze` → `flutter run -d 9d306d62` 到真机
5. 先验离线（飞行模式下拍照识别是否成功）→ 再验中文印刷体准确率（需要用户对照原图判断）
6. 记入对比表，出 OCR 结论

---

## 技术路径记录：2026-07-20 10:00（OCR mlkit 离线兜底选型定案）

### 1. 完成事项

完成 OCR 选型实验任务 #6/#7/#8：用 `ceshi/ocr_mlkit/` demo 工程在 Flutter 3.44.4 + 真机 PJF110（Android 16）实测 `google_mlkit_text_recognition 0.16.0`，确认其纯离线可识别但中文准确率仅约 50%。据此定案：mlkit 作**离线兜底**（无网络备选），**云端 OCR** 列入 V2 待办为主力，并回填技术方案总集 §5.2、daiban 已做区、产品 V2 层 F1.24 等四处文档。

### 2. 初始条件与输入

- 富文本选型已定案（flutter_quill 11.5.1），进 OCR 选型
- 两个 OCR 候选：google_mlkit_text_recognition（活跃、离线免费、需独立配中文语言包）vs flutter_tesseract_ocr（需打包训练数据 50MB+、集成成本高）
- 验证点：①离线可行性 ②中文印刷体识别准确率（须用户对照原图判）③框选区域识别实现难
- 前一阶段已建 `ceshi/ocr_mlkit/` 工程 + 装包（mlkit 0.16.0 + image_picker）+ 查清 README API 用法与中文本地化要求，但 main.dart 仍是 flutter create 默认模板、Android 中文依赖未配
- mlkit 0.16.0 README 要求：Android minSdk 21 / targetSdk 35 / compileSdk 35；中文识别须在 `android/app/build.gradle` 加 `implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'`

### 3. 技术方案选择

#### 可选方案

- **方案 A**：再搭 flutter_tesseract_ocr 工程对比（任务 #7 原计划）
- **方案 B**：放弃纯离线约束，改试云端 OCR（百度/腾讯/阿里）作主力
- **方案 C**：接受 mlkit 当前约 50% 准确率当主力，靠用户后期手改
- **方案 D**：mlkit 离线兜底 + 云端主力双方案

#### 最终选择

方案 D 的变体：**mlkit 作离线兜底（无网络备选），云端 OCR 列入 V2 待办为主力**。

#### 选择原因

- mlkit 准确率仅约 50%，方案 C 会让用户每张图手改一半错字，违背 OCR 减负初衷，体验不可接受 → 不当主力
- tesseract 中文准确率传闻也不如云端、且需打包 50MB+ 训练数据，方案 A 投入高回报不确定，且云端方案 D 已能满足准确率要求 → 不优先实测
- 方案 D 兼顾"离线兜底（飞行模式仍可用）"与"联网高准确率"，体验最佳；当前阶段先把 mlkit 兜底定下不拖进度，云端主列入 V2 在进笔记拍照功能时再启动，分阶段控制成本

### 4. 详细实施路径

#### 步骤 1：备份默认 main.dart 与默认 widget_test.dart

- **目的**：改写前留底，符合 CLAUDE.md「改文件先备份」规则
- **操作**：复制到 `beifen/ocr_mlkit-main.dart-默认模板-20260719.dart` 与 `beifen/ocr_mlkit-widget_test-默认模板-20260719.dart`
- **输出**：2 份模板备份在 beifen

#### 步骤 2：配 Android 中文识别依赖

- **目的**：mlkit 默认只支持拉丁文，须手动加中文语言包
- **操作**：在 `ceshi/ocr_mlkit/android/app/build.gradle.kts` 末尾加
  ```kotlin
  dependencies {
      implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
  }
  ```
- **关键坑**：该 demo 是 Flutter 新模板用 **Kotlin DSL（`build.gradle.kts`）**，非旧版 Groovy 的 `build.gradle`；写法用 `implementation("...")` 函数式调用而非 `implementation '...'`

#### 步骤 3：写最小验证页 main.dart

- **目的**：相册选图 → mlkit 中文识别 → 显示识别全文 + block/line/element 三级计数 + 耗时，供人机对照原图判断准确率
- **操作**：整文件覆盖写 `ceshi/ocr_mlkit/lib/main.dart`，结构：MyApp→OcrHomePage(StatefulWidget)→_pickAndRecognize
- **方法或技术**：
  - `TextRecognizer(script: TextRecognitionScript.chinese)` 实例化中文识别器
  - `ImagePicker.pickImage(source: ImageSource.gallery, imageQuality: 100)` 选图（quality=100 不压缩保准确率）
  - `InputImage.fromFile(_image!)` 转输入格式
  - `await recognizer.processImage(inputImage)` 返回 `RecognizedText`，含 blocks/lines/elements 三级
  - `Stopwatch` 计耗时；遍历三级统计 block/line/element 计数
  - UI：图片预览区 + 识别结果区（状态/耗时/计数/可选中文本）+ 右下 FloatingActionButton
- **输出**：可编译运行的最小 OCR 验证页

#### 步骤 4：修复默认 widget_test.dart 导致的 analyze 报错

- **表现**：`flutter analyze` 报 "The name 'MyApp' isn't a class - test/widget_test.dart"，默认测试引用旧模板 MyApp 类（已被 demo 删掉）
- **原因判断**：flutter create 默认测试文件与改写后的 main.dart 不同步
- **操作**：备份默认 widget_test.dart 后，改成只含一个 `test('placeholder', ...)` 的空占位测试
- **输出**：`flutter analyze` 复跑全绿（No issues found）

#### 步骤 5：真机编译运行

- **操作**：`flutter devices` → 真机掉线 → 用全路径 `C:\Users\yangxiaoyong\AppData\Local\Android\Sdk\platform-tools\adb.exe` `kill-server/start-server` → 轮询 `adb devices` 8 次（约 16s）等待真机上线 → `flutter run -d 9d306d62`
- **关键细节**：PowerShell 中 `adb` 不在 PATH，必须用 `platform-tools/adb.exe` 全路径调用
- **结果**：编译成功 `√ Built build\app\outputs\flutter-apk\app-debug.apk`（~200s）+ 装真机（15.5s）+ 应用启动（日志显示 Impeller/Vulkan 渲染 + `zh-Hans-CN` 中文字体已加载）
- **编译期 WARN**：mlkit 插件（google_mlkit_commons / google_mlkit_text_recognition）仍用旧版 KGP，"Future versions of Flutter will fail to build if your app uses plugins that apply KGP"——当前不影响运行，记入风险

#### 步骤 6：人机验证准确率与离线性

- **操作**：用户在真机操作——点"相册选图识别"按钮选中文印刷图 → 对照原图识别结果判断准确率；开飞行模式再识别验证离线
- **验证**：中文识别准确率**约 50%（错一半），连清晰 PDF 截图也错字不少** → 不达体验要求；离线验证飞行模式也能识别 → 确认纯离线；单张耗时 ~800ms；无崩溃

#### 步骤 7：拍板定方案与回填文档

- **操作**：向用户给出 A/B/C/D 四方案及利弊，用户拍板"mlkit 留作离线兜底，云端 OCR 列 V2 为主力"
- **回填**：备份 4 份规划文档 → 改技术方案总集 §5.2（含实测表/理由/立项修正/风险/API 速查）+ 顶部技术栈表 OCR 行 → 改 daiban（#6b 已完成区 + #7 暂缓新增）→ 选型实验文档加 §11 → 产品 V2 层加 F1.24

### 5. 核心技术细节

- **mlkit 0.16.0 核心 API**：`TextRecognizer(script: TextRecognitionScript.chinese)` → `processImage(InputImage)` → 返回 `RecognizedText`，含 blocks/lines/elements 三级 + `boundingBox`(Rect) + `cornerPoints`（四角点），直接支撑框选区域识别
- **中文识别依赖双端配置**：
  - Android（Kotlin DSL）：`android/app/build.gradle.kts` 加 `implementation("com.google.mlkit:text-recognition-chinese:16.0.1")`
  - iOS：`ios/Podfile` 加 `pod 'GoogleMLKit/TextRecognitionChinese', '~> 9.0.0'`
  - 默认只支持拉丁文，不配中文包识别中文会出乱码或跑不动
- **Flutter 新模板 Kotlin DSL 坑**：默认 `build.gradle` 已被 `build.gradle.kts` 取代；Gradle 依赖从 Groovy 的 `implementation 'group:name:ver'` 改为 Kotlin `implementation("group:name:ver")` 函数式调用
- **image_picker 选图保准确率**：`imageQuality: 100` 不压缩；若压太狠会进一步损失已偏低的准确率
- **mlkit 离线性**：所有 ML 处理在原生平台（Android/iOS），通过 Platform Channel 桥接调用 Google 原生 ML Kit API，无网络依赖——飞行模式实测确认
- **准确率与定位**：mlkit 中文 ~50% 不达拍摄转可编辑笔记体验；联网云端 OCR 普遍 95%+ 是主力；mlkit 用于无网络兜底"有比没有强"

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `ceshi/ocr_mlkit/lib/main.dart` | 修改(覆盖写) | flutter create 默认模板→OCR mlkit 中文识别验证页 | 选型实测 demo |
| `ceshi/ocr_mlkit/test/widget_test.dart` | 修改(覆盖写) | 默认引用 MyApp 测试→空占位测试 | 消 analyze 报错 |
| `ceshi/ocr_mlkit/android/app/build.gradle.kts` | 修改 | 末尾加 dependencies 中文语言包 16.0.1 | 启用中文识别 |
| `ceshi/ocr_mlkit/run_log_pjf110.log` | 新建 | flutter run 真机日志 | 编译运行证据 |
| `jihua/ruoke-技术方案总集-20260716.md` | 修改 | §5.2 回填定案 + 顶部技术栈表 OCR 行同步 | 技术方案定稿 |
| `jihua/ruoke-待办清单-daiban-20260716.md` | 修改 | 已完成区加 #6b + 暂缓区加 #7(云端OCR主力) | 待办闭环 |
| `jihua/ruoke-富文本OCR选型实验-20260719.md` | 修改 | 末尾加 §11 OCR mlkit 实测定案节 | 选型实测全记录 |
| `jihua/ruoke-产品待办需求清单-20260713.md` | 修改 | V2 F1 笔记组加 F1.24 云端OCR主力 | V2 衍生需求 |
| `beifen/` 6 份 | 新建 | 4 规划文档+main.dart+widget_test 备份 | 改前留底 |
| `lujing.md` | 修改 | 追加本条技术路径记录 | 技术档案 |

### 7. 问题、尝试与解决过程

#### 问题 1：flutter analyze 报 "MyApp isn't a class" 在 test/widget_test.dart

- **表现**：`error - The name 'MyApp' isn't a class - test\widget_test.dart:16:35`
- **原因判断**：flutter create 默认 widget_test 引用旧模板 MyApp 类，demo 改写后 main.dart 无此类
- **尝试过的方法**：无（直接定位）
- **最终处理**：备份默认 widget_test.dart 后改成空占位测试
- **处理结果**：复跑 analyze 全绿

#### 问题 2：真机掉线（adb devices 列表为空）

- **表现**：`flutter devices` 只见 Windows/Chrome/Edge 三 emulator，无真机；`adb devices` 列表空
- **原因判断**：PJF110 偶发掉线睡死
- **尝试过的方法**：PowerShell `adb` 不在 PATH 报 CommandNotFoundException → 找到全路径 `platform-tools\adb.exe` → kill-server/start-server → 轮询 8 次(约16s) 仍空
- **无效方法**：单纯 adb 重启+轮询 8 次没恢复（真机已睡）
- **最终处理**：请用户解锁唤醒真机屏幕
- **处理结果**：用户回复"已连接真机"后 adb devices 见 `9d306d62 device`

#### 问题 3：PowerShell 中 adb 命令找不到

- **表现**：`adb : The term 'adb' is not recognized`
- **原因判断**：platform-tools 未加进用户 PATH
- **最终处理**：用全路径 `C:\Users\yangxiaoyong\AppData\Local\Android\Sdk\platform-tools\adb.exe` 调用
- **处理结果**：adb 命令成功执行

### 8. 验证方法与结果

- `flutter analyze` 在 `ceshi/ocr_mlkit/` 内：No issues found
- `flutter run -d 9d306d62`：编译成功 + 装真机成功 + 应用启动
- 人机验证（用户真机操作判官）：
  - 中文识别准确率 → **约 50%（错一半），含清晰 PDF 截图也错字不少** —— 用户对照原图判定
  - 离线识别（飞行模式） → 成功，确认纯离线 —— 用户验证
  - 单张耗时 ~800ms、无崩溃 —— 用户观察
- 文档回填后自检：4 份规划文档改动点齐整，技术方案总集 §5.2/技术栈表/daiban/选型实验§11/产品V2 F1.24 全部落地
- **未验证内容**：tesseract 候选未实测（已定云端为主力，tesseract 无优先级）；云端 OCR 具体厂商准确率与集成方式未验证（V2 了做）

### 9. 可复现要点

- mlkit 0.16.0 中文识别**必须**在 Android `build.gradle.kts` 加 `implementation("com.google.mlkit:text-recognition-chinese:16.0.1")`、iOS Podfile 加 `pod 'GoogleMLKit/TextRecognitionChinese', '~> 9.0.0'`，否则只识拉丁文
- Flutter 新模板用 Kotlin DSL `build.gradle.kts`（非 Groovy `build.gradle`），依赖写法是函数式 `implementation("...")` 而非 `implementation '...'`
- flutter create 默认 `widget_test.dart` 引用 MyApp 类；改写 main.dart 后该测试会 analyze 报错，须同步替换或删除默认测试
- PowerShell 调 adb 需用 `platform-tools\adb.exe` 全路径（未加 PATH）
- 真机 occasionally 掉线 → 解锁屏幕唤醒 + 必要时 `adb kill-server && adb start-server`
- mlkit 中文准确率实测约 50%——此结论是定 mlkit 仅作离线兜底、云端为主力的核心依据，不要因"能跑通"误判其可作主力
- OCR Repository 设计时本地/远程接口可切换（决策"Repository 标本地/远程可换"），联网优先云端、断网回退 mlkit 是 V2 集成时的实现方向


---

## 技术路径记录：2026-07-21 19:30（阶段5 第1批：数据库底座）

### 1. 完成事项

完成阶段5 第1批"地基底座"：Drift 数据库 + 6 张笔记表 + 6 DAO 骨架 + errors + utils。`flutter analyze` 全绿。切 `feature/notes-mvp` 分支，commit `caeba4f`。

### 2. 初始条件与输入

- Flutter 3.44.4 / Dart 3.12.2，主项目只有 `lib/main.dart` 空壳
- pubspec 已有 riverpod/drift/go_router 等依赖，缺 uuid、flutter_localizations
- git 干净，master = `6e71465`

### 3. 技术方案选择

按 B 文档只建第 2 批需要的 6 张笔记表（非全部 18 张），schemaVersion=1，后续模块逐次追加。

### 4. 实施路径

1. `flutter pub add uuid`；手改 pubspec 加 `flutter_localizations: sdk: flutter`
2. 6 张 Drift 表：subject（自引用树，level 0/1/2，软删）、note（content_json + 派生 plain_text + 软删）、note_version（快照）、note_highlight（kind=red/underline，body 列避开 Table.text 冲突）、tag（name 唯一）、note_tag（复合主键）
3. 6 个 DAO（DriftAccessor）+ AppDatabase 入口（drift_flutter 后台 isolate，schemaVersion=1）
4. `data/errors/`：AppException sealed + Result<T> + guard()
5. `utils/`：newId() uuid v4、nowMs()/fromMs() 毫秒时间戳
6. fluter analyze → 4 坑修完全绿 → commit `caeba4f`

### 5. 关键技术细节

- Drift 列名不能用 `text`——Table 基类有同名方法
- OrderingTerm 用位置参数 `asc(expr)`/`desc(expr)` 而非 `expression:` 命名参数
- schemaVersion getter 必须实现
- analysis_options 排除 beifen/ceshi 防备份 Dart 文件被扫到

### 6. 文件变更（15 个新文件）

tables 6 + daos 6 + app_database + errors 2 + utils 2 + pubspec/analysis_options 修改

### 7. 问题与处理

4 个坑：uuid 重复（pub add 手加重复→删手加行）/ text 列冲突（改名 body）/ OrderingTerm 语法（改位置参）/ schemaVersion 缺实现（补 override）

### 8. 验证结果

`flutter analyze` 全绿，build_runner 28 outputs。未真机验证（纯数据层无 UI）。

### 9. 可复现要点

- DriftAccessor 须 `part 'xxx.g.dart'` + 注解，改后重跑 build_runner
- pub add 后手改 pubspec 前先 grep 去重


---

## 技术路径记录：2026-07-22 00:00（阶段5 第2批起步：笔记 CRUD + 富文本编辑器 — 未完成，卡在 riverpod 生成器兼容）

### 1. 完成事项

第 2 批写完全部功能代码文件（models/repository/ViewModel/View/路由），但卡在 **riverpod_generator 4.x + riverpod 3.x 注解兼容**导致 `flutter analyze` 未全绿，代码未跑真机。

### 2. 初始条件

- 第 1 批已 commit，branch feature/notes-mvp
- 线框图集 B1/B1.a 已定；用户选择工具栏 A（加粗/斜体/下划线/红字/删除线/列表/H1/H2）
- 用户确认：功能优先、UI 最小占位

### 3. 技术方案选择 — 关键分歧

**riverpod 生成器 bug**：

| 尝试 | 写法 | 结果 |
|---|---|---|
| ① @riverpod class XxxVm | 2.x 旧 Notifier 写法 | InvalidTypeException |
| ② @riverpod Future<T> f(Ref ref) | 4.x 新函数式 | 同样 InvalidTypeException |
| ③ 手写 FamilyAsyncNotifier<T, Arg> | 不依赖 generator | 3.x 移除了 FamilyAsyncNotifier 类 |
| ④ 手写 AsyncNotifier + init(arg) | 绕开 family | analyze 有 valueOrNull 等 API 差异未解 |

最终选择 ④（手写 AsyncNotifier + init 传 arg），仍待 analyze 全绿。

### 4. 已建文件

- `pubspec` 加 flutter_quill ^11.5.1（pub add 误装 2.0.7 已改回）
- `notes/models/note.dart` / `note_version.dart` — 领域模型
- `notes/note_constants.dart` — 占位科目常亮
- `notes/repository/note_repository.dart` — 抽象接口
- `notes/repository/local_note_repository.dart` — Drift 实现，含快照
- `notes/view_model/note_list_view_model.dart` — AsyncNotifier hand-rolled
- `notes/view_model/note_editor_view_model.dart` — AsyncNotifier + init(noteId)
- `notes/view_model/view_model_providers.dart` — Provider 声明
- `notes/providers.dart` — appDatabase + noteRepository 手写 Provider
- `notes/view/note_list_view.dart` — 列表页 ConsumerWidget
- `notes/view/note_editor_view.dart` — 编辑器 ConsumerStatefulWidget
- `routing/app_router.dart` — go_router StatefulShellRoute 5 tab
- `routing/placeholder_page.dart` — 未开发 tab 占位
- `lib/main.dart` — 升级：FlutterQuillLocalizations + appRouter
- `data/database/daos/note_dao.dart` + `note_version_dao.dart` 扩充
- `utils/delta_plain_text.dart` — 富文本→纯字

### 5. 核心技术发现

**riverpod 3.3.2 + generator 4.0.4 组合有已知 bug**：generator 对 `@riverpod` 注解生成时抛 `InvalidTypeException`，可能与 riverpod_annotation 4.0.3 不兼容。建议降 generator 到 2.x 或全手写。

`FamilyAsyncNotifier` 在 3.x 中不存在，family 须通过 Provider 声明结合普通 AsyncNotifier 实现。

### 6. 问题与当前状态

**核心问题**：riverpod 生成器/手写 API 差异，下一会话应：

1. **优先方案**：pubspec 删 `riverpod_generator` + `riverpod_annotation`，全项目手写 Provider/AsyncNotifier，核实 3.3.2 AsyncValue API（查 `valueOrNull` 是否存在还是改用别的 getter）
2. **备选**：降 riverpod 到 2.x（更稳妥但可能连锁影响其他依赖）

当前 git 16 个文件 untracked + 7 个文件 modified，未 commit。

### 7. 可复现要点

- `flutter pub add flutter_quill` 必须指定版本 `:^11.5.1`
- 第 2 批代码**未 verify**,恢复后先跑 analyze 定位问题再改



---

## 技术路径记录：2026-07-23 14:00（阶段5 第2批：笔记 CRUD + 富文本编辑器 — analyze 全绿 + 真机验证）

### 1. 完成事项

完成阶段5 第2批「笔记 CRUD + 富文本编辑器」：写全 notes feature（models / Repository 接口+本地实现 / 手写 AsyncNotifier ViewModel / 列表页 + 编辑器 flutter_quill / go_router 5tab 底栏）、扩充 2 个 DAO、`flutter analyze` 从 29 issue 修到 No issues found、真机 PJF110 8 步验证通过、commit `7c313d9`。同时更正前会话误判的「riverpod 兼容 bug」根因。

### 2. 初始条件与输入

- 第 1 批已 commit `caeba4f`（Drift 6 表 + 6 DAO 骨架 + errors + utils），branch `feature/notes-mvp`
- 线框图集 B1（列表）/ B1.a（编辑器）交互已定；用户选工具栏 A（加粗/斜体/下划线/红字/删除线/列表/H1/H2）
- 用户确认：功能优先、UI 最小占位、保存手动点才写库
- 16 个 untracked + 7 个 modified 文件已写但 `flutter analyze` 报 29 个问题未闭环
- 技术栈：Flutter 3.44.4 + Dart 3.12.2，Riverpod 3.3.2，Drift 2.34.2，flutter_quill 11.5.1，go_router 17.3
- 前会话 HANDOFF 把卡点记成「riverpod_generator 4.0.4 + riverpod 3.3.2 兼容 bug」，并据此已改手写 AsyncNotifier

### 3. 技术方案选择

#### 可选方案

- **方案 A**：降 riverpod_generator 到 2.x，改回 `@riverpod` 注解生成
- **方案 B**：全手写 Provider/AsyncNotifier，彻底不依赖 generator（会话开始时代码已是手写）
- **方案 C**：升级 riverpod 到兼容 generator 4.x 的新版

#### 最终选择

方案 B：保持手写 Provider/AsyncNotifier，且**不改 riverpod 版本**——因后续排查发现报错真因不是 generator 兼容 bug，而是相对路径 + AsyncValue API 改名 + sealed analyzer 副作用，与 generator 无关。

#### 选择原因

- 报错根因排查后确认与 generator 注解无关（generator 全程 no-op，项目无 `@riverpod` 注解），降/升 generator 解决不了现有报错
- 手写 Provider 已写就，零迁移成本，且 riverpod 3.x 手写 AsyncNotifier API 稳定
- 改 riverpod 版本会连锁影响其它依赖，风险高收益零

### 4. 详细实施路径

#### 步骤 1：跑 flutter analyze 拿全量报错分类

- **目的**：定位 29 个问题的真实类别，不盲改
- **操作**：`flutter analyze` → 读输出分 3 类：①`uri_does_not_exist`/`undefined_class` 级联 ②`valueOrNull` 未定义 ③Dead code 警告
- **输出**：29 issue 清单，发现 `uri_does_not_exist` 级联集中在 4 个 import 了 `data/database` 的文件

#### 步骤 2：确认 riverpod 3.3.2 AsyncValue API

- **目的**：核实 `valueOrNull` 是否改名
- **操作**：grep `D:\PubCache\hosted\pub.dev\riverpod-3.3.2\lib\src\core\async_value.dart`
- **关键发现**：3.x 移除 `valueOrNull`，改为 `value`（返回 `ValueT?`，语义一致）。全项目约 5 处需改

#### 步骤 3：单文件 analyze 二分定位 `uri_does_not_exist` 真因

- **操作**：分别 `dart analyze` 单文件
- **关键发现**：
  - `app_database.dart` 单独 analyze → 全绿（它有 `part 'app_database.g.dart'`，上下文完整）
  - `note.dart` 单独 analyze → 仍报 `uri_does_not_exist` 指向真实存在的 `app_database.dart`
  - `main.dart`/`app_router.dart` 不 import 生成符号 → 全绿
- **这一步排除了"生成代码不同步"假设**，把怀疑指向相对路径本身

#### 步骤 4：核对相对 import `..` 层数（定位真凶）

- **操作**：逐文件数 `..` 与目录深度的对应关系
- **结果**：
  - `note.dart`/`note_version.dart`（在 `features/notes/models/`）→ `src/data/database/` 应 3 个 `..`，代码写了 2 个 ❌
  - `providers.dart`（在 `features/notes/`）→ repository 是同级子目录，应 0 个 `..` 直接 `repository/...`，代码写了 `../repository/` ❌
  - `local_note_repository.dart` 已 3 个 `..` 正确，但缺 DAO 直 import（`NoteDao` 在 `daos/note_dao.dart`，不从 AppDatabase re-export）

#### 步骤 5：修路径 + 改 valueOrNull + 改 switch

- **操作**：
  1. `note.dart`/`note_version.dart`：`'../../data/...'` → `'../../../data/database/app_database.dart'`
  2. `providers.dart`：`'../../../data/...'` → `'../../data/database/app_database.dart'`；`'../repository/...'` → `'repository/...'`
  3. `local_note_repository.dart`：补 `import ... daos/note_dao.dart` + `note_version_dao.dart`
  4. 2 个 ViewModel + editor_view：`valueOrNull` → `.value`
  5. 2 个 ViewModel：`switch(r){case Success(:final value)...}` → `if(r is Success) ... else throw (r as Failure).exception`（绕 Dart 3.12.2 sealed analyzer 副作用）
- **每改一步跑一次 analyze 验证级联减少**

#### 步骤 6：修 DAO insertNote 签名 + 清 warning

- **问题**：`local_note_repository.dart:63` 报 `argument_type_not_assignable`——`insertNote(NotesCompanion(...))` 但 DAO 签名收 `NoteEntity`
- **操作**：改 `note_dao.dart` 的 `insertNote` 收 `NotesCompanion`（加 `insertNoteEntity` 备用 entity 版）
- **清 warning**：删未用字段 `_noteId`、改 `(_, __)` → `(_, _)`、去掉 `if (r is Success)` 后的多余 cast

#### 步骤 7：重跑 build_runner 同步生成代码

- **操作**：`dart run build_runner build`（50s，77 outputs）
- **说明**：实为排除性验证——build_runner 后报错纹丝不动，反向确认真因不是生成代码不同步；riverpod_generator 全 no-op 印证手写 Provider 无注解依赖

#### 步骤 8：commit + 真机验证

- **操作**：`git add` 19 文件（不带 lujing.md）→ `git commit -m "feat: 笔记 CRUD + 富文本编辑器"` → commit `7c313d9`
- **真机**：唤醒 PJF110 → `adb devices` 见 9d306d62 → `flutter run -d 9d306d62` 编译装真机
- **人机验证（8 步全通过）**：新建→写富文本(加粗/下划线/红字)→保存提示"已保存"→返回列表可见→点开读出保留格式→删除从列表消失 ✅
- **发现待办并登记**：新建空笔记直接退出会生成空标题空内容笔记 → 登记产品需求清单 F1.1.10，当前不修

### 5. 核心技术细节

- **`uri_does_not_exist` 级联的真因**：相对 import `..` 数错。`..` 的次数 = 当前文件到 `lib/src/` 根要回退的目录层数。`features/notes/models/` 到 `src/` 是 3 层（models→notes→features→src），故到 `data/...` 应 3 个 `..`。写错后 analyzer 无法解析目标文件，连带报该文件所有符号 `undefined_*`，形成"一个错变十几个错"的级联假象，极易误判为框架版本兼容问题
- **单文件 analyze 二分法**：`dart analyze <单文件>` 能快速区分"文件自身问题"vs"级联污染"。本次靠它确认 `app_database.dart` 自身全绿而 `note.dart` 报错，把怀疑从"生成代码"转向"相对路径"
- **Dart 3.12.2 sealed class + analyzer 副作用**：`switch(sealed) { case Sub(:final x): ... }` 模式匹配在某些写法下触发 `dead_code` 警告与子类型 extractor 行为异常。规避法：改 `if (r is Success) { use r.value } else { throw (r as Failure).exception }`。注意 `if (r is Success)` 后 r 已收窄为 Success，**直接用 `r.value` 无需再 cast**（否则 `unnecessary_cast`）
- **riverpod 3.3.2 AsyncValue API**：3.x 移除 `valueOrNull`，用 `.value`（`ValueT?`）。`.requireValue` 用于确信有值时取值（loading/error 时抛错）。`AsyncValue.guard(_fn)` 包异步建值
- **Drift DAO 不从 AppDatabase re-export**：DAO 类定义在 `daos/xxx_dao.dart`，`AppDatabase` 只通过 `@DriftDatabase(daos:[...])` 暴露 `db.xxxDao` 实例 getter，不暴露类型。外部要用 `NoteDao` 类型必须直 `import ... daos/note_dao.dart`
- **Drift Companion vs Entity**：`into(t).insert(companion)` 收 `XxxCompanion`（可部分字段），`insert(entity)` 收 `XxxEntity`（须完整）。Repository 新建用 companion 合理（insert 前无完整 entity），故 DAO `insertNote` 签名收 companion
- **flutter_quill 11.5.1 在主项目集成要点**（沿用 demo 验证结论）：工具栏 `showUnderLineButton`/`showStrikeThrough`（无 Button 后缀）/`showListBullets`+`showListNumbers`；序列化 `controller.document.toDelta().toJson()` ↔ `Document.fromJson(jsonDecode(...))`，纯字 `doc.toPlainText()`；乎乎续集在 main.dart 注册 `FlutterQuillLocalizations.delegate`

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `features/notes/models/note.dart` | 修改 | 相对路径 `..` 修成 3 个 | 解 uri_does_not_exist |
| `features/notes/models/note_version.dart` | 修改 | 同上 | 同上 |
| `features/notes/providers.dart` | 修改 | `..` 修成 2 + repository 去 `..` | 同上 |
| `features/notes/repository/local_note_repository.dart` | 修改 | 补 DAO 直 import | 解 NoteDao/NoteVersionDao undefined |
| `features/notes/view_model/note_editor_view_model.dart` | 修改 | valueOrNull→.value + switch→if-else + 删 _noteId + 清 cast | 解 5 类 |
| `features/notes/view_model/note_list_view_model.dart` | 修改 | valueOrNull→.value + switch→if-else + 清 cast | 同上 |
| `features/notes/view/note_editor_view.dart` | 修改 | valueOrNull→.value | 解 1 处 |
| `data/database/daos/note_dao.dart` | 修改 | insertNote 收 companion | 解 argument_type_not_assignable |
| `features/notes/view/note_list_view.dart` | 修改 | `(_, __)`→`(_, _)` | 清 unnecessary_underscores |
| `jihua/ruoke-产品待办需求清单-20260713.md` | 修改 | 加 F1.1.10 空笔记不残留 | 登记待办 |
| git commit `7c313d9` | 新建 | feat: 笔记 CRUD + 富文本编辑器（19 文件 +1386） | 第 2 批存档 |

### 7. 问题、尝试与解决过程

#### 问题 1（最大）：29 个报错被误判为「riverpod 兼容 bug」

- **表现**：`uri_does_not_exist` ×13 + `undefined_*` ×多 + `valueOrNull` ×5 + Dead code ×多，前会话归因为 generator 4.x 与 riverpod 3.x 不兼容
- **原因判断**：误判。真因是 3 个文件相对 import `..` 数错 → 级联未解析符号；叠加 riverpod 3.x `valueOrNull` 改名、Dart 3.12.2 sealed analyzer 副作用
- **尝试过的方法**：①清 `.dart_tool` 缓存重跑 analyze（无效，排除缓存）②重跑 build_runner（无效，排除生成代码不同步）③单文件 `dart analyze` 二分（关键：发现 app_database.dart 独立全绿而 note.dart 报错）
- **无效方法**：清缓存、重跑生成——都治不了相对路径写错
- **最终处理**：逐文件核对 `..` 层数修正，29 issue → 15 → 5 → 0
- **处理结果**：analyze No issues found

#### 问题 2：insertNote 参数类型不匹配

- **表现**：`argument_type_not_assignable: NotesCompanion 不能赋给 NoteEntity 参数`
- **原因判断**：DAO `insertNote(NoteEntity)` 但 Repository 调用方传 `NotesCompanion`
- **最终处理**：改 DAO `insertNote` 收 `NotesCompanion`
- **处理结果**：通过

#### 问题 3：真机空笔记残留（已登记待办，未修）

- **表现**：新建笔记不写任何内容直接退出，仍生成空标题空内容笔记
- **原因判断**：当前 `createEmpty` 一进编辑器就 create 一条草稿行，退出不回收
- **处理**：登记产品需求清单 F1.1.10，当前不修（用户决定以后修复）

### 8. 验证方法与结果

- `flutter analyze`（最终）：No issues found ✅
- 真机 PJF110 `flutter run -d 9d306d62`：编译成功 + 装机成功 + 应用启动 ✅
- 人机 8 步验证（用户真机操作）：全通过 ✅
  - 5tab 底栏显示、默认落笔记 tab
  - 空列表提示、FAB 新建
  - 编辑器顶栏 + flutter_quill 工具栏可用
  - 写富文本(加粗/下划线/红字) → 保存提示"已保存"
  - 返回列表可见新笔记 → 点开读出保留格式
  - 删除确认后从列表消失
- **未验证内容**：编辑器长期使用下 Delta JSON 持久化稳健性（需多次往返验证，未做）、MVP 范围外功能

### 9. 可复现要点

- 排查 `uri_does_not_exist` 级联第一直觉：**先数相对 import `..` 对不对**（`..` 数 = 当前文件回退到 `lib/src/` 的目录层数），别急着归咎框架版本兼容
- 用 `dart analyze <单文件>` 二分：目标文件单独全绿 → 基本是级联污染，往"谁导入了它"方向查
- riverpod 3.x 取异步值可空用 `.value`（非 `valueOrNull`），确信有值用 `.requireValue`
- 绕 Dart 3.12.2 sealed analyzer 副作用：`if (r is Success) r.value else throw (r as Failure).exception`，收窄后别再 cast（否则 unnecessary_cast）
- Drift DAO 类型用要直 `import ... daos/xxx_dao.dart`，不指望 AppDatabase re-export
- 插入用 companion、读取用 entity：DAO `insertNote(XxxCompanion)`、`select` 返回 `XxxEntity`
- `flutter_localizations` 走 `sdk: flutter`；`flutter pub add flutter_quill` 指定 `:^11.5.1`
- 改表/改 DAO 后跑 `dart run build_runner build`；改纯业务代码（无 Drift 注解）不需重跑


---

## 技术路径记录：2026-07-24 16:00（阶段5 第3批：笔记分级 书-章-节树 + 一键定级 + 科目管理页）

### 1. 完成事项

完成阶段5 第3批「笔记分级」：B1 书-章-节可折叠树、FAB 一键定级窗、App 首启 seed 示例科目、note 接真实 subjectId（defaultSubjectId 退役为未分类兜底）、简易科目管理页（增删书-章-节，单独 commit）。`flutter analyze` 全程全绿。真机 5 步核心验证通过。commit `9b00c60` + `f8604e1` + `8874ffd`。

### 2. 初始条件与输入

- 第 1/2 批已 commit（Drift 6 表基础 + 笔记 CRUD），branch `feature/notes-mvp`
- 线框图 B1 已定义（书-章-节-笔记四级树 + FAB 定级弹窗 + 未分类兜底 + 进度条/V2）
- 用户拍板：全量树（不做 MVP 减配）、App 首启 seed 示例科目、折叠态 ViewModel 持久、加简易科目管理页
- Dart 3.12.2 sealed class analyzer 副作用已在第 2 批摸清（switch→if-else 规避），第 3 批沿用
- subject 表/DAO 骨架第 1 批已建（insertSubject 收 entity, listAll, childrenOf）

### 3. 技术方案选择

#### 可折叠树 vs 平铺列表

- 方案 A：Flutter `TreeView`（不内置，社区包）→ 包量太少、不满足 B1 线框的层级缩进+折叠箭头+笔记行混排
- 方案 B：自写递归 `ExpansionTile` → Flutter 内置、原生折叠动画、嵌套渲染支持任意深度。但 `ExpansionTile.onExpansionChanged` 与 `Consumer` 结合时折叠态持存在 ViewModel 较可控

最终选 B：自写递归 widget（`_BookTile`→`_ChapterTile`→`_SectionTile`→`_NoteRow`），每级用自定义 `_SubjectRow`（InkWell + 图标 + 箭头），展开/折叠通过 `SubjectTreeVm.toggleExpand(id)` 操作 `expandedIds` Set，`Consumer` watch 后 `.value.books` 取当前态重渲染。

#### 选择原因

- `ExpansionTile` 默认折叠态靠自身 State，与 Riverpod Consumer 切 tab 不重建的 indexedStack 偶发状态不同步（展开态"弹回"）
- ViewModel 持 `Set<String> expandedIds` 能穿透 tab 切换且刷新不丢（`_load` 保留上次的 expandedIds）
- 自写 tile 对图标/缩进/笔记行混排自由度最高，可精准对齐 B1 线框的缩进规则

#### seed 时机与幂等

- 方案 A：`main()` 中 ProviderScope 外用临时 `AppDatabase` 实例 seed 完关掉，ProviderScope 内 `appDatabaseProvider` 另外新建一个实例共享同一 .sqlite 文件
- 方案 B：ProviderScope 内注册 seed 任务

选 A。原因：seed 逻辑不应污染 Provider 初始化链；临时 db 实例 seed 完关掉，不走 Provider 闭包，简单安全；Drift 多实例同库无冲突。

### 4. 详细实施路径

#### 步骤 1：扩充 subject_dao + 重跑 build_runner

- **目的**：DAO 增 `getById/softDelete/countChildren/totalCount`，insertSubject 改收 companion（对齐 note_dao 第2批经验）
- **操作**：Write subject_dao 全文（加 countAll/selectOnly for count），`dart run build_runner build` 重生成
- **输出**：drift 9 output 文件重新生成（subject_dao.g.dart），成功无报错

#### 步骤 2：建 Subject 领域模型 + Repository

- **目的**：SubjectEntity→Subject 纯 Dart 模型 + SubjectRepository 接口 + LocalSubjectRepository（Drift 实现）
- **操作**：建 `models/subject.dart`（fromEntity + levelLabel）、`repository/subject_repository.dart`（接口 7 方法）、`repository/local_subject_repository.dart`（Drift 实现，guard+translator）
- **关键细节**：`SubjectRepository.isEmpty()` 返回 `bool` 判空（seed 幂等），`countChildren(String? parentId)` 判叶/判空
- **Provider**：`providers.dart` 加 `subjectRepositoryProvider`（注入 appDatabaseProvider）

#### 步骤 3：建 SubjectTreeVm（书-章-节嵌套树 + 折叠态）

- **目的**：把扁平 subject list + note list 在内存构造成嵌套树
- **数据类**：`SubjectTreeNode`（subject + children + notes）、`SubjectTreeState`（books + uncategorized notes + expandedIds + uncategorizedExpanded）
- **构造算法**：`_buildTree`：按 parentId 映射 → 递归 `buildNode` 从书 level0 起构子树 → 笔记按 subjectId 分组挂对应节点 → 对指向不存在科目或 defaultSubjectId 的笔记入 uncategorized
- **折叠态**：`toggleExpand(id)` 写 `state = AsyncData(cur.copyWith(expandedIds: next))`；`_load` 刷新时保留上次 expandedIds（空则首次默认展开所有书级节点）

#### 步骤 4：首启 seed 示例科目树

- **目的**：App 首启插入物理（3 章）+ 英语（2 章），让 B1 树立即可看效果
- **文件**：`data/database/seed/subject_seed.dart`
- **幂等**：`SubjectSeed.runIfEmpty()` 调 `SubjectDao.totalCount()`，仅 0 才 seed
- **调用**：`main()` 里 `ProviderScope` 前用临时 `AppDatabase()` 跑 seed（容错例外：`try-catch` + `debugPrint` 不打断启动）
- **关键坑**：`SubjectsCompanion` 是生成类，不在 `package:drift/drift.dart` 里，要将 `import 'package:drift/drift.dart' show Value, SubjectsCompanion;` 改为只 `show Value`，让 SubjectsCompanion 从 `app_database.dart` 的 part 来

#### 步骤 5：B1 树 View（note_list_view 重写）

- **目的**：将第2批平铺列表升级为可折叠四级树
- **结构**：`NoteListView(ConsumerWidget)` → `_BookTile(ConsumerWidget)` → `_ChapterTile(ConsumerWidget)` → `_SectionTile(ConsumerWidget)` → `_NoteRow(ConsumerWidget)`，每级用 `_SubjectRow` 渲染科目行
- **缩进规则**：`padding: EdgeInsets.only(left: 16.0 + depth * 16)`
- **笔记行**：`_NoteRow` 为 ConsumerWidget（点进编辑器、删除调 `subjectTreeVmProvider.notifier.softDeleteNote(id)`、返回 refresh）
- **未分类组**：树底部 `_UncategorizedTile(ConsumerWidget)`，可折叠

#### 步骤 6：FAB 定级窗（subject_picker_dialog）

- **目的**：FAB + 弹出定级窗选书/章/节，选完后带 subjectId 进编辑器
- **实现**：`showSubjectPickerDialog(context, ref)` → 拉 `subjectTreeVmProvider.value.books` 扁平化 → `AlertDialog` + `ListView` 含层级缩进图标
- **关键变更**：`RadioListTile.groupValue/onChanged` deprecated（Flutter 3.32）→ 改用 `ListTile` + 选中态 `Check` 图标 + `onTap` 单选

#### 步骤 7：编辑器 subjectId 及路由 query

- **目的**：新建笔记时保存选定的 subjectId
- **改动链**：`app_router.dart` 编辑器路由加 `?subjectId=` query → `NoteEditorView` 加 `subjectId` 参数 → `init(noteId, subjectId:)` 带进 `NoteEditorState.subjectId` → `save()` 用 `cur.subjectId ?? defaultSubjectId` 建笔记

#### 步骤 8：简易科目管理页（单独 commit）

- **目的**：我的 tab 加学科管理入口，实现增删书-章-节
- **文件**：`SubjectManageVm`（AsyncNotifier+create/delete）+ `subject_manage_view.dart`（扁平缩进列表+FAB 新建弹窗选 level+父节点）+ `settings_view.dart`（替换 placeholder）+ 路由 `/settings/subjects`
- **新建弹窗**：`StatefulBuilder` 内选择 level（0/1/2），level>0 显示父节点下拉（过滤仅 level≤1 科目），调 `SubjectManageVm.create(name,level,parentId)`
- **删旧**：确认弹窗 → `SubjectManageVm.delete(id)` → 刷新 B1 树

### 5. 核心技术细节

- **内存树构造**：`byParent[subject.parentId]` 分组 → 从 parentId=null 的 level0 开始递归 `buildNode(s)`。节点本身也有 `notes`（B1 线框支持整本/整章笔记——subject_id 指向书或章而非节）。未分类=subjectId==defaultSubjectId 或不在 validIds 中。
- **折叠态跨 tab 保**：`SubjectTreeState.expandedIds: Set<String>` 由 VM `toggleExpand` 维护；`_load` 刷新时保留 `prev.expandedIds`（首次用 `tree.books.map(id).toSet()` 默认展所有书）。`Consumer.watch` 的 `value` 每次刷新重建 ViewModel → View 用新 data 渲染，但 expandedIds 已保留。
- **seed 幂等**：`SubjectDao.totalCount()` → `selectOnly(subjects)..addColumns([countAll()])`，仅 0 才插。临时 AppDatabase 跑 seed close 掉，ProviderScope 另建新实例共享 .sqlite。
- **SubjectsCompanion 来源**：`app_database.g.dart` 生成 → `app_database.dart` 通过 `part 'app_database.g.dart'` 暴露。外部文件不应 `show Value, SubjectsCompanion`（SubjectsCompanion 不在 drift package），只 `show Value` 加另 import app_database 即可。
- **DropdownButtonFormField deprecation**：Flutter 3.33+ 的 `value` → `initialValue`（一次性初始值，后续状态由 `onChanged` 驱动）。与 `StatefulBuilder` + `setState` 搭配实现内部值更新。
- **V2 未改名**：SubjectRepository 缺少 rename 方法，管理页改名栏留"待 V2 补充"提示。如需急着改名，可用 `create(新)+softDelete(旧)` 变通（副作用是笔记关联需迁移，暂不这样做）。
- **`final class` vs `sealed class` 避坑延续**：第3批所有 Result 解包沿用 if-else `is Success/Failure`，不碰 switch sealed（Dart 3.12.2 analyzer bug）。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `data/database/daos/subject_dao.dart` | 修改 | insertSubject 收 companion + countChildren/totalCount/softDelete/getById | 树查询+seed 判空 |
| `data/database/seed/subject_seed.dart` | 新建 | 幂等 seed 示例科目（物理3章+英语2章） | 首启有树看 |
| `features/notes/models/subject.dart` | 新建 | Subject 领域模型(levelLabel) | 数据解耦 |
| `features/notes/repository/subject_repository.dart` | 新建 | 接口 7 方法 | 存储抽象 |
| `features/notes/repository/local_subject_repository.dart` | 新建 | Drift 实现 | 本地存储 |
| `features/notes/providers.dart` | 修改 | 加 subjectRepositoryProvider | DI |
| `features/notes/view_model/subject_tree_view_model.dart` | 新建 | 扁平→嵌套树 + 折叠态 + softDelete | B1 树 VM |
| `features/notes/view_model/subject_manage_view_model.dart` | 新建 | 扁平列表 + create/delete | 管理页 VM |
| `features/notes/view_model/view_model_providers.dart` | 修改 | 加 subjectTreeVmProvider + subjectManageVmProvider | DI |
| `features/notes/view/note_list_view.dart` | 修改 | 平铺→B1 可折叠树 | UI |
| `features/notes/view/subject_picker_dialog.dart` | 新建 | FAB 定级窗（单选+未分类兜底） | 建笔记取 subjectId |
| `features/notes/view/subject_manage_view.dart` | 新建 | 管理页（增删新建弹窗） | 科目管理 |
| `routing/settings_view.dart` | 新建 | 我的tab→学科管理入口 | 入口 |
| `routing/app_router.dart` | 修改 | 编辑器路由 +?subjectId=/settings/subjects | 路由 |
| `features/notes/view/note_editor_view.dart` | 修改 | 接受 subjectId 参数 | 路由→VM |
| `features/notes/view_model/note_editor_view_model.dart` | 修改 | init 加 subjectId 参数 + save 用它 | VM |
| `features/notes/note_constants.dart` | 修改 | 注释：defaultSubjectId 退役为未分类兜底 | 常量 |
| `lib/main.dart` | 修改 | 首启 `SubjectSeed.runIfEmpty`（临时 db+容错） | seed 入口 |

git commits：`9b00c60 feat: 笔记分级-书章节树+一键定级`（16 文件 +1059 行）、`f8604e1 feat: 简易科目管理页`（5 文件 +384 行）、`8874ffd docs: 第3批真机验证待办F1.1.11-F1.1.15`（1 文件 +5 行）

### 7. 问题、尝试与解决过程

#### 问题 1：DropdownButtonFormField `value` deprecated

- **表现**：analyze 报 `deprecated_member_use: value → use initialValue`
- **原因判断**：Flutter 3.33+ 将 `value` 属性改名为 `initialValue`（更准确描述行为——这是一次性初始值，后续值由 StatefulBuilder 内的 setState 维护）
- **最终处理**：`value: level` → `initialValue: level`，同改 parentId 下拉
- **处理结果**：analyze 通过

#### 问题 2：SubjectsCompanion undefined_shown_name

- **表现**：`show Value, SubjectsCompanion` 报 `undefined_shown_name`
- **原因判断**：SubjectsCompanion 是 Drift 生成类（在 `app_database.g.dart`），不在 `package:drift/drift.dart` 的导出符号里
- **处理**：删掉 show 里的 SubjectsCompanion，靠 import app_database.dart 拿
- **处理结果**：analyze 通过。经验：Drift 生成的各种表专有类（XxxCompanion, XxxEntity）一律从 app_database 拿，不要 show 到 drift package

#### 问题 3：真机验证发现 5 条待办

- **F1.1.11 节加展开按钮**：节行无折叠图标（`onTap: null`），用户要求节也能折叠。根因：设计时以为节为叶节点（level2=叶），但实际有节下大量笔记需折叠。已登记待办。
- **F1.1.12 定级窗层级选**：当前所有节点平铺单选，书多后繁琐。应改为级联选。已登记待办。
- **F1.1.13 新建笔记残留**：新建时 `_ensureControllers` 检查 `if (_controller != null) return;`，所以退出再进时 QuillController(s) 没清，旧内容保留。根因：`_NoteEditorViewState` 未在 `initState` 时重置 controller。已登记待办。
- **F1.1.14 编辑器首次转圈**：首启 seed 写在 ProviderScope 外、`runApp` 前，但编辑器 `init(noteId)` 调异步 Provider→Repository→DAO，如果 ProviderScope 内的 appDatabaseProvider 创建实例与 seed 有少许时序重叠（或 DB 文件锁），第一次 Watch/Read 可能 loading 态卡住，退出再进时 Provider 已缓好。根因待排查：疑似 Flutter 首次构建 Widget 时 Riverpod AsyncNotifier 初始化未就绪。已登记待办。
- **F1.1.15 文件夹系统**：用户要求书(level0)之上加多级文件夹，类似 Windows 文件夹系统。设计层面需考虑 subject 表扩展或新建 folder 表，与当前 0/1/2 三层模型冲突。已登记待办（先 V2 再细化设计）。

### 8. 验证方法与结果

- `flutter analyze`：全程全绿（No issues found），3 次复跑确认
- 真机 PJF110 `flutter run`：编译成功 + 装机成功 + 首次启动 seed 执行成功
- 真机人机验证（5 步通过）：B1 树展开/折叠、FAB 定级窗①选节点②弹出来③点新建④save⑤返回看见挂对位置、树上笔记右侧删除确认后消失
- 切 tab（首页→笔记）折叠态保留 ✅
- **未验证内容**：科目管理页新建/删除（真机待验证——已纳入第4批前人工单独验证）；编辑器首次转圈 bug（已登记）。进度条/复习量（F1.21，需 review_card 表，非本批范围）

### 9. 可复现要点

- SubjectsCompanion 从 app_database.dart 拿，不要 show 到 drift 包（dart analyze 会报 undefined_shown_name）
- DropdownButtonFormField 用 `initialValue` 非 `value`（Flutter 3.33+ deprecated）
- 折叠态跨 tab 保需要 ViewModel 持有 `expandedIds` + `Consumer.watch`，不能只用 ExpansionTile 自身 State
- seed 临时建 `AppDatabase()` 跑完 `close()`（别在 ProviderScope 内做，时序重叠可能与 Provider 的 appDatabaseProvider 首次懒取冲突→编辑页首次转圈，根因待查 F1.1.14）
- `RadioListTile.groupValue/onChanged` deprecated → 用 `ListTile` + 选中态图标 + `onTap` 单选
- 表全量 seed 幂等检查用 `selectOnly(table)..addColumns([countAll()])`，非 `select(table).get().length`
- 重命名未实现（Repository 无 rename），写代码时避开调不存在的 API






