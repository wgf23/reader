<!-- wf-meta: req=REQ-003 | phase=development | agent=developer | date=2026-08-31 | gate=passed -->
# REQ-003 · 开发前置审查（Pre-Implementation Review）

## 1. 设计与既有约定核对
| 检查项 | 结果 |
|---|---|
| 与 docs/03 分层/架构冲突？ | 无冲突。改动落在既有层声明路径内：domain `core/src/dict`（stardict/provider/translation）、共享内核 `core/src/types.rs`（契约与载荷，ADR 决策点3 关键论证：ddd-lint 对 infrastructure 禁 `crate::dict`，store 实现契约必须只 `use crate::types`）、infrastructure `core/src/store/translation.rs`、interface `core/src/api.rs`（新增 7 个 async 桥接函数，既有同步函数零改动）。**docs/03 §4 dict/translate 契约同步（`dict_install` 返回 DictInfo、新增 `dict_remove`、async 说明）属 T-006 内容但 docs/ 不在 developer 写权限内 → 登记为 orchestrator 后续动作（代码侧按 ADR 关联裁定4/US-7 实现，文档债务不阻塞闸门3）** |
| 与 docs/04 Locator/限界上下文冲突？ | 无。locator/reading_progress/tts/notes 零改动；翻译/查词以选中纯文本为输入，不新增锚定；`vocabulary` 表不建（TRANS-04 排除，不占迁移号）；`TextSelection` 不新增（归笔记 REQ）；translation_cache/settings DDL 与 docs/04 §5 逐列一致 |
| 与既有 ADR 冲突？ | 无。02-adr.md 为本次架构产物：A1（同步 Provider + FRB async 桥接）、决策点2（滚动 SelectionArea + 分页最小 JS 选区回传）、B1（契约落 types.rs）、C1（ureq+rustls）；全部与 docs/03 §5 线程模型、docs/04 §7 同步签名、docs/02 §8 依赖约定一致 |
| 与既有业务（听读进度/笔记锚定）冲突？ | 无。library/store 既有路径零行为变化；`migrate_conn` 提取为行为等价重构（v1/v2 分支原样保留）；api 既有 sync 函数零改动；reader_page 新增 `translateBackend` 为可选参数（null 隐藏入口，既有测试零回归）；paged_web_view 仅追加选区回传（既有 onProgress 行为不动） |

### 1.1 实现级澄清（相对 02-design 的措辞修正，均不构成 rework-A/B/C，代码内注释说明）
1. **`Lang` 缺 `Auto` 变体**：02-design §4.2/§5.1 的 UI 默认调用为 `translate(text, "auto", "zh")`，但 §2.1 `Lang` 枚举无 Auto → api 层 `Lang::parse("auto")` 会失败。处置：`Lang` 新增 `Auto`（`as_str()=="auto"`、parse 识别），DeepL 请求对 Auto 省略 `source_lang`。
2. **`SelectionArea.onSelectionChanged` 载荷**：Flutter 原生回调给的是 `TextSelection`（起止偏移），**无 `plainText`**（02-design §5.2 措辞不成立）。处置：reader_page 持 `chapter.text`，回调时 `substring(sel.start, sel.end)` 取选中纯文本（单 Text 渲染场景偏移一一对应）。
3. **`from_cache` 标注**：02-design §2.4 的 `translate` 返回 `Result<Translation>`（无缓存标记），§2.7 api 却要 `from_cache`。处置：`TranslationService` 新增 `translate_cached(...) -> Result<(Translation, bool)>`，`translate` 保持设计签名薄包装（`map(|(t,_)| t)`）；api 层用 `translate_cached` 取标记。
4. **`t`（音标）字段终止语义**：sametypesequence 模式下文本型字段按 NUL 终止（末字段止于条目边界）。真实 langdao-ec 词库下载已确认可达（8.7MB），T-002 用真实语料实测验证；若实测存在 `t` 带 1 字节长度前缀的变体，按实测修正并记录。
5. **`PagedViewBuilder` typedef 扩展**：分页模式需透传选中回调；`onSelectedText` 声明为**可选命名参数**（默认 null）→ 既有 `fakePagedBuilder`（无该参数）仍然可赋值，既有 reader_page_test 零改动零回归。
6. **SettingsPage 可测性**：导入按钮经 `FilePicker` 选 `.ifo`；widget 测试环境无平台插件 → SettingsPage 增可选 `filePicker` 注入（默认实现用 FilePicker，测试注入假 picker）。
7. **domain 层 HTTP 客户端合规性确认**：ddd-rules.toml 的 domain 层 `forbid_external = []`（仅禁 `crate::store|api|library` 内部依赖）→ `DeepLProvider`（ureq）落 `core/src/dict/provider.rs` 合规，规则表零改动；网络仅封装于 DeepLProvider 内部（ADR 决策点4 影响）。
8. **`dict_install` 入参语义**：02-design §5.3 为"选 `.ifo` → installDict" → 入参为 `.ifo` 文件路径，同目录同名 `.idx`/`.dict`(或 `.dict.dz`) 由文件名推导（校验三件套，缺一即 Corrupt）。

