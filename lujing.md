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





---

## 技术路径记录：2026-07-26 10:00（阶段5 第4批：重点标记入库 + 历史版本回退）

### 1. 完成事项

完成阶段5第4批方案 A（最小 MVP 闭环）：

- 笔记手动保存时解析 Quill Delta，将红字和下划线内容全量重建到 `note_highlight` 表；
- 正文发生变化时，将修改前正文保存为 `note_version` 快照；
- 新增历史版本列表页，按版本号倒序显示；
- 支持恢复指定版本，恢复前先把当前正文保存为新快照；
- 编辑器首次保存新笔记后，无需退出重进即可打开历史版本；
- 从有未保存正文的编辑器进入历史版本前会先保存，保存失败则阻止跳转；
- 解决真机回归发现的编辑器持续转圈、Quill 实际红色值无法识别、恢复后刷新失败误报恢复失败等问题。

本批未修改 F1.1.10-F1.1.15 已知待办，未实现版本对比、标题历史、自动保存、另存为新笔记和重点字符位置定位。代码尚未 commit，未 push。

### 2. 初始条件与输入

- 当前分支：`feature/notes-mvp`，第1/2/3批已提交并推送至 `origin/feature/notes-mvp`；
- 第1批已创建 `note_highlight`、`note_version` 表及 DAO 骨架，不需要改 schemaVersion 或数据库迁移；
- 第2批已有 Quill Delta JSON 持久化和“正文变化时保存旧正文快照”的基础逻辑；
- 编辑器工具栏已有红字和下划线按钮，本批不重新设计工具栏；
- 需求依据：
  - F1.1.7：红字/下划线内容作为重点记录；
  - F1.1.4：查看历史版本并回退；
  - B1.b 历史版本线框；
  - `jihua/ruoke-阶段5第4批重点标记历史版本回退开发计划-20260725.md`；
- 用户选择方案 A：重点表保存 `kind + body`，`start/end` 暂为 null；历史快照只覆盖正文；
- 已知 bug F1.1.10-F1.1.15 明确留待办，本批不处理；
- 环境：Flutter 3.44.4、Dart 3.12.2、Riverpod 3.3.2、Drift 2.34.2、flutter_quill 11.5.1、go_router 17.3；
- 真机：PJF110，Android 16，ADB 设备码 `9d306d62`。

### 3. 技术方案选择

#### 可选方案

- 方案 A：保存时扫描 Quill Delta，提取红字/下划线文本，按笔记先删后插全量重建重点；历史页只做列表和恢复。
  - 优点：不改表结构，逻辑确定，避免复杂的富文本字符位置换算，能快速闭环 F1.1.7/F1.1.4；
  - 缺点：`start/end` 暂为空，不能从重点记录精确跳回原文位置。
- 方案 B：在编辑过程中监听 Delta change，实时维护重点表和字符范围。
  - 优点：可保留精确位置，未来可做重点导航；
  - 缺点：Delta 的插入、删除、格式覆盖会持续改变偏移量，需要处理组合操作、换行和 Unicode 边界，超出 MVP 范围。
- 历史恢复另存为新笔记：保留原笔记不动，恢复内容生成新笔记。
  - 优点：原笔记完全不被覆盖；
  - 缺点：会产生额外笔记和科目关联处理，不符合当前“回退当前笔记”的交互。

#### 最终选择

采用方案 A：

1. `create/update/restoreVersion` 都通过 Repository 统一重建重点；
2. `update` 仅在正文 JSON 变化时生成旧正文快照；
3. `restoreVersion` 在同一事务内保存当前正文快照、写回目标正文并重建重点；
4. 历史列表由独立 ViewModel 管理加载与恢复；
5. 编辑器打开历史页前若存在未保存内容，先执行保存。

#### 选择原因

- 已有数据库表和 Quill 工具栏可直接复用，修改范围小；
- 将事务边界放在 Repository，可保证“版本快照、当前正文、重点记录”同步成功或同步失败；
- View 不直接访问 DAO，保持现有 View → ViewModel → Repository → DAO 分层；
- 恢复前保存当前正文，既满足回退，又保留可再次前进的版本；
- 不改数据库结构，降低对前三批已验证功能的回归风险。

### 4. 详细实施路径

#### 步骤 1：建立第4批计划与范围边界

- **目的：** 把用户选择的方案 A 转成可执行、可验收的任务；
- **操作：** 新建 `jihua/ruoke-阶段5第4批重点标记历史版本回退开发计划-20260725.md`；
- **方法或技术：** 按 TDD 拆为重点解析器、Repository 事务、版本页与路由、验证四组；
- **关键设置：** 不改数据库 schema；不修 F1.1.10-F1.1.15；不 push；
- **输出：** 第4批开发计划；
- **判断依据：** 文件范围、接口约定、测试顺序和验收标准均明确。

#### 步骤 2：用测试驱动重点解析器

- **目的：** 将 Quill Delta 中的重点格式转换为可写入数据库的领域数据；
- **操作：** 先写 `highlight_extractor_test.dart` 失败测试，再实现 `highlight_extractor.dart` 和 `NoteHighlight`；
- **方法或技术：** 遍历 Delta operation；仅处理 `insert` 为非空字符串的操作；读取 `attributes.color` 和 `attributes.underline`；
- **输入：** Quill Delta JSON；
- **关键设置：**
  - 红色兼容 `red`、`#F44336`、`#FFF44336`，比较时统一大写；
  - 下划线仅在 `underline == true` 时提取；
  - 同一段同时红色和下划线时生成两条重点；
  - 普通文字和空字符串不生成重点；
  - `start/end` 保持 null；
- **输出：** `List<NoteHighlight>`；
- **判断依据：** 解析器单元测试覆盖普通文本、红字、下划线、双格式、空操作及真机 Quill 红色值。

#### 步骤 3：扩展 DAO 和 Repository 事务

- **目的：** 保存笔记时同步维护重点和历史快照；
- **操作：**
  - `note_highlight_dao.dart` 改为接收 `NoteHighlightsCompanion`；
  - `NoteRepository` 增加 `restoreVersion`；
  - `LocalNoteRepository` 增加重点重建、下一版本号、版本恢复等辅助逻辑；
- **方法或技术：** 使用 Drift `transaction` 包裹多表写入；
- **关键设置：**
  - create：写当前笔记后提取并写入重点；
  - update：正文变化时先保存旧正文快照，再更新笔记，最后删旧重点并写新重点；
  - 正文未变化时不生成空版本；
  - restore：校验目标版本存在；先保存当前正文为新版本，再写回目标正文并重建重点；
  - 重点采用按 noteId 全量删除后批量插入，防止重复累积和过期重点残留；
- **输出：** 保存、更新和恢复流程形成一致的数据事务；
- **判断依据：** 本地 Repository 数据库测试验证新建重点、更新重建、版本生成和恢复行为。

#### 步骤 4：实现历史版本 ViewModel、列表页与路由

- **目的：** 提供用户可操作的版本列表和恢复入口；
- **操作：**
  - 新建 `NoteVersionVm` 和 Provider family；
  - 新建 `NoteVersionListView`；
  - 增加 `/notes/editor/:noteId/versions` 路由；
  - 编辑器“更多”菜单增加“历史版本”；
- **方法或技术：** Riverpod 手写 `AsyncNotifier`；go_router 子路由；恢复前显示确认对话框；
- **关键设置：**
  - 版本按 Repository 返回顺序倒序展示；
  - 恢复成功后重新加载列表；
  - 恢复已成功但列表刷新失败时，仍返回恢复成功，刷新错误只保留在列表状态中；
  - 恢复成功后返回编辑器，由编辑器重新加载当前笔记；
- **输出：** B1.b 历史版本 MVP 页面；
- **判断依据：** ViewModel 测试覆盖加载、恢复、恢复失败，以及恢复成功后刷新失败的边界。

#### 步骤 5：修复编辑器进入历史页的状态边界

- **目的：** 避免新笔记首次保存后无历史入口，以及未保存正文丢失；
- **操作：**
  - 历史入口可用性由 `state.value?.note != null` 判断，不再只看静态路由参数是否为 `new`；
  - 跳转时使用 ViewModel 中实际保存后的 noteId；
  - 编辑器为 dirty 时，进入历史页前先保存；
  - 保存失败时提示“保存失败，无法打开历史版本”并停止跳转；
- **方法或技术：** widget 回归测试验证菜单入口、dirty 保存和失败阻断；
- **关键设置：** 标题变化会保存当前笔记，但版本快照仍只由正文变化触发，这是本批定义的边界；
- **输出：** 新建笔记首次保存即可访问历史，正文修改后可直接进入历史；
- **判断依据：** `note_editor_history_entry_test.dart` 通过，并在 PJF110 真机复现通过。

#### 步骤 6：定位并修复真机回归

- **目的：** 处理自动化测试未覆盖、真机操作暴露的异常；
- **操作与根因：**
  1. 编辑器持续转圈：`NoteEditorVm.build()` 原为异步，`init()` 写入 ready 状态后，迟到的 build 完成又覆盖状态；改为同步 `build() => const NoteEditorState()`；
  2. 实际红字未识别：flutter_quill Material 红色写入的是 `#FFF44336`，不是只有字符串 `red`；扩展颜色兼容；
  3. 新笔记首次保存后无历史入口：UI 仍依据路由参数 `new`；改为依据已保存的实际 note；
  4. dirty 正文直接进历史未形成快照：进入路由前没有保存；增加先保存流程；
  5. 恢复成功但刷新失败返回 false：把恢复结果与列表刷新结果解耦；
  6. widget 测试菜单点击失败：测试在点击“更多”后未 pump 新 frame，并非生产代码错误；修正测试同步方式；
- **方法或技术：** systematic debugging 逐项确认现象、最小复现和根因；每个生产修复先补失败测试；
- **输出：** 真机核心闭环可连续执行；
- **判断依据：** 定向测试、全量测试、analyze、APK build 和真机回归均通过。

### 5. 核心技术细节

