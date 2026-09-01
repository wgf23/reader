<!-- wf-meta: req=REQ-003 | phase=architecture | agent=architect | date=2025-08-31 | gate=passed -->
# REQ-003 · 架构决策记录（ADR：翻译异步方案 / 选区获取 / 缓存仓储分层 / HTTP 客户端）

## 决策
在线翻译采用 **core 内同步 HTTP（ureq + rustls）+ FRB 桥接层线程池执行**，不引入 tokio 运行时、
Provider trait 保持全同步（与 docs/04 §7 签名一致）；阅读器选中文本采用 **滚动模式 Flutter 原生
`SelectionArea` + 分页模式最小 JS 选区回传**（两模式都做）；翻译缓存落库采用 **domain 契约 trait
（落位共享内核 `core/src/types.rs`）+ store 实现 + api 装配注入**；HTTP 客户端选 **ureq（blocking，
rustls 后端，禁 native-tls/OpenSSL）**。

## 两个待确认点结论（01-req §2 依赖 D3 / §5 风险 5-6）
1. **异步方案**：采"同步 HTTP + 桥接层线程池"（决策点 1，方案 A1）——FRB async 桥接函数在 FRB
   内部线程池执行，UI 不阻塞，core 不拥有/不初始化运行时，全部领域代码保持同步。
2. **选中文本现状**：`reflow_engine.dart` 的 `selectText` 仍是 TODO、`paged_web_view.dart` 无任何
   选区回调 → 01-req 所称"D3 既有选中能力"**实际不存在**。处置：滚动模式用 `SelectionArea` 兜底
   （01-req 已授权），分页模式补"最小 JS 选区回传"（决策点 2，方案 A1），完整选区/上下文菜单机制
   仍归后续 REQ（REQ-001 演进 / 笔记 REQ）。

---

## 决策点 1：在线翻译的异步方案

### 备选
- **A1（选）：core 内同步 HTTP + 桥接层线程池执行**
  领域/Provider 全同步：`TranslationProvider::translate(&self, text, from, to) -> Result<Translation>`
  （与 docs/04 §7 一致）；api.rs 新增桥接函数声明为 FRB async 函数（`pub async fn translate(...)`，
  函数体仍是同步代码：阻塞 ureq + rusqlite），由 FRB 2.13 在**自身后台线程池**执行，Dart 侧拿到
  `Future`，UI 线程不阻塞；core 不初始化、不拥有任何运行时。
  优点：零 async 依赖（无 async_trait/无 Runtime 生命周期管理）、Provider 无 Send/Sync 升级约束、
  既有全部测试同步直调不改、CRAP/DDD-lint 对同步函数解析零适配；FRB 2.13 依赖树**已含 tokio**
  （Cargo.lock：`flutter_rust_bridge 2.13.0` → `tokio`，FRB 内部用于异步执行）——FRB async 支持
  开箱即用，无需我们引入任何东西。缺点：翻译请求占用一个池线程（低并发场景无影响）；`Mutex` 在
  请求期间被持有（单用户桌面无并发压力，且 `dict_lookup` 与 `translate` 拆为两个单例互不阻塞）。
- **A2：引入 tokio 运行时 + Provider trait 改 async**
  核心层启用 tokio（`#[tokio::main]` / `OnceLock<Runtime>`），`TranslationProvider::translate` 改
  `async fn`（需 `async_trait` 或 RPITIT + 所有 Provider 满足 `Send + Sync`），api 全 async 链路。
  优点：并发模型"正统"、长操作不占线程。缺点：新增宏依赖与运行时生命周期管理；trait 对象安全/
  Send/Sync 约束全面收紧（DeepL 客户端、注册表 Vec<Box<dyn …>> 都要升级）；core 全同步测试体系
  （cargo test 直调、语料/集成测试）需处处 `block_on`；CRAP/DDD-lint 对 async fn 的 syn 解析需
  适配；本 REQ 并发需求几乎为零（单用户、UI 触发、短操作），收益不抵复杂度。docs/02 §8 也把
  tokio 列为"P0 按需启用"（Cargo.toml 注释），本期不启用。
- **A3：同步桥接 + Dart 侧 isolate（compute）承载**
  桥接保持 sync，Dart 用 `compute`/`Isolate.run` 执行。缺点：FRB 生成类型与 `RustOpaque`/指针不可
  跨 isolate 传递（需重写 FFI 层或序列化绕行），比 FRB async 复杂得多；与 docs/03 §5"Rust 工作
  线程池"约定不符。

