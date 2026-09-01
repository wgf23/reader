<!-- wf-meta: req=REQ-003 | phase=requirements | agent=req-analyst | date=2025-08-31 | gate=passed -->
# REQ-003 · 翻译与词典（TRANS-01 离线查词 + TRANS-02 在线翻译） —— 需求分析

## 1. 背景与目标
Epic D（docs/01 §3）的 TRANS-01/02 为 **P0**（docs/01 §2："能翻译"是 MVP 四件套之一），但核心层
`core/src/dict/mod.rs` 仍是空 stub：`TranslationProvider` trait 只有 `name()` 占位、`TranslationService`
无任何实现；`docs/04 §5` 规划的 `translation_cache` 表与 `docs/03 §4` 的 dict/translate 桥接面
（`dict_install`/`dict_lookup`/`translate`/`vocabulary_*`）均未落地。REQ-003 交付 **TRANS-01（离线
StarDict 查词）与 TRANS-02（在线 Provider 选句翻译 + 缓存）** 的核心链路：安装词库后长按/双击查词
完全离线可用；选中文本翻译可插拔 Provider、结果按（原文, 语言对, Provider）缓存、命中缓存不联网、
失败不崩溃；翻译缓存仅存用户选中文本且可一键清空（docs/02 §10、docs/04 领域规则 4）。成功标准一句话：
**任意已装 StarDict 词库可离线查词返回结构化解义；选中文本经可插拔 Provider 翻译并缓存复用，全程
无 key/断网/未收录词均给明确可重试错误且不 panic**。

**边界划界（本 REQ 明确）**：必做 TRANS-01 + TRANS-02；**不在本 REQ 范围**（列为后续 REQ）：
TRANS-03 进阶管理（词库信息预览、Provider 启用/停用与默认 Provider 选择、离线优先策略开关）、
TRANS-04 生词本（`vocabulary` 表本期不建）、TRANS-05 对照阅读。本 REQ 仅含 TRANS-01 验收自带的
**词库安装/移除最小能力**与 TRANS-02 运行所必需的 **Provider key 最小配置通道**（见 §2 US-6/§4）。

## 2. 用户故事与验收标准（Given/When/Then，必须可测）

### 故事 1：TRANS-01 离线查词 —— 作为陈老师，我想要长按/双击选中单词即可看到释义卡片，以便不打断阅读
- **US-1 已知词返回结构化词条（词/音标/词性/释义）**
  - Given 已通过 `dict_install` 安装一份 StarDict 词库（`.ifo`/`.idx`/`.dict`，`sametypesequence` 含
    释义类型，如自造语料 `'tgm'`；或朗道 langdao-ec）
    When 调用 `dict_lookup("apple")`
    Then 返回 `Ok(Some(DictEntry))`，且：`word == "apple"`；`phonetic` 与 `pos` 在词库提供时非空、
    未提供时允许 `None`；`definition` **非空**且含自造语料/朗道语料中已知释义子串（断言精确值）。
  - Given 自造词库 `sametypesequence = 'tgm'`（音标+HTML 释义+纯文本释义混合）When 查该词库词条
    Then 各释义按类型码正确解析归位（`t`→phonetic、`g`/`m`→definition），无字段错位。
- **US-2 未收录词返回"未找到"**
  - Given 已装词库但不含 "zzzqqq"（语料中确认不存在）When `dict_lookup("zzzqqq")`
    Then 返回 `Ok(None)`（UI 显示"未找到"），**不 panic、不产生网络调用**（见 US-4 计数断言）。
- **US-3 无词库时给出明确提示**
  - Given 未安装任何词库（空 dicts 目录）When `dict_lookup("apple")`
    Then 返回 `Err`，错误消息含"词库"与"未安装/导入"语义（如"未安装词库，请先在设置中导入"），不 panic。