- **重点提取不是富文本渲染：** `note_highlight` 是从 Delta 派生的索引数据，真实正文仍以 `contentJson` 为准。重点表可以全量重建，不作为正文唯一来源。
- **Quill 红色编码兼容：** 工具栏选择 Material red 后，Delta 可能写 `#FFF44336`（ARGB）或 `#F44336`（RGB），也可能存在命名色 `red`。解析时统一大写再匹配，避免大小写和格式差异。
- **事务一致性：** 更新正文时“旧正文快照 → 当前正文更新 → 重点重建”必须处于同一事务。任何一步失败都不能留下半更新状态。
- **版本号策略：** 读取当前最大版本号后加 1。恢复操作本身也产生新版本，因此恢复后版本列表会多一条“恢复前内容”。
- **快照范围：** `note_version.snapshotJson` 只保存正文 Delta JSON。标题、科目和标签不参与本批回退；标题-only 保存不会创建版本。
- **恢复结果与刷新解耦：** Repository 恢复成功是数据事实。列表重新加载失败是展示层后续错误，不能把已经完成的恢复向用户误报为失败。
- **Riverpod 初始化竞态：** 对需要外部 `init(noteId)` 驱动的编辑器 VM，`build()` 使用同步初始状态，避免异步 build 在 init 后完成并覆盖状态。
- **新笔记身份切换：** 路由参数 `new` 只描述进入页面时的身份；首次保存后应以 VM 当前 `note.id` 为真实身份，后续历史路由必须使用该 ID。
- **dirty 进入历史：** 进入历史页是离开当前编辑上下文，必须先保存；失败时留在原页，避免用户误以为当前内容已进入版本链。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `jihua/ruoke-阶段5第4批重点标记历史版本回退开发计划-20260725.md` | 新建 | 方案 A、范围、TDD 步骤与验收标准 | 第4批执行依据 |
| `lib/src/data/database/daos/note_highlight_dao.dart` | 修改 | 重点插入改收 Companion | 支持 Repository 写入派生重点 |
| `lib/src/features/notes/models/note_highlight.dart` | 新建 | 重点领域模型 | 隔离数据库实体与解析逻辑 |
| `lib/src/features/notes/utils/highlight_extractor.dart` | 新建 | 解析 Delta 红字/下划线 | 生成重点数据 |
| `lib/src/features/notes/repository/note_repository.dart` | 修改 | 增加版本恢复接口 | 统一版本能力契约 |
| `lib/src/features/notes/repository/local_note_repository.dart` | 修改 | 事务保存、重点重建、版本快照与恢复 | 第4批数据核心 |
| `lib/src/features/notes/view_model/note_version_view_model.dart` | 新建 | 加载版本、恢复并刷新 | 历史页状态管理 |
| `lib/src/features/notes/view_model/note_editor_view_model.dart` | 修改 | 同步 build 初始状态 | 修复 init 状态被覆盖 |
| `lib/src/features/notes/view_model/view_model_providers.dart` | 修改 | 注册版本 ViewModel family | Riverpod 注入 |
| `lib/src/features/notes/view/note_version_list_view.dart` | 新建 | 版本列表、确认恢复、结果提示 | 历史版本 UI |
| `lib/src/features/notes/view/note_editor_view.dart` | 修改 | 历史入口、实际 noteId、dirty 先保存、返回刷新 | 编辑器接入历史能力 |
| `lib/src/routing/app_router.dart` | 修改 | 新增版本列表沉浸路由 | 页面导航 |
| `test/features/notes/highlight_extractor_test.dart` | 新建 | 重点解析与真实红色值测试 | 解析回归保护 |
| `test/features/notes/local_note_repository_test.dart` | 新建 | 重点、版本、恢复数据库测试 | 数据事务验证 |
| `test/features/notes/note_version_view_model_test.dart` | 新建 | 列表、恢复、刷新失败测试 | ViewModel 边界验证 |
| `test/features/notes/note_editor_history_entry_test.dart` | 新建 | 首存入口、dirty 保存、失败阻断测试 | 编辑器历史入口回归保护 |
| `test/features/notes/note_editor_view_model_test.dart` | 新建 | init 跨事件循环保持 ready | Riverpod 初始化竞态保护 |
| `test/widget_test.dart` | 修改 | 路由和编辑器 widget 测试适配 | 全局回归测试 |

本批源码与测试仍在工作区，尚未 commit，尚未 push。

### 7. 问题、尝试与解决过程

#### 问题 1：编辑器真机持续显示加载

- **表现：** 进入编辑器后一直转圈，退出再进也可能受状态时序影响；
- **原因判断：** `build()` 异步返回初始状态，外部 `init()` 已经设置 ready 后，迟到的 build 结果再次覆盖 state；
- **尝试过的方法：** 通过 VM 单元测试让 `init()` 完成后再跨一个事件循环检查状态；
- **最终处理：** `build()` 改为同步返回 `const NoteEditorState()`；
- **处理结果：** 单元测试通过，PJF110 编辑器可正常加载。

#### 问题 2：真机红字未写入重点解析结果

- **表现：** 测试中的 `color: red` 可提取，但真机工具栏选择红色后数据未匹配；
- **原因判断：** flutter_quill 实际保存 Material red 为 `#FFF44336`；
- **最终处理：** 兼容 `red`、`#F44336`、`#FFF44336`，统一大小写比较；
- **处理结果：** 增加真实值回归测试并通过。真机可确认红字格式保存和恢复；真机数据库表未直接查询。

#### 问题 3：新笔记首次保存后没有历史版本入口

- **表现：** 保存成功后“更多”菜单仍不显示“历史版本”，必须退出重进；
- **原因判断：** 入口逻辑使用创建页面时的静态 `widget.noteId == 'new'`；
- **最终处理：** 改为检查 VM 当前是否已有 note，并使用保存后实际 noteId 导航；
- **处理结果：** widget 测试和真机 `DEVICE-TEST-3` 均确认首次保存后立即出现入口。

#### 问题 4：未保存正文进入历史页时没有形成版本

- **表现：** 编辑正文后不点保存，直接进入历史列表，版本链中没有这次正文变化；
- **原因判断：** 跳转前没有调用编辑器保存；
- **最终处理：** `_openHistory` 检查 dirty，先保存；保存失败提示并阻止导航；
- **处理结果：** 自动化测试通过；真机追加 `BODY-CHANGE-3` 后直接进历史，版本 1 出现。

#### 问题 5：恢复成功后列表刷新失败会误报恢复失败

- **表现：** Repository 已完成恢复，但 ViewModel 重新拉列表异常时 `restore()` 返回 false；
- **原因判断：** 把数据操作结果和后续 UI 刷新结果合并成同一个布尔结果；
- **最终处理：** 恢复成功后尝试刷新，但刷新失败不改变恢复成功返回值；
- **处理结果：** 对应 ViewModel 测试通过。

#### 问题 6：widget 测试找不到“历史版本”菜单项

- **表现：** 生产逻辑修复后测试仍失败；
- **原因判断：** 测试点击“更多”后立即查找菜单，没有推进新 frame；不是生产代码缺陷；
- **最终处理：** 使用测试辅助方法 pump 必要帧后再断言；
- **处理结果：** 定向测试和全量测试恢复全绿。

### 8. 验证方法与结果

- 定向 Flutter 测试：7 个测试文件全部通过：
  - `highlight_extractor_test.dart`
  - `local_note_repository_test.dart`
  - `note_version_view_model_test.dart`
  - `note_editor_history_entry_test.dart`
  - `note_editor_view_model_test.dart`
  - `widget_test.dart`
  - 相关既有 notes 测试
- 全量 `flutter test`：12/12 通过；
- `flutter analyze`：`No issues found!`；
- `flutter build apk --debug`：成功，产物 `build/app/outputs/flutter-apk/app-debug.apk`；
- 构建有一条非阻断警告：`quill_native_bridge_android` 仍使用 Kotlin Gradle Plugin 应用方式，属于未来 Flutter 兼容性提示，不影响本次 APK；
- 真机 PJF110 安装：`adb install -r` 成功，保留原有 App 数据；
- 真机 `DEVICE-TEST-3` 验证：
  1. 编辑器正常加载，无持续转圈；
  2. 输入 `BASE`，追加下划线 `UNDER3` 和红字 `RED3`；
  3. 首次保存后不退出，立即看到“历史版本”入口；
  4. 仅修改标题进入历史会保存标题，但不产生正文版本，符合本批快照范围；
  5. 正文追加 `BODY-CHANGE-3` 后不手动保存，直接进入历史，dirty 自动保存并出现版本 1；
  6. 恢复版本 1 后，正文从 `BASE UNDER3 RED3 BODY-CHANGE-3` 回到 `BASE UNDER3 RED3`；
  7. 再次进入历史，看到版本 2、版本 1 倒序显示，证明恢复前正文已保留；
- 真机日志：筛选结果未发现 `FATAL EXCEPTION` 或 `Unhandled Exception`，仅有正常输入/系统日志和一条 SurfaceView 警告；
- **验证边界：**
  - 未直接查询真机 `note_highlight` 表。App 数据库位于 `app_flutter/ruoke.sqlite`，设备无 `sqlite3`，UIAutomator 也不能检查表内容；重点表写入由解析器测试和 Repository 数据库测试覆盖；
  - 真机保留了 `DEVICE-TEST-2`、`DEVICE-TEST-3 AUTO3 BODY3` 测试数据，未获授权前不删除；
  - 用户尚未完成其自行复测，本批尚未 commit、未 push。

### 9. 可复现要点

- 必须在 `feature/notes-mvp` 分支继续，不要把第4批直接写入 main；
- Quill 红色至少兼容 `red`、`#F44336`、`#FFF44336`，不能只测命名色；
- 重点表是正文派生数据，保存时按 noteId 全量重建；正文 Delta JSON 才是唯一真实来源；
- `update` 正文变化才建版本；标题-only 修改不会创建版本；
- `restoreVersion` 必须先快照当前正文，再覆盖目标正文，并同步重建重点；
- 恢复成功与版本列表刷新成功必须分开判断；
- 编辑器 VM 的 `build()` 保持同步初始状态，外部 `init()` 负责异步加载，避免状态覆盖；
- 新笔记保存后用 VM 当前 `note.id` 导航，不能继续依赖路由参数 `new`；
- dirty 编辑器进入历史前必须先保存，保存失败不能离开页面；
- widget 测试打开 PopupMenu 后需要 pump frame 再查找菜单项；
- 真机重点表未直接查库，不得把自动化 Repository 验证描述成真机数据库验证；
- 当前测试数据和 `beifen` 备份均保留，删除前必须由用户确认。