### 选择与理由
选 **A1**。与 docs/03 §5（"Rust 工作线程池（tokio 或 rayon + std threads）"——FRB 内部池即满足
"线程池执行"语义）、docs/04 §7（Provider 签名为同步 `Result`）、docs/02 §8（tokio 按需启用）、
01-req §5 风险 6（"同步方案下长网络请求阻塞 Rust 线程，需明确线程模型"——FRB 池线程即为该模型）
全部一致。A2 的复杂度对本 REQ 无收益；A3 与 FRB 2.x 用法冲突。

### 影响
- api.rs 新函数为 `pub async fn`（FRB 2.13 支持 async + `Result<_, String>` + `Option<T>` 返回，
  生成物在 T-006 再生成）；既有同步桥接函数零改动（FRB 支持 sync/async 混用）。
- Provider trait 保持同步（docs/04 §7 不变）；01-req §3 的"`async fn translate`"注释为过时占位，
  以 docs/04 §7 为准（冲突处置见 02-plan.md）。
- Cargo.toml 仅新增 ureq（+ serde_json 已有）；tokio 以 FRB 传递依赖存在，不显式声明。

---

## 决策点 2：阅读器"选中文本"如何拿到（翻译入口输入）

### 现状（已核实）
滚动模式：`reader_page.dart` 用 `Text` + `SingleChildScrollView`，**无任何选区能力**；分页模式：
`paged_web_view.dart` 的 `paginationJs` 只有分页逻辑，**无选区监听**；`reflow_engine.dart`
`selectText` 为 TODO。即 01-req §4 D3 假设的"既有选中能力"不存在。

### 备选
- **A1（选）：滚动模式 `SelectionArea` + 分页模式最小 JS 选区回传（两模式都做）**
  滚动模式：正文 `Text` 外包 `SelectionArea(onSelectionChanged: …)`，选中即回调纯文本到
  `_selectedText` 状态（Flutter 原生，零依赖，01-req §4 已明确授权"用 Flutter 原生 SelectionArea
  兜底"）；分页模式：`paginationJs` 增加 `selectionchange` 监听（约 20 行 JS），
  `window.getSelection().toString()` 非空时经既有 `flutter_inappwebview.callHandler('selectedText',
  …)` 通道回传（与现有 `readerFlutter` 进度回调同款通道），`PagedWebView` 增加 `onSelectedText`
  回调，`reader_page` 统一走同一 `_onSelectedText` 路径。
  优点：US-15 两条验收全部成立且可测（widget 测试经 fake paged builder 注入选中回调）；分页回传
  成本极低且复用既有 callHandler 通道。缺点：分页 JS 选区回传属于"最小选区机制"，与 01-req §4
  "本 REQ 不实现选区机制本身"字面冲突——以处置说明消解（见下）。
- **A2：仅滚动模式 `SelectionArea`，分页模式暂缓**
  优点：工作量最小。缺点：US-15 第二句（"分页模式选中回调产生 → 同一翻译入口可用"）验收无法
  成立（分页模式没有"选中回调产生"的路径，测试只能挂在假回调上，真机不可用），**不满足验收**。
- **A3：两模式选区机制全部归前置 REQ（REQ-001 补选区）**
  跨 REQ 依赖会阻塞本 REQ 验收排期；REQ-001 已交付且其选区能力实际为 TODO，不能作为已就绪前提。

### 选择与理由
选 **A1**。处置说明（消解与 01-req 字面冲突）：滚动模式选区本就由 01-req 授权纳入本 REQ UI；
分页模式只补"选区文本回传"（~20 行 JS + 一个 Dart 回调），**不实现**上下文菜单、锚定高亮等完整
选区机制（那些归 REQ-001 演进/笔记 REQ）；`reflow_engine.selectText` TODO 保留不动。翻译/查词
入口拿到的是**选中纯文本**（String），不新增 `TextSelection` 结构（决策点见 02-design §7），
与 docs/03 §4 `translate(text, …)` 纯文本签名一致。

### 影响
- `app/lib/engines/paged_web_view.dart`：`paginationJs` 增选区监听；组件增 `onSelectedText` 回调
  （`onCallBackHandler` 接 `selectedText`）；既有 `onProgress` 行为零改动。
- `app/lib/pages/reader_page.dart`：滚动模式 `SelectionArea`；新增选中工具条（翻译/查词/取消）；
  `ReaderPage` 增可选 `translateBackend` 参数（null 时入口隐藏，既有测试零回归）。
- widget 测试可测性：`SelectionArea.onSelectionChanged` 可直接在测试中触发；分页模式经
  `PagedViewBuilder` fake 注入选中回调（真 JS 走 FFI 端到端/真机验证）。

---

## 决策点 3：翻译缓存落库的分层方案（ddd-rules 合规）