## 2. 计划核对
| 检查项 | 结果 |
|---|---|
| 任务缺失/依赖环/估算离谱？ | 无。T-001..T-009 覆盖"语料 → 解析内核 → 查词服务 → Provider/缓存 → store 迁移 → 桥接 FFI → app UI/浮层/设置 → 测试强化/基准"全链；依赖图无环（T-003/T-004 并行、T-007/T-008 并行）。**一处计划依赖外部（非 rework）**：T-006 含"docs/03 §4 契约同步更新"，但 developer 写权限不含 docs/ → 该子项转 orchestrator 在闸门3 后补做（代码与文档契约均以 02-design/ADR 为准，不会错位）。T-009 的 build-android.sh 交叉编译回归同理属后续阶段（rustls 纯 Rust，除 ring 的 C 编译外无 OpenSSL 依赖——cc（gcc-15）已在 toolchain 验证可用） |

## 3. 需求可测性核对
| 检查项 | 结果 |
|---|---|
| 验收标准可实现且可测？ | 是。US-1~US-17 全部落为可断言项：`Ok(Some(DictEntry))` 字段精确值（自造 tgm 语料 t→phonetic/g+m→definition/x→example 归位）、`Ok(None)` 未收录、`Err` 消息子串（"词库/未安装/导入"、"未配置/API Key"、"网络/失败"+原文）、mock Provider **调用计数**（US-9/10/11/12）、缓存表行数/列断言（US-13）、耗时基准（US-8 100 次查词均值 <50ms CI≤200ms；US-14 ≥1000 行命中 <10ms CI≤100ms）、widget 测试断言浮层文案/Provider 名/缓存标记/重试按钮（US-15/16）、桥接函数存在性与签名（US-17）。"分页模式选中回调产生"（US-15 第二句）经 fake PagedViewBuilder 注入选中回调可测（真 JS 走 FFI 冒烟/真机）。真实 langdao 词库下载已确认可达（huzheng.org HTTP 200，8.7MB<30MB），若 T-001 下载完成则真实词库断言可用；若中途失败按计划"已知缺口"登记不阻塞 |

## 4. 结论
- [x] 通过，进入实现（§1.1 的 8 项均为实现级澄清/措辞修正，含处置，不构成 rework-A/B/C；docs/03 §4 同步与 Android 构建回归为跨阶段交接项，已登记）