- **US-4 完全离线可查（零网络）**
  - Given 词库已安装、且测试注入必然失败的 Provider（`FailingProvider`，调用即 `Err(Network)`）并断言其调用计数为 0
    When `dict_lookup` 任意词
    Then 结果与"Provider 可正常工作时"完全一致（离线不降级）；测试断言 `FailingProvider` **调用计数 == 0**
    （结构性约束：dict 模块不新增任何 HTTP/网络依赖，见 §3 依赖项）。
  - Given 测试环境模拟断网（无网络可用或网络层 mock 全部失败）When 查词 Then 结果不变。
- **US-5 大小写归一与多词库顺序**
  - Given 词库索引存 "Apple" When `dict_lookup("apple")` Then 命中（大小写不敏感，首字母大小写归一）。
  - Given 按序安装词库 A、B（A 含该词）When `dict_lookup(word)` Then 返回 A 的词条
    （多词库按安装顺序取首个命中；A、B 均含时只返回 A 的结果，不合并——合并策略为架构决策点）。
- **US-6 .dz 压缩词库与坏词库**
  - Given 安装 `.dict.dz`（gzip 压缩整文件）词库 When 查词 Then 正常返回释义（`.dz` 解压路径被覆盖）。
  - Given 损坏词库（`.idx` 截断/偏移越界/`.ifo` 缺 `wordcount`）When `dict_install` 或 `dict_lookup`
    Then 返回 `Err`（结构化错误，消息含原因分类），**不 panic**，且已装词库列表不受影响。
- **US-7 词库安装/移除最小闭环（TRANS-01 验收"可安装/移除词库"）**
  - Given 合法词库文件路径 When `dict_install(path)` Then 返回 `DictInfo`（词库名/词条数/路径）；
    `dict_list()` 含该词库；重复安装同一词库返回已存在的幂等结果（不重复注册）。
  - Given 已装词库 When `dict_remove(dict_id)` Then `dict_list()` 不再含该词库，且其文件/注册信息被移除；
    移除后查词回落 US-3 行为。
- **US-8 查词性能预算（可测基准，非 CI 硬断言）**
  - Given 词库索引已加载（首次加载不计入）When 连续 `dict_lookup` 100 次
    Then 单次平均 **< 50ms**（docs/02 §6 无既有预算，此为本次新增；CI 用宽松上限 ≤ 200ms 防回归，
    以基准/计时测试记录为准）。

### 故事 2：TRANS-02 选句翻译 —— 作为陈老师，我想要选中句子/段落翻译，以便理解原文
- **US-9 调用 Provider 返回译文**
  - Given 已配置 Provider（测试注入 `EchoProvider`：固定返回 `Translation { text: "译文:"+原文, provider: "echo" }`）
    When `translate("Hello world", Lang::En, Lang::Zh)`
    Then 返回 `Ok(Translation)`，`text` 与 mock 返回一致、`provider == "echo"`；
    且 mock 收到的请求参数**只含 `text`/`from`/`to`**（mock 记录参数并断言不含书路径/元数据/其他信息，见隐私 US-13）。
  - Given 选中文本含跨行换行/多余空白 When 翻译 Then Provider 收到的 `text` 为**空白规范化后**的整句
    （连续空白折叠为单空格并 trim，对应 TRANS-02"跨行自动合并"）。
- **US-10 同文+同语言对+同 Provider 命中缓存（不重复请求，mock 计数验证）**
  - Given `CountingProvider`（每次调用计数 +1）When 对同一 `(text="Hello world", en→zh)` 连续调用 `translate` 2 次
    Then Provider **调用计数 == 1**（第二次命中缓存）；两次返回的 `Translation.text` 一致；
    第二次响应耗时 **< 10ms**（缓存命中查询预算，见 US-14）。
- **US-11 缓存键区分（语言对/Provider 任一不同即 Miss）**
  - Given 缓存已有 `(text, en→zh, providerA)` 记录
    When `translate(text, en→zh, providerB)` Then 调用 Provider B（计数 +1），不命中；
    When `translate(text, zh→en, providerA)` Then 调用 Provider A（计数 +1），不命中。