### 备选
- **B1（选）：domain 契约 trait（落位共享内核 `core/src/types.rs`）+ store 实现 + api 装配注入**
  在 `core/src/types.rs`（共享内核，ddd-rules 的 domain 路径已覆盖）定义跨层契约：
  `TranslationCacheRepository`（get/put/clear/incr_hit/count）与 `ProviderConfig`
  （default_provider/provider_key/set_provider_key/set_default_provider），连同其载荷类型
  （`Lang`/`Translation`/`CacheKey`/`CacheEntry`，serde 可序列化，供 store 实现时命名）；
  `core/src/store/translation.rs`（infrastructure）实现这两个 trait（settings 表 + translation_cache
  表）；api.rs（interface）在 `library_open` 装配注入到 `TranslationService`。
  优点：依赖方向正确（infrastructure → 契约，不触 domain 业务）；ddd-lint **违规=0** 且
  ddd-rules.toml **零改动**（infrastructure 的 `forbid_internal` 只禁 `crate::dict` 等业务模块、
  不禁 `crate::types`）；契约可单测（内存 Mock 实现注入，服务层测试不碰 SQLite）；未来可换
  内存/LRU 缓存实现。
  关键论证（为什么契约落 `types.rs` 而非 01-req 字面说的"dict 模块内"）：ddd-lint 对
  `use crate::xxx` 归一化首段机械比对，`core/src/store/**`（infrastructure）的
  `forbid_internal` **含 `crate::dict`**（rules/ddd-rules.toml 已核实）——若 trait 定义在
  `core/src/dict`，store 实现必然 `use crate::dict::TranslationCacheRepository` → 闸门3 违规=0
  无法达成；规则表按 docs/07 §6"评审后冻结，勿单方面修改"。契约及其载荷类型移入共享内核
  （docs/04 §1"共享内核定义在一处"原则）后，store 只 `use crate::types`，合规。
- **B2：TranslationService 直接依赖 store（具体仓储类）**
  服务内 `use crate::store::TranslationRepo` 并持有 → 违反 ddd-rules domain `forbid_internal`
  （含 `crate::store`），ddd-lint 直接抓取；翻译服务与 SQLite 强耦合（单测需真库临时文件、
  无法注入内存 Mock、US-9/10/12 的 mock 计数与参数断言被迫降级为集成测试）；缓存实现不可替换
  （未来 LRU/内存缓存/容量上限策略（01-req §5 风险3）无注入点）。**拒绝**。
- **B3：修改 ddd-rules.toml 允许 store → dict（infra 实现 domain 接口）**
  DDD 语义上"infrastructure 实现 domain 接口"本属标准方向，但规则表已冻结（docs/07 §6），且
  需走规则评审链、影响全局（不止本 REQ）。作为远期选项记录，本期不采用——B1 以更小侵入达成
  同一目标。

### 选择与理由
选 **B1**。在"规则表冻结 + 闸门3 违规=0 + 契约归 domain"三个硬约束下，唯一同时满足的方案；
契约落共享内核有 docs/04 §1 依据，属对 01-req 措辞的机械修正（已列冲突处置）。

### 影响
- `core/src/types.rs` 新增跨层契约与载荷类型（serde 派生）；`core/src/dict` 与
  `core/src/store/translation.rs` 均只依赖 `crate::types`/`crate::error`。
- `TranslationService::new(cache: Box<dyn TranslationCacheRepository + Send>, config:
  Box<dyn ProviderConfig + Send>, providers: Vec<Box<dyn TranslationProvider>>, default: String)`；
  api.rs 装配时对两个 trait 各构造一个 `TranslationRepo`（同一 `library.db` 的两个连接，WAL +
  busy_timeout，SQLite 多连接标准用法；迁移共享且幂等——见 02-design §4）。

---

## 决策点 4：HTTP 客户端选型（rustls 约束）

### 备选
- **C1（选）：ureq（blocking，rustls 后端，禁 native-tls）**
  纯同步 API、无运行时、依赖树轻（无 hyper/tower）；rustls 纯 Rust，Android NDK/WSL 交叉编译
  零 OpenSSL 依赖（01-req §5 风险5）；2.x 默认 rustls（不开 native-tls feature）。
  `ureq = { version = "2", default-features = false, features = ["json", "tls"] }`（开发阶段按
  实际解析结果 pin 小版本并冻结）。缺点：功能集小于 reqwest（重定向/代理等场景弱）——本 REQ 仅
  DeepL 一个 POST 端点，无此需求。
- **C2：reqwest blocking + rustls**
  功能全（重定向/超时/代理），blocking 内部自带 tokio 运行时；但依赖树明显更重（hyper/tower/
  http 全家），编译时长与体积增加（移动端每 ABI <25MB，docs/02 §7），与"core 不显式启用
  tokio"的同步约定张力大；超出本 REQ 单端点的需求面。记录为后续（多 Provider/代理需求出现时
  再评估）。