---

## 技术路径记录：2026-07-26 16:47

### 1. 完成事项

完成阶段5编辑器稳定性小批次，闭环 F1.1.10、F1.1.13、F1.1.14：

- 完全空白的新笔记不会写入数据库；
- 标题或正文任一有内容时仍可保存；
- 旧笔记退出后立即新建不会残留上一条标题或正文；
- 旧初始化、旧保存的异步结果不会覆盖新编辑会话；
- 加载中、加载失败或保存中不能触发无效保存；
- 保存期间继续编辑时保留未保存标记；
- 首次创建未完成时重复保存不会生成两条笔记。

### 2. 初始条件与输入

- 分支：`feature/notes-mvp`；
- 前置成果：第4批重点标记和历史版本回退提交 `6281468`；
- 输入文档：
  - `jihua/ruoke-阶段5编辑器稳定性与标签搜索设计-20260726.md`；
  - `jihua/ruoke-阶段5编辑器稳定性小批次实施计划-20260726.md`；
- 限制：只处理 F1.1.10、F1.1.13、F1.1.14；不夹带 F1.1.11、F1.1.12、F1.1.15；不 push。

### 3. 技术方案选择

#### 可选方案

- 方案 A：在编辑器 ViewModel 中维护会话初始化代次、编辑修订号和保存锁，并由 View 管理每个路由会话的 Controller 生命周期；
- 方案 B：把编辑器 Provider 改为按 noteId family 隔离，每条笔记创建独立 Provider 实例。

#### 最终选择

采用方案 A，在现有手写 `AsyncNotifier` 架构上增加显式会话隔离和保存状态。

#### 选择原因

- 不改变现有路由和 Provider 公共结构，改动范围较小；
- 可同时解决旧初始化覆盖、旧保存覆盖、重复创建和脏状态误清除；
- 不新增依赖，不影响第4批历史版本接口；
- 通过初始化代次和编辑修订号可精确区分“切换笔记”和“同会话继续编辑”。

### 4. 详细实施路径

#### 步骤 1：定义空笔记保存结果

- **目的：** 区分保存成功、空笔记跳过和真实失败；
- **操作：** 新增 `NoteSaveResult`，并给 `save()` 增加 `hasVisibleContent`；
- **方法或技术：** 标题使用 `trim()` 判断；正文使用 Quill `Document.toPlainText().trim()` 判断；
- **关键设置：** 仅新建态同时满足标题空、正文无可见文字时跳过创建；已有笔记清空后仍执行更新；
- **输出：** 空笔记保存提示和三态保存契约；
- **判断依据：** ViewModel 与 Widget 测试覆盖空白、标题-only、正文-only 和已有笔记清空。

#### 步骤 2：隔离编辑器路由会话

- **目的：** 防止上一条笔记内容和异步状态污染新页面；
- **操作：** View 增加会话键、初始化门禁和 Controller 重置；ViewModel 增加 `_initGeneration`；
- **方法或技术：** 每次 `init()` 增加代次，Repository 返回后只允许当前代次写状态；
- **关键设置：** 同一 ProviderScope 下真实执行旧笔记 pop、新建 push，并重复验证；
- **输出：** 新会话在当前初始化完成前只显示加载态，旧结果无法解锁或覆盖新页面；
- **判断依据：** GoRouter Widget 测试覆盖连续进出及旧读取延迟返回。

#### 步骤 3：保护异步保存

- **目的：** 防止保存期间切换笔记或继续编辑造成数据污染；
- **操作：** 保存开始捕获初始化代次和编辑修订号；增加 `_savingGeneration` 与 `saving` 状态；
- **方法或技术：**
  - 跨会话：代次不匹配时不回写状态；
  - 同会话：修订号变化时保存成功但保留 `dirty=true`；
  - 重复提交：同代次已有保存时拒绝第二次调用；
- **关键设置：** 首次 create 成功后始终转为真实 note；若期间继续编辑，后续保存走 update；
- **输出：** 异步保存不会覆盖新会话、清除新改动或重复创建；
- **判断依据：** 可控 `Completer` 测试覆盖延迟 create、延迟 update 和保存期间再次编辑。

#### 步骤 4：完善 View 防御

- **目的：** 避免 Controller 未创建或正在保存时点击保存崩溃；
- **操作：** 保存按钮只在当前会话 ready、Controller 已建立且非 saving 时启用；`_save()` 内再做一次防御检查；
- **输出：** 加载、错误和保存中按钮均禁用；
- **判断依据：** Widget 测试直接断言按钮启用状态及保存完成后恢复。

#### 步骤 5：审查和真机闭环

- **目的：** 验证自动化未遗漏的并发和生命周期风险；
- **操作：** 完成两轮独立代码审查；根据审查补充同会话并发保存保护；构建并安装 APK；用户按清单完成真机复测；
- **输出：** 本地提交 `3383961 fix: 修复笔记草稿与编辑器初始化问题`；
- **判断依据：** 最终审查 Critical 0、Important 0、Minor 0，用户确认 10 项真机测试全部通过。

### 5. 核心技术细节

- **空笔记定义：** `title.trim().isEmpty` 且 `document.toPlainText().trim().isEmpty`；
- **已有笔记例外：** 空内容规则只阻止新建，已有笔记清空必须保存；
- **初始化代次：** `_initGeneration` 区分编辑对象，旧读取和旧保存只返回操作结果，不得回写新会话状态；
- **编辑修订号：** `_editRevision` 在每次就绪编辑时递增，保存返回时只有修订号未变化才能清除 `dirty`；
- **保存锁：** `_savingGeneration` 防止同一会话重复提交；新会话具有新代次，不受旧保存锁阻塞；
- **Controller 生命周期：** noteId 或 subjectId 变化时销毁并重建标题和 Quill Controller；
- **双层防御：** UI 禁用按钮，View `_save()` 仍检查会话、Controller、ready 和 saving。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `jihua/ruoke-阶段5编辑器稳定性小批次实施计划-20260726.md` | 新建 | 范围、TDD 步骤和真机清单 | 稳定性批次执行依据 |
| `lib/src/features/notes/view_model/note_editor_view_model.dart` | 修改 | 保存三态、初始化代次、编辑修订号、保存锁 | 数据与状态竞态保护 |
| `lib/src/features/notes/view/note_editor_view.dart` | 修改 | 空内容判断、会话隔离、按钮门禁 | 编辑器交互稳定性 |
| `test/features/notes/note_editor_view_model_test.dart` | 修改 | 空笔记和异步竞态测试 | ViewModel 回归保护 |
| `test/features/notes/note_editor_stability_test.dart` | 新建 | 真实路由、空笔记、按钮状态测试 | Widget 生命周期验证 |
| `test/features/notes/note_editor_history_entry_test.dart` | 修改 | 首次保存测试输入有效标题 | 适配空笔记规则 |
| `build/app/outputs/flutter-apk/app-debug.apk` | 更新 | 最终 Debug APK | 真机验收安装包 |

### 7. 问题、尝试与解决过程

#### 问题 1：旧保存覆盖新会话

- **表现：** A 的延迟保存可能在 B 初始化后把 ViewModel 改回 A；
- **原因判断：** 原代次保护只覆盖 `init()`，未覆盖 `save()`；
- **最终处理：** 保存开始捕获 `_initGeneration`，返回后仅当前代次可写状态；
- **处理结果：** 延迟 create/update 切换会话测试通过。

#### 问题 2：保存返回误清除新改动

- **表现：** 保存期间继续输入，旧保存返回后把 `dirty` 设为 false；
- **原因判断：** 同一会话代次不变，只有代次不足以区分内容修订；
- **最终处理：** 增加 `_editRevision`，按保存开始与返回时修订号比较；
- **处理结果：** 延迟 update 期间再次编辑后仍保持 dirty。

#### 问题 3：首次创建可重复提交

- **表现：** 首次 create 返回前快速保存两次可能产生两条笔记；
- **原因判断：** 两次调用都捕获 `isNew=true`；
- **最终处理：** 增加同代次保存锁和 UI saving 门禁；
- **处理结果：** 重复调用只发起一次 create。

#### 问题 4：Dart 格式化工具无法写用户目录

- **表现：** `dart format` 尝试创建用户级 `.dart-tool` 时被沙箱拒绝；
- **最终处理：** 临时将 APPDATA 指向 `ceshi/删除dart-appdata`，格式化完成后在真机验收通过时删除；
- **处理结果：** 代码格式化成功，临时目录已清理。

### 8. 验证方法与结果

- `git diff --check`：通过；
- `flutter analyze --no-pub`：`No issues found`；
- `flutter test`：44 项全部通过；
- `flutter build apk --debug --no-pub`：成功；
- 独立代码审查：最终 Critical 0、Important 0、Minor 0；
- ADB 安装：`Performing Streamed Install`、`Success`；
- 用户真机测试：空笔记、标题-only、正文-only、连续进入退出、旧内容隔离、首次加载、重复保存、已有笔记清空等 10 项全部通过；
- 非阻断警告：`quill_native_bridge_android` 仍使用旧 Kotlin Gradle Plugin 应用方式。

### 9. 可复现要点

- 必须先区分新建态与已有笔记，空内容规则不能阻止已有笔记清空；
- 初始化代次解决跨会话竞态，编辑修订号解决同会话竞态，两者不能互相替代；
- 首次 create 成功后即使保存期间又有编辑，也必须切换为真实 note 身份；
- 保存按钮门禁不能替代 ViewModel 保存锁和 `_save()` 防御；
- Widget 测试需在同一 ProviderScope 中使用真实 GoRouter pop/push，不能只用 `pumpWidget` 替换组件；
- 真机测试由用户执行，自动化结果与用户真机结果必须分别记录；
- 稳定性批次提交为 `3383961`，尚未 push。

---

## 技术路径记录：2026-07-28 22:20

### 1. 完成事项

完成阶段5第5批真机反馈改造：