## 5. 实现与自检记录
| Task | 完成 | 测试 | CRAP | DDD |
|---|---|---|---|---|
| T-001 语料获取与校验 | ✅ | `make_test_dict.py` 生成 test-tgm/test-tgmx(+.dz)/test-tgz + 坏词库 ×4（截断/越界/缺 wordcount/.dz 截断），两次运行字节一致（可复现已验证）；**真实词库下载成功**：langdao-ec（朗道英汉 435468 词条，seq='m'，8.7MB tar.bz2）+ langdao-ce（朗道汉英 405719 词条），sha256 与来源登记于 corpus/README.md（新增 dicts 章节） | — | — |
| T-002 StarDict 解析内核 | ✅ | stardict.rs 15 项单测：parse_ifo（缺 wordcount→Corrupt）、load_idx（截断/缺 NUL/全 0 padding）、lookup_entry（二分精确/首字母归一/忽略大小写）、parse_entry（tgm 归位、tgmx example、空音标→None、未知类型码 tgz 跳过、旧格式空 seq、越界→Corrupt）、decompress_dz（往返/截断流→Corrupt）；types.rs 契约（Lang/Translation/CacheKey/CacheEntry + 2 trait，serde 手写 Lang） | PASS（parse_entry CC13 cov96% CRAP13.0） | 0 违规 |
| T-003 DictService | ✅ | translation.rs 13 项服务单测：安装/列表/查词往返、空注册表 Err 含"词库/未安装"、大小写归一（"Apple"）、未收录 None、多词库按序首命中 + dict_id 过滤、幂等、移除删目录回落 US-3、坏词库不破坏列表、偏移越界 Corrupt、.dz 解压查词、**US-8 性能基准（2 万词条：100 次查词 77µs，单次均值 0.001ms，预算 50ms/CI 200ms）** | PASS | 0 违规 |
| T-004 Provider + TranslationService | ✅ | provider.rs 4 项单测（Echo/DeepL 未配置 NotConfigured/configure 后 Network 携带原文/Counting 计数）；translation.rs 12 项服务单测：US-9（echo 返回 + 参数仅 text/from/to）、空白归一、US-10（计数==1 + 二次 <100ms）、US-11（Provider/语言对任一不同即 Miss）、US-12（NotConfigured 含"API Key"、FailingProvider Network 携带原文且不写缓存、重试闭环）、US-13（清空→行数 0→重翻重调）、from_cache 标记 + hit_count 递增、set_config 切换；error.rs 新增 NotConfigured/Network 变体 | PASS | 0 违规 |
| T-005 store v3 + TranslationRepo | ✅ | store/translation.rs 7 项单测：put/get/UPSERT 不重置 hit_count、Miss、键区分、clear/count、ProviderConfig 往返、**v2→v3 迁移（存量书+进度不丢、新表可用、user_version==3、dicts/ 目录）**、**US-14 性能基准（1200 行命中查询 20.5µs，预算 10ms/CI 100ms）**；migrate_conn 提取行为等价（既有 store 测试零回归） | PASS | 0 违规 |
| T-006 api 桥接 + FRB + FFI | ✅ | api.rs 新增 7 个 async 桥接函数 + 3 个 Debug DTO；library_open 装配 DICT/TRANSLATION 双单例（两 trait 各一 TranslationRepo 第二连接）；FRB 2.13 再生成（frb_generated.rs + app/lib/src/rust/**）；core 集成测试 translate_corpus.rs 7 项（含真实 langdao-ec/ce 查词、"苹果"中文词条、坏词库、block_on 驱动 async 全链路：未配置 key→NotConfigured→set_config(echo)→命中缓存→行数断言→清空→重翻→非法语言码）；**Dart FFI 端到端 rust_dict_ffi_test.dart 全链路通过**（dictInstall→lookup 命中 .dz 路径→translate(echo)→fromCache→clear→remove）；既有 rust_bridge_test.dart 零回归 | PASS | 0 违规 |
| T-007 app 服务层 + reader 接入 + 浮层 | ✅ | services：translate_backend.dart（DTO+抽象）/rust_translate_backend.dart/frb_init.dart（共用 init，rust_library_backend 重构复用）；reader_page：滚动模式 SelectionArea（SelectedContent.plainText）+ 选中工具条（翻译/查词/取消）+ 可选 translateBackend（null 隐藏入口）；paged_web_view：onSelectedText + selectionchange JS + addJavaScriptHandler（6.x API；顺带修复 readerFlutter 进度回调此前未注册 handler 的缺口）；widgets/translation_popup.dart（译文卡片含 Provider 名+缓存徽标、词典卡片、OverlayError+重试、loading）；**translate_reader_test.dart 6 项 widget 测试全绿**（US-15 滚动/失败重试/分页回传、US-16 卡片/未找到/无词库引导、null 后端零回归） | PASS | 0 违规 |
| T-008 设置页最小区块 | ✅ | settings_page.dart："词典与翻译"区块（导入 .ifo/列表+移除/DeepL key 输入/清空缓存；filePicker 注入可测）；**settings_page_test.dart 3 项全绿**（控件渲染+交互、无词库引导、取消选择） | PASS | 0 违规 |
| T-009 测试强化 + 基准 + 回归 | ✅ | `cargo test --all-targets` 全绿：111 单测 + 21 mobi_azw3 + 5 p0_corpus + 7 translate_corpus = **144 项**（既有测试零回归）；`flutter test` 全绿 14 项 + FFI 2 项（含既有 rust_bridge_test）；CRAP 报告（见 §5.1）；DDD 报告（见 §5.1）；性能基准实测已入测试断言并记录（US-8 0.001ms/次、US-14 20.5µs） | FAIL=0 / WARN=5（全为既有 format/convert 代码，非本 REQ 新代码） | 0 违规 |

### 5.1 实现期发现与处置（相对 02-design 的实现级偏差，均已在代码注释说明）
1. **Flutter 6.x API**：flutter_inappwebview 6.1.5 无 `onCallBackHandler` 参数，JS 回调须经 `controller.addJavaScriptHandler`（onWebViewCreated 注册）——按 6.x 现状实现；顺带修复既有 `readerFlutter` 进度回调从未注册 handler 的缺口（既有 onProgress 参数语义不变）。
2. **`SelectionArea.onSelectionChanged` 载荷**：Flutter 原生给的是 `SelectedContent?`（含 `plainText`）而非 `TextSelection`——按 `content?.plainText` 取文本（比 03-review §1.1 预判的 substring 方案更简）。
3. **FRB `u64` → Dart `BigInt`**：DictInfoView.word_count 在 Dart 侧为 BigInt，服务层 `.toInt()` 转 int（DTO 契约保持 int）。
4. **`TranslationProvider` 增 `Send` 超 trait**：TranslationService 以 `static Mutex` 进程单例持有（api 装配），要求容器 Send——内置 Provider 全部天然 Send；与 ADR 决策点1"不引入 async trait Send 约束"不冲突（注释说明）。
5. **既有测试文件最小改动**：`reader_page_test.dart` 的 `fakePagedBuilder` 增加可选命名参数 `onSelectedText`（Dart 函数子类型规则：typedef 新增命名参数后旧函数不可赋值）——仅签名扩展，**断言零改动**。
6. **真实词库实测**：langdao-ec/ce 均 `sametypesequence='m'`（无 t 音标字段、无 g HTML）→ phonetic=None、pos 启发式按行首扫描（`*['æpl]\nn. 苹果…` 的次行标记可识别，extract_pos 增强）；`.dict.dz` 整文件 gzip 安装期流式解压实测通过。
7. **中文词库名 id 碰撞**：langdao-ec/ce 的 bookname 消毒后同为退化下划线串 → sanitize_id 增"退化回退 dict-<fnv32 哈希>"，幂等键改用 bookname 精确匹配。
8. **docs/03 §4 契约同步（T-006 计划内但 docs/ 超出 developer 写权限）** → 登记为 orchestrator 交接项（代码按 ADR 关联裁定4/US-7 实现：`dict_install` 返回 DictInfo、新增 `dict_remove`、async 说明），不阻塞闸门3。

### 5.2 闸门3 自评
- [x] CRAP FAIL=0（`workflow/reports/crap-req003.md`；新代码最高 CRAP 13.2 < WARN 15；WARN=5 全为既有 format/convert 代码，非本 REQ 新增）
- [x] DDD 违规=0（`workflow/reports/ddd-req003.md`；domain 层 dict/types/error 无 `crate::store|api|library`；infrastructure store 只依赖 crate::types；app pages 不 import 桥接生成物）
- [x] `cargo test --all-targets` 全绿（144 项，既有断言零改动零回归）+ `flutter test` 全绿（14 项 + FFI 2 项含既有 rust_bridge_test）
- [x] 无未处理 rework（本阶段无 rework-A/B/C；§5.1 的 8 项均为实现级处置）
- [ ] 交接项（不阻塞闸门3）：docs/03 §4 dict/translate 契约同步（orchestrator）；build-android.sh 交叉编译回归（ureq+rustls 无 OpenSSL，T-009 计划内后续阶段）；真实 langdao 词库已入仓库但 CI 用例在文件缺失时跳过（确定性 CI 主语料为自造词库）