- **C3：HTTP 请求放 Dart 侧（http 包），Rust 只做编排 + 缓存**
  01-req §5 风险5 的备选。缺点：Provider 接口归属被破坏（docs/04 §7 `TranslationProvider` 在
  core）；US-9/10/12 要求的 **mock 计数与请求参数断言必须在 Rust Provider trait 层**（测试注入
  CountingProvider/EchoProvider 依赖该层）；"失败不写缓存"的原子性（US-12）跨进程无法保证；
  隐私断言"只传 text/from/to"（US-13）失去测试锚点。**拒绝**。

### 选择与理由
选 **C1**。与 01-req §5 风险5 的约束（"禁 native-tls/OpenSSL 以免 Android 交叉编译/WSL 构建
受阻"、"或备选 HTTP 放 Dart 侧——二选一并出 ADR"）一致；C3 被拒绝的理由如上（测试与隐私
断言锚点全在 Rust Provider 层）。

### 影响
- `core/Cargo.toml` 新增 ureq（rustls）；`scripts/build-android.sh` 现有构建链回归验证
  （T-009 回归面）；Provider 层与缓存层零网络抽象改动（网络仅封装在 `DeepLProvider` 内部）。

---

## 关联裁定（次要决策，记录供 02-design/02-plan 引用）
1. **Provider 注册表**：默认注册 `DeepLProvider`（真实，Free 层 50 万字符/月，REST POST
   /v2/translate，auth header）与 `EchoProvider`（mock/无 key 演示回退）；Google/有道仅留
   trait 可插拔位，本期不注册（01-req §4 风险8"一个真实 + mock"）。
2. **default provider 语义**：默认 `deepl`；未配置 key → `NotConfigured`（满足 US-12）；
   经 `translate_set_config("echo", "")` 切到 echo 即无 key 演示（满足"mock 可演示"）。
3. **settings 表随 v3 一并建**（docs/04 §5 已有 DDL；Provider key 最小配置通道需要）；
   `vocabulary` 表不建（TRANS-04 排除，不占迁移号）。
4. **dict_install 返回类型**：US-7 要求返回 `DictInfo`（词库名/词条数/路径），docs/03 §4 原为
   `Result<()>` → 本 REQ 采用 US-7（需求验收优先），docs/03 §4 契约在 T-006 同步更新
   （另补 `dict_remove`——docs/03 §4 原无此函数）。
5. **大词库 .dz 内存风险处置**（01-req §5 风险2）：安装期用 flate2 `GzDecoder` **流式解压**
   `.dict.dz` 落盘为 `.dict`（一次性磁盘成本，无内存峰值），查询期对 `.dict` 随机读；本期以
   langdao 级词库为准，100MB+ 词库的 mmap/按区段解压方案留后续 REQ（TRANS-03）记录。
6. **Traits 载荷类型归位**：`Lang`/`Translation`/`CacheKey`/`CacheEntry` 随契约入 `types.rs`
   （store 实现需命名）；`DictEntry`/`DictInfo`（仅 domain+interface 消费）留 `core/src/dict`。

## 影响汇总
- **接口**：api.rs 新增 7 个 async 桥接函数 + 3 个 DTO（DictInfoView/DictEntryView/TranslationView）；
  docs/03 §4 dict/translate 契约需同步（返回类型、dict_remove、async 说明）。
- **数据模型**：store v3 迁移新增 `translation_cache` + `settings` 两表（DDL 见 02-design §3）。
- **依赖**：Cargo.toml 新增 ureq(rustls)；FRB 2.13 async 支持复用（无需新依赖）。
- **时序/线程**：translate 在 FRB 池线程执行，UI 不阻塞；DICT/TRANSLATION 双单例互不锁竞争。
- **回归面**：既有 api 同步函数零行为变化；store v1/v2 迁移路径不动（v3 追加）；
  reader_page 既有测试零回归（translateBackend 可选参数）；paged_web_view 既有行为不动（仅追加
  选区回传）。

## 闸门2 自评（ADR 部分）
- [x] 备选 ≥2 且给出理由：4 个决策点各含 ≥2 备选（A1/A2/A3、B1/B2/B3、C1/C2/C3、SelectionArea/
      JS 回传/暂缓）并给出选择理由与拒绝论证（B2 违反 ddd-rules、C3 破坏测试/隐私锚点）。
- [x] 与既有约定一致：docs/03 §5 线程模型、docs/04 §7 Provider 同步签名、docs/04 §1 共享内核、
      docs/04 §5 表 DDL、docs/02 §8 依赖与 §5 目录（dicts/）、ddd-rules 冻结（零改动）——
      两处与 01-req 措辞的偏差（trait 落位 types.rs、分页最小选区回传）均已列处置说明。