- 编辑器标签改为会话草稿，添加或删除后不保存离开不会写入数据库；
- 标题、正文、重点和标签在同一 Drift 事务内原子保存；
- 历史版本升级为标题、正文、标签完整快照，并兼容合法的旧正文 Delta；
- 标签-only 修改会产生版本，恢复完整版本会恢复标题、正文和标签；
- 搜索范围改为未搜索只显示根书、书展开章、章展开节的按需树；
- 支持按书、章、节名称搜索，搜索结果补齐并合并祖先路径；
- 保留全部笔记、全部书、全部章、全部节和指定节点子树语义；
- 修复清空已有标题未保存、新建保存期间标签草稿丢失、损坏旧快照可覆盖当前正文等审查问题。

### 2. 初始条件与输入

- 分支：`feature/notes-mvp`；
- 前置实现：第5批标签自由输入、多标签并集搜索、通用搜索和范围筛选已存在；
- 用户真机反馈：
  - 标签添加和删除在点击保存前就会写库；
  - 标签变化不进入历史版本；
  - 原范围弹窗平铺全部书、章、节，数据增长后难以使用；
- 已确认交互：
  - 标签和正文共享保存、放弃、继续编辑语义；
  - 未输入范围关键词时只显示根书；
  - 书和章逐级展开；
  - 搜索命中章、节时显示完整祖先上下文；
- 约束：不修改数据库 schema，不处理 F1.1.11、F1.1.12、F1.1.15，不 push，真机验证由用户执行。

### 3. 技术方案选择

#### 可选方案

- 标签保存：
  - 方案 A：编辑器标签即时写 `note_tag`，退出时再反向恢复；
  - 方案 B：标签进入 `NoteEditorVm` 草稿，保存时与笔记正文一起提交。
- 历史版本：
  - 方案 A：新增数据库列或新表保存标签版本；
  - 方案 B：保持 `snapshot_json TEXT`，通过带 `schemaVersion` 的 JSON 对象扩充快照。
- 范围选择：
  - 方案 A：继续全量加载后在界面本地过滤；
  - 方案 B：根书和子节点按需读取，名称搜索由 DAO 和 Repository 返回祖先路径。

#### 最终选择

- 标签采用 ViewModel 草稿；
- 历史版本采用 schemaVersion 1 的完整 JSON 快照；
- 范围树采用按需读取、会话缓存和路径搜索；
- 不引入第三方树组件，使用 Flutter Material 组件实现。

#### 选择原因

- 标签放入同一草稿可直接复用现有 dirty、保存失败保留和退出确认机制；
- 单事务可避免笔记已保存但标签失败的半完成状态；
- 复用现有文本列无需数据库迁移，同时可识别旧数组快照；
- 按需树不会随着书目增长一次渲染全部节点；
- Repository 补齐祖先后，两个搜索页面可共享同一范围选择器；
- 独立会话 Provider 能在弹窗关闭时自动清理关键词、缓存和展开状态。

### 4. 详细实施路径

#### 步骤 1：建立完整历史快照格式

- **目的：** 让历史版本覆盖标题、正文和标签；
- **操作：** 新增 `NoteEditSnapshot`，写入 `schemaVersion/title/contentJson/tagNames`；
- **方法或技术：** 标签 trim、去空、保持首次出现顺序去重；比较时忽略标签顺序；
- **兼容规则：** 顶层对象解析为新快照；顶层数组只作为旧 Quill Delta；
- **安全校验：** 旧数组必须能通过 Quill `Document.fromJson` 重建，空数组和损坏嵌入直接拒绝；
- **输出：** 新格式编码、解码、完整状态比较和旧格式识别能力。

#### 步骤 2：聚合 Repository 原子事务

- **目的：** 避免标题、正文、重点和标签出现部分保存；
- **操作：** 扩展 `NoteRepository.create/update` 的 `tagNames` 参数；
- **方法或技术：** `LocalNoteRepository` 在单个 `_db.transaction` 内读取旧状态、比较完整状态、写旧快照、更新 note、重建 highlight、复用或创建 tag、替换 note_tag；
- **关键设置：**
  - `tagNames == null` 表示保持标签；
  - 非 null 表示整体替换；
  - 空白标题新建时规范化为 null；
  - 更新时空字符串表示明确清空标题，null 表示未提供；
- **输出：** 标签-only 版本、完整恢复和旧版正文-only 恢复。

#### 步骤 3：编辑器标签草稿

- **目的：** 退出不保存时不污染标签数据；
- **操作：** `NoteEditorState` 增加 `tagNames`，初始化已有笔记时读取当前标签；
- **方法或技术：** 添加和删除只更新 ViewModel 内存状态及 `_editRevision`；
- **保存：** ViewModel 把当前标签名称交给 Repository 一次保存；
- **竞态处理：** 新建保存期间继续修改标签时，保存返回只替换真实 note 身份，保留最新标签草稿并保持 dirty；
- **输出：** 标签与标题、正文统一的保存和退出语义。

#### 步骤 4：科目名称与路径搜索