- **US-12 失败不崩溃（无 key / 网络失败 / Provider 异常）**
  - Given Provider 未配置（未设置任何 key，`translate` 之前未调用配置接口）
    When `translate` Then 返回 `Err`，错误消息含"未配置/API Key"语义；不 panic。
  - Given `FailingProvider`（返回 `Err(Network)`）When `translate` Then 返回 `Err`，错误消息含
    "网络/失败"语义且**携带原文本**（`TranslationError` 结构或错误字符串含原文，供 UI 重试不丢原文）；
    不 panic。重复调用失败**不写入缓存**（`translation_cache` 行数不变）。
  - Given 失败后再配置可用的 Provider When 重试同一文本 Then 正常返回（可重试闭环）。
- **US-13 隐私：缓存只存选中文本 + 一键清空**
  - Given 产生 N 条翻译缓存后 When `translate_cache_clear()`
    Then 缓存表行数为 0；再次翻译同文本重新调用 Provider（计数 +1），证明清空生效。
  - Given 任意缓存写入 When 断言 `translation_cache` 表结构 Then 仅含 `docs/04 §5` 规定的列
    （source_text/from_lang/to_lang/provider/result/created_at/hit_count），**无书 ID、路径、设备信息等
    额外个人数据列**；`source_text` 即用户选中文本（Provider 收到的 `text` 与缓存 `source_text` 一致）。
  - Given 命中缓存返回 When UI 译文卡片标注"缓存"来源（见 US-15，widget 可断言缓存标记）。
- **US-14 性能预算（可测基准，非 CI 硬断言）**
  - Given 缓存含 ≥1000 条记录（含目标键）When 命中查询
    Then 单次 **< 10ms**（唯一索引单行查询）；CI 宽松上限 ≤ 100ms 防回归，以计时测试记录为准。

### 故事 3：桥接与 UI —— 作为所有用户，我想要在阅读器里直接触发查词/翻译并看到浮层结果
- **US-15 选中文本 → "翻译"入口 → 译文浮层（widget 测试）**
  - Given 阅读器（滚动模式）存在选中文本（测试注入选中状态 + fake 后端）When 选中工具条出现
    Then 工具条含"翻译"入口；点击后调用 `translate` 桥接，页面出现译文浮层并展示 mock 返回的译文文案；
    浮层含 Provider 名与"缓存/在线"标记；加载中显示 loading、失败显示错误文案与"重试"按钮（可断言）。
  - Given 阅读器（分页模式，WebView）选中文本 When 选中回调产生 Then 同一"翻译"入口可用
    （选区回调机制为既有选中能力，见 §4 依赖 D3；本 REQ 不实现选区机制本身，仅挂接入口）。
- **US-16 查词浮层（widget 测试）**
  - Given 阅读器选中单个词 When 触发查词（长按/双击/快捷键，按 TRNS-01 入口）
    Then 出现词典卡片浮层：词条名/音标/词性/释义（mock 后端固定返回 `DictEntry`，断言各字段渲染）；
    未收录词显示"未找到"、无词库显示导入引导文案（对齐 US-2/US-3 错误映射）。
- **US-17 桥接契约与配置最小通道**
  - Given `api.rs` 编译通过 When 检查桥接函数
    Then `dict_install`/`dict_remove`/`dict_list`/`dict_lookup`/`translate`/`translate_cache_clear`/
    `translate_set_config`（或等价 settings 通道）全部存在且签名与 docs/03 §4 对齐
    （`Result<…, String>` 错误映射，含 US-3/US-12 错误文案）。
  - Given 未配置任何 key 的设置页（TRANS-03 未实现）When 经最小配置通道写入 key
    Then `translate` 可用该 key（配置通道 = 桥接函数 + settings 键，设置页完整 UI 不在本 REQ，见 §4 划界）。

## 3. 影响面分析（必须非空）
- **core/src/dict/mod.rs（domain 层，空 stub → 实现）**：StarDict 解析（`.ifo` 元数据/`wordcount`、
  `.idx` 词条索引（word\0 + 偏移/长度 4B BE，二分查找或内存哈希索引）、`sametypesequence` 释义类型
  解析、`.dict` 与 `.dict.dz`（gzip 整文件流，flate2 已有））；`DictEntry`/`Translation`/`Lang` 类型
  （定义位置：`core/src/types.rs` 共享内核 或 dict 内，架构阶段定）；`TranslationProvider` trait 完整化
  （`async fn translate(&self, text, from, to) -> Result<Translation>`，docs/04 §7）；`TranslationService`
  实现 `lookup`/`translate`/`install_dict`/`list_dicts`/`remove_dict`/`clear_cache` + Provider 注册表
  （默认 DeepL/Google/有道注册 + `EchoProvider` mock 回退）。