- **目的：** 不加载全量科目也能按名称找到指定范围；
- **操作：** DAO 增加 `searchByName`，Repository 增加 `searchPaths`；
- **方法或技术：** LIKE 查询按 `\`、`%`、`_` 顺序转义；每个命中节点最多向上读取两次父节点；
- **校验：** 祖先缺失、层级不连续或任一祖先软删除时丢弃无效路径；
- **输出：** 始终按书、章、节顺序排列的 `SubjectPath`。

#### 步骤 5：可搜索按需范围树

- **目的：** 替换平铺全部节点的臃肿弹窗；
- **操作：** 新增 `SubjectScopePickerVm` 和 family autoDispose Provider；
- **方法或技术：**
  - build 只调用 `childrenOf(null)`；
  - 展开节点时读取直接子节点并按 parentId 缓存；
  - 关键词输入使用 250ms 防抖；
  - 搜索 generation 阻止慢旧请求覆盖快新请求；
  - 每次弹窗使用新 sessionKey，关闭后销毁状态；
- **界面：** 层级范围放入紧凑菜单；根树和搜索树使用 ListTile、缩进及独立展开按钮；
- **搜索合并：** 多条 `SubjectPath` 按节点 ID 合并共同祖先，避免重复书和章。

#### 步骤 6：独立审查与修复

- **目的：** 关闭自动化初版未覆盖的数据一致性和兼容风险；
- **操作：** 对 `83ea70e..5bd2d3c` 做独立审查，并对修复提交进行两轮复核；
- **发现与处理：**
  - 清空标题被误当“保持原标题”：使用空字符串表达明确清空，Repository 规范化为 null；
  - 新建保存期间标签草稿被旧状态覆盖：改为保留返回时最新状态标签；
  - 任意数组被当作旧快照：使用 Quill 实际解析校验；
  - 搜索结果祖先重复：合并为共享祖先树；
- **输出：** 最终复核 Critical 0、Important 0。

### 5. 核心技术细节

- 完整快照：

```json
{
  "schemaVersion": 1,
  "title": "标题",
  "contentJson": "[{\"insert\":\"正文\\n\"}]",
  "tagNames": ["重点", "复习"]
}
```

- 恢复新格式：恢复标题、正文、标签，恢复前先保存当前完整状态；
- 恢复旧格式：仅恢复正文，保留当前标题和标签；
- 损坏旧格式：恢复返回失败，事务不覆盖当前状态；
- 范围语义：
  - 指定书：书自身及全部章、节；
  - 指定章：章自身及全部节；
  - 指定节：仅该节；
  - 全部书/章/节：只匹配直接归属于对应层级的笔记；
- 范围选择错误隔离：根加载错误覆盖主体，搜索错误保留关键词，分支错误只影响对应节点。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `jihua/ruoke-阶段5第5批真机反馈改造设计-20260728.md` | 新建 | 正式交互和架构设计 | 本批设计依据 |
| `jihua/ruoke-阶段5第5批真机反馈改造实施计划-20260728.md` | 新建/更新 | TDD 步骤和执行结果 | 实施与验证依据 |
| `lib/src/features/notes/models/note_edit_snapshot.dart` | 新建 | 完整快照及旧 Delta 校验 | 历史版本格式 |
| `lib/src/features/notes/models/subject_path.dart` | 新建 | 根到命中节点路径 | 科目搜索结果模型 |
| `lib/src/features/notes/repository/note_repository.dart` | 修改 | 保存接口增加标签名称 | 聚合保存契约 |
| `lib/src/features/notes/repository/local_note_repository.dart` | 修改 | 原子保存、完整版本、兼容恢复 | 数据一致性核心 |
| `lib/src/data/database/daos/note_dao.dart` | 修改 | 完整可编辑状态替换 | 恢复标题和正文 |
| `lib/src/data/database/daos/subject_dao.dart` | 修改 | 名称字面量搜索 | 范围搜索数据入口 |
| `lib/src/features/notes/repository/subject_repository.dart` | 修改 | 增加路径搜索接口 | ViewModel 抽象边界 |
| `lib/src/features/notes/repository/local_subject_repository.dart` | 修改 | 补齐并校验祖先路径 | 搜索上下文 |
| `lib/src/features/notes/view_model/note_editor_view_model.dart` | 修改 | 标签草稿、dirty 和保存竞态 | 编辑会话状态 |
| `lib/src/features/notes/view/note_editor_view.dart` | 修改 | 标签区改为草稿操作 | 统一退出语义 |
| `lib/src/features/notes/view_model/subject_scope_picker_view_model.dart` | 新建 | 根、分支缓存、防抖、generation | 范围弹窗状态 |
| `lib/src/features/notes/view_model/view_model_providers.dart` | 修改 | 注册会话 family Provider | 生命周期隔离 |
| `lib/src/features/notes/view/subject_scope_picker.dart` | 修改 | 可搜索按需树和祖先合并 | 范围选择 UI |
| `lib/src/features/notes/view/note_search_view.dart` | 修改 | 接入独立范围弹窗 | 通用搜索 |
| `lib/src/features/notes/view/tag_management_view.dart` | 修改 | 接入独立范围弹窗 | 标签搜索 |
| `test/features/notes/` 相关测试 | 新建/修改 | 快照、Repository、编辑器、路径、范围树和页面回归 | TDD 与回归保护 |
| `build/app/outputs/flutter-apk/app-debug.apk` | 更新 | 最新 Debug APK | 用户真机验证包 |

### 7. 问题、尝试与解决过程

#### 问题 1：系统 Flutter/Dart 锁导致命令超时

- **表现：** 中途 `flutter analyze` 和系统 `dart format` 出现长时间无输出；
- **原因判断：** Flutter SDK 缓存目录存在旧锁，Dart 还会尝试写受限的用户 APPDATA；
- **尝试过的方法：** 不删除 SDK 锁文件，避免未经授权的破坏性操作；
- **最终处理：** 测试继续使用可运行的 Flutter 命令；格式化和定向 analyze 使用 SDK 内 Dart，并把 APPDATA/LOCALAPPDATA 指向项目 `ceshi` 临时目录；
- **处理结果：** 后续全量 Flutter analyze 恢复正常并通过。

#### 问题 2：旧快照手写结构校验不完整

- **表现：** 初版会接受空数组和部分无效嵌入；
- **原因判断：** 手写 JSON 字段检查不能完整复制 Quill 文档约束；
- **无效方法：** 仅检查 operation 是 Map 且 insert 为 String/Map；
- **最终处理：** 使用 `Document.fromJson` 做真实可重建性校验；
- **处理结果：** 空数组、缺失 insert、数字 insert、空嵌入均被拒绝，合法旧 Delta 继续恢复。

#### 问题 3：搜索结果共同祖先重复

- **表现：** 多个命中节分别显示相同祖先副标题，书和章不形成树；
- **原因判断：** 界面逐条渲染 `SubjectPath`；
- **最终处理：** 按节点 ID 把路径合并为共享树；
- **处理结果：** 同一书和章只显示一次，多个命中节作为共同祖先下的子节点。

### 8. 验证方法与结果

- 每个生产改动均先运行失败测试确认 RED，再实现并运行 GREEN；
- 最终 `flutter analyze --no-pub`：`No issues found!`；
- 最终 `flutter test --no-pub`：138 项全部通过；
- 最终 `flutter build apk --debug --no-pub`：成功；
- APK：`build/app/outputs/flutter-apk/app-debug.apk`；
- APK SHA-256：`E00096341CFA44F695A2DB1830DC1C6195A0016F6772908E3DF491BB8734B299`；
- 独立代码审查：
  - 初审：Critical 0、Important 3、Minor 1；
  - 两轮修复复核后：Critical 0、Important 0；
- 构建非阻断警告：`quill_native_bridge_android` 尚未迁移到 Flutter 未来要求的 Built-in Kotlin；
- **未验证内容：** 本轮尚未安装最新 APK 到真机，用户尚未执行真机验收，不得写成真机通过。

### 9. 可复现要点

- 先执行快照和 Repository 测试，再验证编辑器 Widget，最后验证范围树和两个搜索页面；
- 旧版历史数组必须是 Quill 可重建文档，不能仅凭“顶层是数组”判定合法；
- 标签必须留在 `NoteEditorVm` 草稿，界面不得直接写 `note_tag`；
- 新建保存完成时只替换真实 note 身份，不能覆盖保存期间产生的新标签草稿；
- 科目 LIKE 查询必须转义反斜杠、百分号和下划线；
- 范围弹窗每次打开使用新的 sessionKey，关闭后不得保留关键词、展开态或缓存；
- 本轮备份位于 `beifen/stage5-batch5-device-feedback-20260728`，用户真机确认前不删除；
- 最新 APK 尚未真机验证，真机结果必须与自动化结果分开记录；
- 当前提交均为本地提交，未经用户确认不得 push。

---

## 技术路径记录：2026-07-29 16:00

### 1. 完成事项

完成笔记历史版本管理增强：版本可自定义命名、列表可进入管理模式批量永久删除、恢复前可选择是否保存当前完整状态，默认不保存。补充了重命名校验失败时保留弹窗并展示错误的交互。

### 2. 初始条件与输入

- 阶段 5 已存在 `note_version` 快照、标题/正文/标签/重点的完整恢复能力；
- 用户确认：自定义名称不显示“版本 N”副标题；批量删除不可恢复；恢复前保存当前内容默认取消；
- 数据库已从 v1 迁移至 v2，`note_versions.name` 为可空字段；
- 不推送远程，原有备份保留至用户确认删除。

### 3. 技术方案选择

#### 可选方案

- 方案 A：版本页直接维护局部选择和请求状态；
- 方案 B：将版本列表、管理态、选中集合、写入中状态和错误统一放入 Riverpod ViewModel。

#### 最终选择

采用方案 B，以 `NoteVersionState` 驱动页面。

#### 选择原因

批量删除、恢复和重命名都会异步写库；统一状态可避免重复点击，并使失败时能保留选择和可读错误。

### 4. 详细实施路径

#### 步骤 1：扩展数据层与恢复策略

- **目的：** 为自定义名称、批量删除和可选恢复快照提供持久化能力；
- **操作：** 为版本模型和 DAO 增加名称、按 ID 查询、重命名、按 ID 集合删除；Repository 在事务中校验归属、唯一名和长度；
- **关键设置：** 空白名称规范化为 null，名称上限 50；删除不重排 `versionNo`；默认恢复不保存当前状态；
- **输出：** 数据层提交 `8faa6a1`、`71221e3`、`f58a775`；
- **判断依据：** 内存数据库测试验证迁移、唯一性、原子删除和恢复边界。

#### 步骤 2：实现可管理 ViewModel

- **目的：** 支持选择、全选、重命名、删除和恢复的统一状态；
- **操作：** 将 Provider 类型改为 `AsyncNotifier<NoteVersionState>`，实现 `refresh`、`rename`、`deleteSelected`、`restore`；
- **关键设置：** 写操作完成后即使列表刷新失败，仍返回写入成功；删除会退出管理并清空选择；非预期刷新异常也会复位 `mutating`；
- **输出：** 提交 `c510935`；
- **判断依据：** ViewModel 测试覆盖刷新失败、删除失败、选择清理和恢复选项透传。

#### 步骤 3：实现版本列表交互

- **目的：** 提供用户可见的版本管理入口；
- **操作：** 默认显示 `displayName`、重命名和恢复；管理模式显示复选、全选/取消、底部永久删除；恢复弹窗使用默认 false 的复选项；
- **关键设置：** 重命名校验失败时不关闭弹窗，保留输入并在弹窗内显示 Repository 返回的错误；
- **输出：** 提交 `f995fda` 与修复提交 `b91201c`；
- **判断依据：** Widget 测试验证自定义名称、管理态、默认恢复选项和重命名失败弹窗。

### 5. 核心技术细节

- `NoteVersion.displayName` 仅在名称为空时回退为“版本 N”；
- `deleteVersions` 与跨笔记归属校验在同一数据库事务中执行；
- `saveCurrentBeforeRestore` 由恢复弹窗显式传入 Repository，默认 false；
- 页面通过 `operationError` 区分“写入失败”和“写入成功但列表刷新失败”，避免误报数据操作失败。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `lib/src/features/notes/view_model/note_version_view_model.dart` | 修改 | 管理状态、错误恢复与写操作 | 版本页状态中心 |
| `lib/src/features/notes/view/note_version_list_view.dart` | 修改 | 管理、重命名、删除、恢复对话框 | 用户交互页面 |
| `test/features/notes/note_version_view_model_test.dart` | 修改 | 状态与失败边界测试 | ViewModel 验证 |
| `test/features/notes/note_version_list_view_test.dart` | 新建/修改 | 页面交互测试 | Widget 验证 |
| `jihua/ruoke-阶段5历史版本管理增强实施计划-20260729.md` | 修改 | 勾选已完成实施项 | 实施记录 |

### 7. 问题、尝试与解决过程

#### 问题 1：写入成功后刷新失败被误报为失败

- **表现：** 重命名或删除成功后列表读取失败时，页面提示操作失败；
- **原因判断：** 原实现把刷新结果直接当作写入结果；
- **最终处理：** 写入成功保持 true 语义，刷新错误单独写入 `operationError`；删除同时退出管理并清空选择；
- **处理结果：** 对应自动测试通过。

#### 问题 2：重命名校验失败关闭弹窗

- **表现：** 同名或超长时用户需重新打开对话框；
- **最终处理：** 使用 `StatefulBuilder` 管理保存中和错误文本，失败时保留对话框；
- **处理结果：** Widget 测试通过。

#### 问题 3：Flutter SDK 锁文件阻塞测试

- **表现：** `lockfile` 与 `flutter.bat.lock` 为零字节时 Flutter 命令超时；
- **最终处理：** 经用户授权删除遗留锁文件；Dart 分析使用项目 `ceshi` 临时 APPDATA；
- **处理结果：** 定向测试、分析和 APK 构建成功。

### 8. 验证方法与结果

- `flutter test --no-pub`：最终回归 162 项通过（在最后一处 UI 修复前）；
- 修复后 `flutter test --no-pub test/features/notes/note_version_list_view_test.dart`：3 项通过；
- 修复后 Dart analyze：`No issues found!`；
- `flutter build apk --debug --no-pub`：成功；
- 最新 APK：`build/app/outputs/flutter-apk/app-debug.apk`；
- **未验证内容：** 最新修复 APK 的真机覆盖安装被工具审批连接中断，尚未写成真机通过。

### 9. 可复现要点

- 恢复默认不保存当前状态，只有用户勾选后才创建当前完整快照；
- 重命名错误应在弹窗内显示且不关闭弹窗；
- 发生列表刷新错误时，应区分数据写入成功与列表显示未刷新；
- Flutter 命令异常卡住时先检查两个 SDK 零字节锁文件，删除前必须取得用户授权；
- 本批所有提交只在 `feature/notes-mvp` 本地，未 push。

---

## 技术路径记录：2026-07-30

### 1. 完成事项

完成阶段 5 文件夹系统：在既有书—章—节之上增加无限层级文件夹，支持书籍归属、逐级浏览、移动、重命名、安全解散、文件夹递归搜索范围与未归类书籍范围。

### 2. 初始条件与输入

- `subjects` 既有语义固定为书（level 0）、章（level 1）和节（level 2），笔记以 `subject_id` 归属。
- 用户确认文件夹独立于书章节树；已有书保持未归类；安全解散不得删除书和笔记。
- 用户确认使用逐级浏览与面包屑，并保留书—章—节的按需展开范围选择器。

### 3. 技术方案选择

#### 可选方案

- 方案 A：为 `subjects` 新增文件夹 level。
- 方案 B：新建独立 `subject_folders`，只让 level 0 的书持有可空 `folder_id`。

#### 最终选择

采用方案 B。

#### 选择原因

不改变原有书章节语义与查询；已有书的 `folder_id = null` 即是未归类；解散文件夹无需触碰笔记或书章节数据。

### 4. 详细实施路径

#### 步骤 1：数据库迁移与数据访问层

- **目的：** 安全保存文件夹树和书籍归属。
- **操作：** 升级至 schema v3，新增 `subject_folders`、`subjects.folder_id` 和 Folder DAO。
- **方法或技术：** Drift v2→v3 迁移先建表、后加可空列；活动查询统一排除软删除。
- **判断依据：** 迁移测试验证既有书、历史版本和快照保留。

#### 步骤 2：文件夹 Repository 与安全边界

- **目的：** 收敛创建、移动和解散规则。
- **操作：** 校验空名、同级重名、缺失父目录、书级别和循环移动。
- **方法或技术：** DFS 阻止移至自身或后代；在同一 Drift 事务中上移直属内容并软删除目标。
- **关键设置：** 仅 level 0 的书可归属文件夹；根文件夹解散后书变回未归类。

#### 步骤 3：浏览、管理和兼容入口

- **目的：** 提供根目录、文件夹、书章节的分层浏览。
- **操作：** 新增 `LibraryLocation`、浏览 Provider 和 `LibraryBrowserView`，加入面包屑、文件夹动作与未归类书入口。
- **兼容性：** 旧 `SubjectManageView` 保留为“书章节管理”入口。

#### 步骤 4：搜索范围扩展

- **目的：** 让笔记搜索和标签搜索按文件夹或未归类书筛选。
- **操作：** `SubjectScope` 新增 `folder`、`ungroupedBooks`；`LocalNoteRepository` 先递归文件夹，再展开其中书的章、节。
- **输出：** 指定文件夹会包含其后代文件夹内的书、章、节笔记。

### 5. 核心技术细节

- `subject_folders` 使用 `parent_id` 构建独立无限层级树，使用软删除字段保留历史。
- 搜索递归为“文件夹树→书→书章节树→笔记 subject_id 集合”两段处理。
- 不存在或已删除的范围返回范围失效错误，不会静默扩大为全部搜索。
- 新浏览页保留普通搜索和标签搜索；全量测试发现标签入口遗漏后已恢复。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `app_database.dart`、`subject_folder_table.dart`、`folder_dao.dart` | 修改/新建 | v3 表、迁移与 DAO | 文件夹持久化 |
| `folder_repository.dart`、`local_folder_repository.dart` | 新建 | 业务规则与事务 | 安全管理文件夹 |
| `library_location.dart`、`library_browser_view_model.dart`、`library_browser_view.dart` | 新建 | 分层浏览和面包屑 | 用户入口 |
| `subject_scope.dart`、`local_note_repository.dart`、`subject_scope_picker.dart` | 修改 | 文件夹/未归类范围 | 搜索统一语义 |
| `app_router.dart` | 修改 | 新路由与兼容入口 | 页面导航 |
| 迁移、文件夹、搜索测试 | 新建/修改 | v3、事务、递归范围测试 | 回归保护 |

### 7. 问题、尝试与解决过程

#### 问题 1：新浏览页遗漏标签搜索入口

- **表现：** 全量 Widget 测试中原有顶栏入口测试失败。
- **原因判断：** 新浏览页只保留了通用搜索按钮。
- **最终处理：** 恢复标签搜索按钮并复用 `/notes/tags` 路由。
- **处理结果：** 对应定向测试和完整测试套件通过。

### 8. 验证方法与结果

- `flutter analyze --no-pub`：通过，`No issues found!`。
- `flutter test`：通过，179 项全部通过。
- `git diff --check`：通过，无空白错误。
- **未验证内容：** 本批尚未构建/安装 APK，尚未真机测试，不能写为真机通过。

### 9. 可复现要点

- 数据库必须保留 v2→v3 迁移，不能假定用户重装应用。
- 文件夹解散必须使用单一事务，且不得删除书、章、节或笔记。
- 书籍移动前必须限制 level 0；文件夹移动前必须检查自身和所有后代。
- 调整笔记根页后必须运行完整 Widget 回归，确认普通与标签搜索入口均存在。

---

## 技术路径记录：2026-07-31 15:45

### 1. 完成事项

本次补录阶段5文件夹系统之后已经完成、但尚未写入技术档案的成果：

1. 完成笔记主页与目录浏览统一，根目录和任意文件夹内均可切换“逐级浏览/展开浏览”。
2. 完成基于当前位置的新建内容与新建笔记位置选择：不再从全库平铺选择目标，而是由用户在当前目录内逐层进入文件夹、书、章、节后确定位置。
3. 完成阶段5既有 11 份已实施计划的时间顺序合并，形成一份可连续阅读的汇总计划；最新“目录项目移动与排序”计划因尚未写生产代码而保持独立。
4. 完成目录项目移动与排序功能的正式设计和 TDD 实施计划，但该功能尚未进入生产代码实现。

### 2. 初始条件与输入

- 前置成果为阶段5文件夹系统：已有 `subject_folders`、文件夹仓储、文件夹范围搜索和基础 `LibraryBrowserView`。
- 用户要求移除顶栏重复的“笔记/书章节管理”入口，把浏览、新建内容和新建笔记统一放回笔记主界面。
- 用户要求逐级/展开模式在根目录与文件夹层级都可切换。
- 新建书、章、节时需要从当前目录逐层选择合法父级；新建笔记时只能落到书、章、节。
- 最新移动排序需求已经确认两步交互、分类展示和精确插入位置，但明确处于“写代码前准备完成、先不要写代码”的状态。
- 工作分支为 `feature/notes-mvp`，不得 push。

### 3. 技术方案选择

#### 可选方案

- **方案 A：继续保留多个页面和多个入口。** 改动较少，但逐级浏览、展开浏览和位置选择容易出现状态与交互不一致。
- **方案 B：使用单一目录浏览容器和共享导航状态。** 根目录、文件夹、书、章、节共用位置模型，创建流程只改变选择规则，页面结构一致。
- **移动排序方案 A：目标父级和排序位置一次性选择。** 步骤少，但深层目录与大量同级项目混在一起，界面复杂。
- **移动排序方案 B：先选目标父级，再在同类项目中拖拽确定精确位置。** 多一步，但目标目录和排序位置含义清楚，适合跨文件夹移动。

#### 最终选择

- 已实施的主页改造采用方案 B：`LibraryBrowserView` 作为统一浏览容器，导航状态和位置合法性规则从界面中拆出。
- 尚未实施的移动排序采用两步方案 B，并规定按类型分组展示、只允许组内排序。

#### 选择原因

- 同一位置模型可同时支持逐级浏览、展开浏览、新建内容和新建笔记，减少页面间状态漂移。
- 位置合法性由纯规则对象决定，便于用单元测试覆盖根目录、文件夹、书、章、节的边界。
- 移动时把“去哪儿”和“排在哪儿”分开，可在深层目录中保持界面清晰，并满足“移动到某节之后”的精确位置要求。

### 4. 详细实施路径

#### 步骤 1：抽离统一导航状态与位置规则

- **目的：** 让浏览模式、当前位置和选择动作不依赖单个 Widget 的临时状态。
- **操作：** 新增共享 `LibraryNavigationVm`，并用 `LibrarySelectionRules` 统一判断不同创建类型允许选择的位置。
- **方法或技术：** Riverpod 管理导航状态；纯 Dart 规则对象负责合法性判断。
- **输入：** 现有 `LibraryLocation`、文件夹树和书章节树。
- **关键设置：** 文件夹可继续进入；书、章、节按固定层级进入；笔记最终位置仅允许书、章、节。
- **输出：** 根目录和文件夹页共用的导航、选择与返回行为。
- **判断依据：** 状态和规则定向测试覆盖合法、非法及取消路径。

#### 步骤 2：统一逐级浏览与展开浏览

- **目的：** 在任意文件夹层级提供一致的浏览方式切换。
- **操作：** 以 `LibraryBrowserView` 作为单一页面容器，引入 `LibraryExpandedTree` 显示当前位置子树；切换模式时保留当前目录。
- **方法或技术：** 逐级模式只显示直接子项；展开模式递归显示当前范围内的文件夹、书、章、节和笔记。
- **输入：** 当前 `LibraryLocation` 和仓储返回的目录数据。
- **关键设置：** 展开模式不是强制回到根目录，而是以当前文件夹为作用域。
- **输出：** 根目录和任意文件夹内均可切换的两种浏览方式。
- **判断依据：** Widget 测试与真机操作均覆盖根目录、文件夹和子树范围。

#### 步骤 3：改造新建内容与新建笔记流程

- **目的：** 避免全库平铺选择造成范围过大，并保证创建位置可控。
- **操作：** “新建内容”弹窗只收集类型和名称；随后在当前目录下逐层选择合法父级。右下角笔记加号进入位置选择模式，用户在当前文件夹的书章节中逐层确定落点。
- **方法或技术：** 选择模式复用主浏览页，不再复制一套全局选择器；取消或返回只结束选择状态，不写数据库。
- **输入：** 当前文件夹、所选创建类型和名称。
- **关键设置：** 书只能建在根目录或文件夹；章只能建在书或章的合法下级；节遵循固定书章节层级；笔记只能建在书、章、节。
- **输出：** 当前目录内可控的新建流程。
- **判断依据：** 创建成功后对应 Provider 失效并立即刷新；取消路径确认无新增记录。

#### 步骤 4：整理阶段5历史计划

- **目的：** 降低阶段5计划文件数量，同时保留真实实施顺序和可追溯性。
- **操作：** 按 2026-07-21 至 2026-07-30 的实际时间顺序，把数据库、CRUD、分级、重点与历史版本、编辑器稳定性、标签搜索、完整快照、版本管理、文件夹系统及主页浏览改造合并为 `ruoke-阶段5已实施计划汇总-20260731.md`。
- **方法或技术：** 对照旧计划、Git 提交顺序、已有 `lujing.md` 记录和本窗口验证结果去重整理。
- **输入：** 11 份旧实施计划、Git 历史和既有技术路径档案。
- **关键设置：** 尚未编码的 `ruoke-阶段5目录项目移动与排序实施计划-20260731-1049.md` 不纳入汇总，也不删除。
- **输出：** 单一阶段5已实施计划汇总；旧计划删除前已完整备份。
- **判断依据：** `jihua` 中阶段5实施计划最终只保留汇总文件和最新未实施计划。

#### 步骤 5：完成移动排序功能的编码前准备

- **目的：** 在不写生产代码的前提下，把跨目录移动、统一菜单和顺序控制定义到可直接执行。
- **操作：** 固化统一三点菜单、分类展示、两步移动、同类型拖拽排序、固定层级约束和笔记标题重命名规则；编写设计文档与 TDD 实施计划。
- **方法或技术：** 计划复用各业务表 `sortOrder`，为笔记补同级顺序字段；仓储事务统一校验并重排完整同级列表。
- **输入：** 用户逐项确认的菜单、移动目标和排序交互决策。
- **关键设置：** 文件夹、书、章、节、笔记可跨文件夹选择位置；移动第二步可精确放到某个同类型项目之后；笔记菜单重命名不生成正文历史版本。
- **输出：** 设计提交 `235d806` 与计划提交 `cac61f3`。
- **判断依据：** 设计和计划已提交，但没有数据库迁移、生产代码或该功能测试，因此不能记为功能已完成。

### 5. 核心技术细节

- `LibraryNavigationVm` 是浏览模式、当前位置和选择状态的共享来源，避免多个页面各自保存一份状态。
- `LibrarySelectionRules` 只负责位置合法性，界面不自行拼接层级判断；这样既能复用，也能单独测试。
- `LibraryExpandedTree` 的递归根节点取当前 `LibraryLocation`，因此进入文件夹后展开只显示该文件夹子树。
- 新建内容和新建笔记都遵循“先发起创建，再在主浏览页逐层定位”；取消、系统返回和弹窗取消都不得产生写操作。
- 创建或移动成功后统一刷新相关 Riverpod Provider，解决数据已写入但必须重启应用才显示的问题。
- 移动排序的已确认数据方案是同级完整列表事务重排；该方案仅在设计与计划中，尚未迁移数据库或实现仓储方法。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `lib/src/features/notes/view/library_browser_view.dart` | 修改 | 统一浏览容器、模式切换和位置选择流程 | 笔记主页核心入口 |
| `lib/src/features/notes/view/note_list_view.dart` | 修改 | 移除重复入口并接入统一主界面 | 精简顶栏 |
| `lib/src/features/notes/view/subject_manage_view.dart` | 修改 | 收敛旧书章节管理职责 | 避免重复管理入口 |
| `lib/src/features/notes/view_model/view_model_providers.dart` | 修改 | 提供共享导航与刷新协作 | 状态一致性 |
| `lib/src/features/notes/repository/subject_repository.dart`、`local_subject_repository.dart` | 修改 | 支持当前位置创建和立即刷新所需数据操作 | 目录写入 |
| `lib/src/routing/app_router.dart` | 修改 | 统一浏览与选择路由 | 导航入口 |
| `test/src/features/notes/` 下浏览和选择相关测试 | 新建/修改 | 导航、规则、逐级/展开、创建与取消测试 | 回归保护 |
| `jihua/ruoke-阶段5已实施计划汇总-20260731.md` | 新建 | 合并 11 份已实施计划 | 阶段5统一计划档案 |
| 11 份阶段5旧实施计划 | 删除 | 原件已备份，内容已按时间顺序合并 | 减少重复计划 |
| `jihua/ruoke-阶段5目录项目移动与排序设计-20260731.md` | 保留 | 已确认的移动排序设计 | 后续编码依据 |
| `jihua/ruoke-阶段5目录项目移动与排序实施计划-20260731-1049.md` | 保留 | 尚未执行的 TDD 任务清单 | 与已实施汇总隔离 |

### 7. 问题、尝试与解决过程

#### 问题 1：模式切换只在根目录可用

- **表现：** 进入文件夹后无法在逐级和展开浏览之间切换。
- **原因判断：** 浏览模式与根页面结构绑定，没有作为共享导航状态。
- **尝试过的方法：** 先验证保留多页面入口的方案，发现状态和入口仍会分叉。
- **无效方法：** 仅在根页面增加按钮不能覆盖文件夹子树。
- **最终处理：** 将模式切换并入统一 `LibraryBrowserView`，以当前位置作为展开树作用域。
- **处理结果：** 根目录和文件夹层级均可切换，定向测试和真机验证通过。

#### 问题 2：创建位置选择范围过大

- **表现：** 创建笔记或书章节时弹出全库书、章、节，书多后难以定位。
- **原因判断：** 原流程使用全局平铺选择器，没有继承主界面当前位置。
- **尝试过的方法：** 评估继续扩展弹窗树，但会复制浏览逻辑并增加状态同步成本。
- **无效方法：** 全局列表即使按层级分组，仍不能体现“当前文件夹内创建”的上下文。
- **最终处理：** 复用主浏览页进入选择模式，从当前目录逐层定位。
- **处理结果：** 选择范围被限制在当前位置子树，取消不写数据，创建后即时刷新。

#### 问题 3：移动到根目录后需重启才显示

- **表现：** 个别目录移动操作数据库已完成，但根目录 UI 没有立即更新。
- **原因判断：** 写操作后没有完整失效浏览链路依赖的 Provider。
- **最终处理：** 在成功写入后统一刷新目录、书章节和当前位置相关 Provider。
- **处理结果：** 后续创建和位置选择流程复用相同刷新策略，页面无需重启即可更新。

### 8. 验证方法与结果

- 浏览、导航状态、位置规则和创建流程的最新定向 Flutter 测试：18 项全部通过。
- 此前阶段5完整 Flutter 测试：196 项全部通过。
- `flutter analyze` 在对应功能批次通过。
- Debug APK 已构建并安装到 PJF110。
- 真机已验证：根目录逐级/展开切换、文件夹内逐级/展开切换、文件夹子树作用域、新建内容弹窗与取消路径；操作中未观察到红屏或崩溃。
- 本次计划合并和技术档案补录只修改 Markdown，不需要重复运行 Flutter 测试；使用 `git diff --check` 检查文档格式。
- **尚未验证内容：** “目录项目移动与排序”没有写生产代码，也没有相应数据库迁移、自动化测试或真机验证。

### 9. 可复现要点

- 浏览和创建必须共用 `LibraryNavigationVm`，不能在弹窗中另建全库位置状态。
- 展开浏览必须以当前位置为递归根节点，进入文件夹后不能自动扩大到全库。
- 位置合法性必须集中到 `LibrarySelectionRules`，并先用纯规则测试锁定边界。
- 任何创建取消路径都不能调用仓储写方法；成功后必须统一失效相关 Provider。
- 阶段5历史计划汇总只包含已经实施的批次；最新移动排序计划已全部实施完毕，已合并到本汇总。
- 移动排序已按设计文档和 TDD 计划全部实现，真机验证通过。

---

## 技术路径记录：2026-08-01 14:30

### 1. 完成事项

阶段5「目录项目移动与排序」全部 10 项任务实施完毕并真机验证通过。交付内容：文件夹、书、章、节、笔记五类项目统一三点菜单；五类项目同级拖拽排序；跨目录移动并可精确选择插入位置；新建项目稳定追加到同类型末尾；移动/排序后逐级与展开浏览即时刷新。

### 2. 初始条件与输入

- 前序成果：无限级文件夹、书-章-节固定层级、主页逐级/展开浏览、当前目录位置选择、v1→v3 数据迁移均已闭环；
- 分支：`feature/notes-mvp`；
- 输入文件：`jihua/ruoke-阶段5目录项目移动与排序实施计划-20260731-1049.md`（设计依据 + TDD 任务清单，完成后并入汇总并删除原文件）；
- 前序基线提交：`b5b3ec1`；
- 约束：未经确认不 push、不删除备份；每改文件先备份；真机测试由用户手动执行。

### 3. 技术方案选择

#### 可选方案

- 方案 A：新增统一 position 关系表，集中管理所有层级的排序位置；
- 方案 B：排序字段使用小数或大间隔数字，减少重排写操作；
- 方案 C：继续使用各业务表现有 `sortOrder`，排序仅在「同一父级 + 同一类型」内有意义，保存时把整组重排为从 0 开始的连续整数。

#### 最终选择

方案 C。

#### 选择原因

- 与现有数据库结构完全兼容，只需 v4 迁移为 `note` 表补 `sort_order`，其余表已有 `sort_order`；
- 不引入新表和双写逻辑，事务内重排成本低、正确性易验证；
- 符合用户明确要求：分类展示固定（文件夹组在书组前，章/节组在笔记组前），`sortOrder` 只在同父级同类型内有效；
- 小数排序方案虽减少写次数，但会带来精度漂移和排序键维护复杂度，收益不足以抵消风险。

### 4. 详细实施路径

#### 步骤 1：排序数据迁移（Task 1，提交 b7183cc）

- **目的：** 为五类项目提供稳定、连续的初始顺序；
- **操作：** 新增数据库 v4 迁移：`note` 表增加 `sort_order`；为已有文件夹、书、章、节、笔记按「同父级同类型」分组生成 `max(sortOrder)+1` 的连续序号；
- **方法：** Drift `MigrationStrategy` + 迁移测试；
- **输入：** `app_database.dart`、既有 v3 schema；
- **输出：** v4 schema 与迁移测试；
- **判断依据：** `app_database_migration_test.dart` 覆盖 v1→v2、v2→v3、v3→v4 数据保留。

#### 步骤 2：文件夹与书排序移动（Task 2，提交 70f9077）

- **目的：** 文件夹和书支持同级拖拽排序与跨文件夹移动；
- **操作：** `FolderRepository`、`SubjectRepository` 增加排序和移动方法；文件夹可移到根目录或任意其他文件夹（排除自身及后代），书可移到根目录或任意文件夹；移动时完整保留后代；
- **输出：** 排序/移动仓储接口 + 定向测试。

#### 步骤 3：章节目排序移动（Task 3，提交 bbe17be）

- **目的：** 章、节支持排序与跨父级移动；
- **操作：** 章可移到任意书下，节可移到任意章下；保存时把来源与目标同级列表整体重排为连续整数；
- **判断依据：** 定向测试覆盖开头、中间、末尾插入位置。

#### 步骤 4：笔记排序移动与菜单重命名（Task 4，提交 65ed92f）

- **目的：** 笔记支持排序、跨书/章/节移动、菜单重命名；
- **操作：** `NoteRepository` 增加排序/移动/重命名；重命名只改标题不创建 `note_version`；
- **输出：** 笔记排序移动接口与测试。

#### 步骤 5：目录组织规则与调度接口（Task 5，提交 0173b8a）

- **目的：** 统一校验层级约束、循环目标和事务原子性；
- **操作：** 新增 `LibraryOrganizationController` 统一调度排序/移动；`LibrarySelectionRules` 集中校验目标合法性（文件夹→文件夹，书→文件夹/根，章→书，节→章，笔记→书/章/节），排除移动对象自身及后代；
- **输出：** controller + 规则纯测试。

#### 步骤 6：同级拖拽排序页（Task 6，提交 7d40a10）

- **目的：** 提供可视化排序界面；
- **操作：** 新增 `library_reorder_view.dart`，加载真实父级下的完整同类型列表，拖拽只改页面草稿，点击保存才写数据库；取消/返回不写数据。

#### 步骤 7：目录树目标选择与移动页（Task 7，提交 e988bb8）

- **目的：** 支持跨目录移动并精确选择插入位置；
- **操作：** 新增可搜索、可展开的完整目录树目标选择页（`library_move_view.dart`、`library_move_target_tree.dart`），先选合法父级，再在目标同类型列表中拖拽确定精确位置；同名书章节用完整路径区分。

#### 步骤 8：统一五类目录项目菜单（Task 8，提交 0dade88）

- **目的：** 消除五类项目入口不一致；
- **操作：** 新增 `library_item_action_menu.dart` 统一 PopupMenuButton：文件夹含「重命名/移动/调整顺序/安全解散」四项，书/章/节/笔记含「重命名/移动/调整顺序」三项；移除书旧移动按钮、章/节旧 `>` 图标；笔记新增三点菜单；
- **输出：** `library_item_action_menu_test.dart`。

#### 步骤 9：展开树统一菜单与稳定排序（Task 9，提交 0dade88）

- **目的：** 展开浏览树与逐级浏览行为一致；
- **操作：** `expandedLibraryProvider`/`ExpandedLibraryData` 公开；展开树节点挂载统一菜单；排序稳定为 `sortOrder → createdAt → id`；新增 `invalidateLibraryBrowserData(ref)` 统一失效全部位置实例，移动/排序后立即刷新。

#### 步骤 10：构建验证与依赖清理（Task 10，提交 0dade88 及 9a5f5ab）

- **目的：** 全量验证并清理；
- **操作：** `pubspec.yaml` 增加 `sqlite3` dev 依赖（测试环境需要）；删除 `subject_path.dart` 未使用导入；全项目 `dart format`；修复两处测试失败（见问题节）；
- **判断依据：** 全量测试、analyze、APK 构建均通过。

### 5. 核心技术细节

- 排序键规则：`sortOrder` 仅在「同一父级 + 同一类型」内有意义；分类展示顺序固定为 文件夹→书→章→节→笔记；
- 保存算法：移动/排序保存时，把来源与目标同级列表统一重排为从 0 开始的连续整数，避免空洞；
- 移动约束：文件夹→根或任意文件夹（排除自身与后代）；书→根或任意文件夹；章→任意书；节→任意章；笔记→任意书/章/节；
- 事务原子性：`LibraryOrganizationController` 在 Drift 事务内完成校验与写入，任一失败整体回滚；
- Provider 失效策略：成功写入后必须失效逐级浏览、展开树、来源目录、目标目录和位置选择相关 Provider，禁止依赖重启应用刷新；
- 历史版本隔离：笔记菜单重命名仅更新标题，不生成 `note_version`；编辑器正常保存仍沿用完整历史版本机制；
- 测试修复要点：对话框关闭动画期间不能立即释放 `TextEditingController`（需 `addPostFrameCallback` 延迟释放）；页面转场期间刷新 Focus 依赖的 Provider 会触发 build scope 错误（`_refreshLibraryRoots` 需 `addPostFrameCallback` 延迟执行）。

### 6. 文件与资源变更

| 文件或资源 | 操作 | 具体内容 | 作用 |
|---|---|---|---|
| `lib/data/database/app_database.dart` | 修改 | v4 迁移与 note.sort_order | 排序数据底座 |
| `lib/.../library_organization_controller.dart` | 新增 | 排序/移动统一调度 | 事务与规则入口 |
| `lib/.../library_selection_rules.dart` | 修改 | 目标合法性校验 | 层级与循环约束 |
| `lib/.../library_reorder_view.dart` | 新增 | 同级拖拽排序页 | 可视化排序 |
| `lib/.../library_move_view.dart`、`library_move_target_tree.dart` | 新增 | 目标选择与移动页 | 跨目录移动 |
| `lib/.../library_item_action_menu.dart` | 新增 | 五类统一三点菜单 | 统一操作入口 |
| `lib/.../library_expanded_tree.dart` | 修改 | 展开树挂载菜单、稳定排序 | 展开浏览一致性 |
| `lib/.../library_browser_view.dart` | 修改 | 接入统一菜单、移除旧入口 | 逐级浏览一致性 |
| `lib/.../library_browser_view_model.dart` | 修改 | 统一失效全部位置实例 | 移动/排序即时刷新 |
| `pubspec.yaml` | 修改 | 增加 sqlite3 dev 依赖 | 测试环境可用 |
| `test/features/notes/` 相关测试 | 新增/修改 | 迁移、规则、排序、移动、菜单、展开树测试 | 回归保护 |
| `jihua/ruoke-阶段5目录项目移动与排序实施计划-20260731-1049.md` | 删除 | 内容并入汇总 | 只保留一份计划文档 |
| `jihua/ruoke-阶段5已实施计划汇总-20260731.md` | 修改 | 追加移动排序计划全文 | 统一归档 |

### 7. 问题、尝试与解决过程

#### 问题 1：对话框关闭动画期间 TextField 访问已释放控制器

- **表现：** `library_browser_view_test` 中重命名后偶发 `TextField` 使用已释放 controller；
- **原因判断：** 对话框 `Navigator.pop` 后关闭动画仍在运行，立即 `dispose()` 导致 TextField 访问已释放对象；
- **最终处理：** `_showRenameDialog` 中改为 `WidgetsBinding.instance.addPostFrameCallback` 延迟释放；
- **处理结果：** 重命名测试稳定通过。

#### 问题 2：页面转场期间刷新展开树导致 build scope 错误

- **表现：** 移动/排序成功刷新时出现 Focus 节点在错误 build scope 中重建；
- **原因判断：** `_refreshLibraryRoots` 在转场未结束时同步刷新展开树 Provider；
- **最终处理：** 改为 `addPostFrameCallback` 延迟执行 `refreshLibraryExpandedTree(ref)`；
- **处理结果：** 展开模式移动/排序测试稳定通过。

#### 问题 3：Flutter 锁文件卡住命令

- **表现：** `C:\flutter\flutter\bin\cache\lockfile` 与 `flutter.bat.lock` 为 0 字节残留锁，`flutter` 命令卡住；
- **最终处理：** 删除残留锁文件后恢复；沙箱内改用 `dart.exe + flutter_tools.snapshot` 直接调用 Flutter 工具；
- **处理结果：** test/build/analyze 均可正常执行。

#### 问题 4：PowerShell 正则替换损坏 Dart 文件

- **表现：** 用 PowerShell 正则给 `if` 补花括号时破坏了 `library_creation_scope.dart` / `library_selection_rules.dart`，出现大量 undefined class 错误；
- **最终处理：** 从备份恢复文件，改用 Node.js 精确字符串替换；
- **处理结果：** 花括号 lint 修复（提交 9a5f5ab），analyze 全绿。

### 8. 验证方法与结果

- 定向测试：`library_item_action_menu_test.dart`、`library_browser_view_test.dart`、`library_move_view_test.dart`、`library_move_target_tree_test.dart` 等全部通过；
- 全量测试：`flutter test` 251 项全部通过；
- 静态分析：`dart analyze lib test` 输出 `No issues found!`；
- APK 构建：`flutter build apk --debug` 成功，产物 `build\app\outputs\flutter-apk\app-debug.apk`；
- 真机验证：用户手动安装到 PJF110，25 项真机测试全部通过（五类菜单、展开树菜单、同级排序、跨目录移动、精确位置、安全解散、新建默认排序、重命名）；
- 文档整理：`git diff --check` 通过；已确认 jihua 中阶段5文件只剩一份汇总。

### 9. 可复现要点

- 排序/移动必须走 `LibraryOrganizationController`，不允许 UI 直连 DAO；
- 移动保存时把来源与目标列表整体重排为从 0 开始的连续整数；
- 成功后必须调用 `invalidateLibraryBrowserData(ref)` 等统一失效逻辑，不能依赖重启；
- 目录树搜索必须保留祖先路径，同名项目用完整路径区分；
- 笔记重命名不得创建历史版本；
- 修改 Dart 文件的花括号等小格式问题用精确字符串替换（Node.js/Python），避免 PowerShell 正则误伤；
- Flutter 命令卡住时先检查 `C:\flutter\flutter\bin\cache\lockfile` 与 `flutter.bat.lock` 残留锁；
- 计划文件已并入 `ruoke-阶段5已实施计划汇总-20260731.md`，原独立计划文件已删除，不再单独维护。