- **分层约束与缓存落库方案（架构决策点，本 REQ 提出约束）**：ddd-rules.toml 已声明 `core/src/dict`
  属 **domain 层**，禁止 `crate::store|api|library`（闸门3 DDD 违规=0）→ `TranslationService` **不得
  直接持有 SQLite**；约束方案：dict 模块内定义 `TranslationCacheRepository` trait（get/put/clear/incr_hit，
  trait 归 domain 层），`core/src/store`（infrastructure 层）实现该 trait，由装配层（api.rs 单例或
  library 装配）注入 —— 架构阶段落定具体注入方式与 Provider key 的 `SettingsRepository` 等价通道。
- **store（infrastructure 层）**：迁移 `user_version` **v2 → v3** 新增 `translation_cache` 表
  （DDL 按 docs/04 §5：`source_text/from_lang/to_lang/provider/result/created_at/hit_count` +
  `idx_tcache` 唯一索引 (source_text, from_lang, to_lang, provider)）；实现 `TranslationCacheRepository`
  （get/put/clear + hit_count 递增）；Provider key 存储（settings 表本期是否随 v3 一并建，架构定）。
  **vocabulary 表本期不建**（TRANS-04 排除，不占用迁移号）；既有 v1/v2 库升级 v3 的迁移测试必须覆盖
  （存量 books/reading_progress 数据不丢失）。
- **core/src/api.rs（interface 层）+ frb_generated 再生成**：新增 `dict_install`/`dict_remove`/
  `dict_list`/`dict_lookup`/`translate`/`translate_cache_clear`/`translate_set_config` 桥接函数
  （命名与 docs/03 §4 对齐；`translate` 为 async 时需 FRB 异步支持）；全局 `SERVICE` 单例装配扩展
  （Store → 缓存仓储 → TranslationService 注入，或新增独立单例）；`Error → String` 映射覆盖新错误
  变体（见下）。改动需同步 docs/03 §4 契约说明。
- **core/src/error.rs**：建议新增 `Error::NotConfigured`（Provider 未配置）与 `Error::Network`
  （网络失败）变体，使 UI 可区分"未配置 key / 网络失败 / 词库缺失 / 未收录"并给对应文案；
  是否新增由架构阶段决策，决策后同步 api.rs 错误映射与测试断言（对齐 REQ-002 的 error 处理先例）。
- **core/Cargo.toml（依赖）**：StarDict 解析按 docs/02 §8"stardict 类 crate 若缺失则自写（~200 行）"
  —— 实现前核实 crate 生态，缺则自写（纯解析无新依赖）；**新增 HTTP 客户端**（在线 Provider：
  `reqwest`+`rustls` 或 `ureq`，**禁 native-tls/OpenSSL** 以免 Android 交叉编译/WSL 构建受阻，见 §5 风险5）；
  flate2（.dz）已有、serde_json（result JSON）已有。
- **app（Flutter）**：`services/` 新增 `TranslateService`（薄封装转发 FFI，对齐 docs/03 §4，属
  application 层，禁直接 import 桥接生成物）；`reader_page.dart` 选中工具条新增"翻译"入口 + 译文/词典
  浮层组件（`widgets/`，含 loading/错误/重试/缓存标记态）；`settings_page.dart` 新增最小"词典与翻译"
  区块（词库导入/列表/移除、Provider key 输入、清空翻译缓存按钮 —— TRANS-01 验收"可安装/移除词库
  （设置页）"与隐私验收必需）；TRANS-03 进阶管理 UI 不在本 REQ。
- **types.rs / notes（共享类型）**：`TextSelection`（notes 与 dict 共用）与 `Lang` 若未定义则补齐
  （docs/04 §1 共享内核一处定义）；notes 模块不新增行为（翻译入口与高亮/批注共用选中文本，功能正交）。
- **ddd-rules.toml**：规则表**无需修改**（dict 已在 domain、services 已在 application 声明）；
  新增文件须通过 ddd-lint（违规=0）。
- **听读进度 / Locator**：**零影响**（不新增进度模型、不改 Locator；翻译/查词以选中文本为输入，
  不产生新锚定），需在回归中确认无意外触碰。
- **回归面（非空）**：core 全量测试（store 迁移测试——既有 v1/v2 库升级 v3、library 导入/去重/进度
  既有测试、api 既有函数零行为变化）；`tests/` 集成 + p0_corpus 语料不变；Flutter widget 测试
  （reader_page_test 等既有用例 + 新增 US-15/16 用例）；FFI 端到端；workflow 闸门（CRAP/DDD/变异）。

## 4. 依赖与优先级
- **StarDict 词库来源（候选 + 许可）**：
  - `stardict-langdao-ec-gb` / `stardict-langdao-ce-gb`（朗道英汉/汉英，**自由分发**，stardict 官方
    词库站 http://download.huzheng.org/ 提供）；
  - `stardict-xdict-ce-gb`（译典通）、`stardict-cdict-gb`（简明英汉，GPL）、21 世纪英汉汉英双向词典
    （允许自由分发）；WordNet 3.0（Princeton，自由许可）等。
  - **CI 测试语料**：用 stardict-tools（dictfmt）或脚本**自造小型词库**（<1MB，无版权争议，
    `sametypesequence` 可控为 `'tgm'` 等），来源/变更走既有 corpus 评审规则（对齐 REQ-002 语料纪律）；
    线上验证用朗道词库（用户侧安装，不入仓库）。
- **在线 Provider 的 key 需求**：DeepL API（需 key，Free 层 50 万字符/月，默认候选）；Google Cloud
  Translation（需 key 计费）；有道智云（需 appKey+appSecret，有免费额度）；LibreTranslate（开源可
  自托管，公共实例限流）。**本 REQ 至少实现一个真实 Provider + `EchoProvider` mock/回退实现**
  （可测试、无 key 可演示）；具体选型与免费层策略由架构/产品阶段定，需求约束：Provider 必须经 trait
  可插拔、失败可明确报错、mock 可计数（US-9~US-12 依赖）。
- **既有依赖/前置**：store 迁移机制（rusqlite + user_version，已有）；api 桥接与 FRB（已有）；
  flate2/serde_json/encoding_rs（已有）；**D3 前置：阅读器选中文本能力**（滚动模式选区 + 分页模式
  WebView 选区回调）——`engines/reflow_engine.dart` 的 `selectText` 目前为 TODO，需在阶段 2 确认现状；
  若滚动模式选区缺失，本 REQ 的 US-15 用 Flutter 原生 `SelectionArea` 兜底（归属本 REQ UI 部分或前置
  任务，架构阶段定）。
- **优先级**：本 REQ **P0**（TRANS-01/02 属 MVP"能翻译"）；TRANS-03/04/05 为 P1/P2 后续 REQ，
  不在本 REQ。
- **与其他 REQ 关系**：与 REQ-001（WebView 分页渲染）消费同一选中文本但功能正交；与 REQ-002
  （MOBI/AZW3 解析）无重叠；不依赖笔记 REQ（NOTE 系列）实现，但共享 `TextSelection` 类型定义。

## 5. 风险
1. **在线翻译依赖网络 + key（产品兜底）**：无网/无 key 时离线词库查词完全可用（US-4）；选句翻译
   无 key/断网给明确可重试错误且不丢原文（US-12）；命中缓存即离线可用（US-10/13）——"离线优先"
   策略的正式开关属 TRANS-03，本 REQ 以"缓存命中优先"实现语义。
2. **StarDict 解析细节**：`.dict.dz` 为**整文件 gzip 流**，大词库（100MB+）整包解压内存峰值高 →
   按需解压/仅解压命中条目所在区段（idx 偏移指向文件内区段，.dz 需先整体解压或 mmap 后随机读，
   架构阶段定实现）；`.idx` 二分查找要求索引按字节序有序（不同工具生成差异），大小写/词形归一策略
   需语料覆盖；`sametypesequence` 类型码差异（部分词库含 `x` 例句/`w` 图片等非本 REQ 必要类型）→
   未知类型码跳过不崩溃；坏词库（截断/偏移越界）→ 结构化错误（US-6）。
3. **缓存表增长**：翻译缓存无上限会持续膨胀 → 本 REQ 提供 `translate_cache_clear` 一键清空 +
   hit_count 统计；容量上限/LRU 淘汰策略列为架构决策点（本期至少"清空 + 计数"闭环）。
4. **跨语言**：本 REQ 以**中英（zh↔en）为主**；语言对由调用方显式传入（`translate(text, from, to)`），
   自动语言检测**不在本 REQ**（后续）；中文词库无音标/词性字段 → `DictEntry` 字段全部可空，UI 空值
   不渲染（US-1 已含可空断言）。
5. **网络库与 WSL/Android 构建**：core 目前无 HTTP 依赖；新增 reqwest/ureq 若走 native-tls 需
   OpenSSL 交叉编译（Android NDK + WSL 环境高风险）→ 约束用 **rustls** 后端（纯 Rust，交叉编译友好）；
   或备选方案：HTTP 请求放 Dart 侧（http 包）、Rust 只做编排+缓存（Provider 适配器位置变更，架构
   阶段二选一并出 ADR）。以 `scripts/build-android.sh` 现有构建链为准回归验证。
6. **FRB 异步桥接**：`translate` 若设计为 async（docs/04 §7 trait 注释为 async），现有 api.rs 全为
   sync、core 未启用 tokio → 需引入异步运行时或改为"sync 桥接 + Dart 侧 isolate/线程池"（架构决策点）；
   同步方案下长网络请求阻塞 Rust 线程，需明确线程模型（docs/03 §5）。
7. **隐私合规**：Provider 调用只传 text/from/to（US-13 mock 参数断言）；缓存仅存选中文本相关列；
   清空入口随设置区块交付；在线 Provider 首次使用前需有用户知情（key 是用户主动配置的行为即授权，
   对齐 SET-04 隐私承诺文案）。
8. **范围蔓延**：TRANS-03/04/05 明确排除（§1 划界）；多 Provider 只做接口 + 一个真实 + mock；
   词形还原/自动语言检测/例句朗读等一律后续；架构阶段若发现 KF8 式复杂度（StarDict 解析量）超预期，
   允许以降级线（先支持 `m`/`t`/`g` 主类型 + 朗道词库验证）交付并记录 ADR。

## 6. 闸门1 自评
- [x] 验收标准全部可测：US-1~US-17 每条均含可断言项（`Ok(Some(DictEntry))` 字段值、`Ok(None)`、
  错误类型 `matches!` 与消息子串、mock Provider **调用计数**、缓存命中后计数不变、`translation_cache`
  行数与表列断言、耗时基准 <10ms/<50ms（CI 宽松上限）、widget 测试断言浮层文案/重试按钮/缓存标记），
  无"体验好"类不可测词。
- [x] 与既有 REQ 无重复：REQ-001（WebView 分页渲染/选区机制）只提供选中文本能力，本 REQ 不实现
  选区只挂接翻译入口（US-15 依赖声明）；REQ-002（MOBI/AZW3 解析）无关；Epic D 的 TRANS 故事是产品层
  验收，本 REQ 是翻译/词典核心能力，TRANS-03/04/05 已显式划出（§1/§4）。
- [x] 影响面清单非空：dict 模块实现、store 迁移 v3 + translation_cache、分层约束/仓储 trait 方案、
  api 桥接 + FRB、error.rs 变体、Cargo 依赖、app services/reader/settings、types/notes 共享类型、
  ddd-rules 复核、听读进度零影响确认、回归面（store 迁移/既有测试/widget/FFI/闸门）共 11 项，
  均列具体条目与约束。
