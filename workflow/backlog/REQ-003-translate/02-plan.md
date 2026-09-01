<!-- wf-meta: req=REQ-003 | phase=architecture | agent=architect | date=2025-08-31 | gate=passed -->
# REQ-003 · 计划拆分（Task 分解：翻译与词典）

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收 |
|---|---|---|---|---|
| **T-001** | **词库语料获取与校验**：① 自造受控词库脚本 `scripts/make_test_dict.py`（生成 `.ifo/.idx/.dict` 与 `.dict.dz` 两变体，`sametypesequence='tgm'`，含音标/HTML 释义/纯文本释义混合、含大小写混合词条 "Apple"、含 "n." 词性标记、含未知类型码 `x` 条目；词条数 ≥20）；② 坏词库构造（`.idx` 截断/偏移越界/`.ifo` 缺 `wordcount`，脚本化）；③ 真实词库下载尽力而为（候选源见下，huzheng.org 朗道/译典通/简明英汉）；④ 全部落 `tests/corpus/src/dicts/`，更新 `corpus/README.md`（来源/许可/大小/sha256） | — | 1d | `tests/corpus/src/dicts/` 含：自造 tgm 词库 ×2 变体（.dict 与 .dict.dz）、坏词库 ≥3、真实词库 ≥1（下载成功则校验记录；网络受限则登记"已知缺口"不阻塞，对齐 REQ-002 先例）；README 每行含来源 URL/许可/大小 <30MB/sha256；`make_test_dict.py` 在仓库内且可复现（两次运行产物字节一致） |
| **T-002** | **StarDict 解析内核**（design §2.3）：`parse_ifo`（wordcount 缺失→Corrupt）、`load_idx`/`lookup_entry`（二分 + 首字母/全小写归一线性扫描）、`parse_entry`（sametypesequence t/m/g/x + 未知码跳过 + 区段越界→Corrupt）、`decompress_dz`（flate2 流式解压）；`types.rs` 领域类型 `Lang`/`DictEntry`/`DictInfo` + `Translation`/`CacheKey`/`CacheEntry`（serde）先行落地 | T-001 | 1.5d | US-1/US-2/US-5/US-6 内核级通过：tgm 词库 `parse_entry` 各字段按类型码归位无错位（`t`→phonetic、`g/m`→definition、`x`→example，精确断言）；未收录返回 `None`；"Apple" 经 "apple" 命中；`.dict.dz` 路径解压正确；坏词库（截断/越界/缺 wordcount）全部 `Err(Corrupt)` 不 panic；未知类型码不崩溃；`cargo test` 新测试全绿 |
| **T-003** | **词库注册与查词服务**（design §2.4 `DictService`）：`new`（建 dicts/ + 扫描既有安装）、`install`（校验三件套→拷贝→.dz 解压→幂等注册）、`remove`（删目录+注销）、`list`（安装序）、`lookup`（多词库顺序 + dict_id 过滤 + 懒加载索引 + 单词典失败容错）；US-8 性能预算 | T-002 | 1d | US-3/US-5/US-6/US-7/US-8 通过：空注册表 lookup → `Err` 消息含"词库"与"未安装/导入"；双词库按安装序取首个命中（A、B 均含时只返回 A）；`install` 返回 `DictInfo`（name/word_count/path 正确）、重复安装幂等返回既有、`dict_list` 含之；`remove` 后列表不含且文件被删、查词回落 US-3；坏词库安装失败不影响已装列表；计时测试：索引已加载后 100 次连续 lookup 平均 <50ms（CI 宽松断言 ≤200ms，记录基准值） |
| **T-004** | **Provider 与翻译服务**（design §2.4 `TranslationService` + §2.2 trait + 测试 Provider）：`TranslationProvider` 完整化（同步签名 + `configure` 默认方法）；`DeepLProvider`（ureq+rustls，POST /v2/translate，auth header，仅 text/from/to）；`EchoProvider`；测试注入 `CountingProvider`/`FailingProvider`/参数记录 mock；`normalize_text`；缓存优先编排（命中 incr_hit、失败不写缓存、UPSERT 幂等）；`error.rs` 新增 `NotConfigured`/`Network{detail,source_text}` | T-002 | 1.5d | US-9~US-14 通过（内存 Mock 仓储注入，服务层不碰 SQLite）：Echo 返回与注入一致且 mock 记录参数**只含** text/from/to；跨行空白归一化后传给 Provider；`CountingProvider` 同文同语言对同 Provider 连续 2 次 → 计数 ==1、两次 text 一致、第二次耗时 <10ms（CI ≤100ms）；语言对/Provider 任一不同即 Miss（计数 +1）；未配置 key → `Err` 含"未配置/API Key"；`FailingProvider` → `Err` 含"网络/失败"语义**且消息携带原文本**、重复失败缓存行数不变；失败后再配置可用 Provider 重试成功；清空后重翻重新调 Provider；命中缓存返回 `from_cache` 标记；`Network`/`NotConfigured` 新变体测试断言 |
| **T-005** | **store v3 迁移 + 仓储实现**（design §3）：`migrate_conn` 提取（Store::open 复用）；v3 DDL（translation_cache + settings）；`Store::open` 追加 dicts/ 目录；`TranslationRepo`（第二连接，WAL + busy_timeout）实现 `TranslationCacheRepository` + `ProviderConfig`；v2→v3 迁移测试（存量 books/reading_progress 不丢） | T-004 | 1d | 迁移测试绿：user_version=2 存量库（含书+进度）重开 → 数据完整、新表存在、`PRAGMA user_version==3`；`TranslationRepo` 的 get/put(UPSERT 不重置 hit_count)/incr_hit/clear/count 与 settings 读写单测（≥1000 行命中查询 <10ms，CI ≤100ms）；既有 store 测试（v1/v2）零回归 |
| **T-006** | **桥接与 FFI**（design §2.7）：api.rs 新增 7 个 **async** 桥接函数 + 3 个 DTO；`library_open` 装配 DICT/TRANSLATION 双单例（两 trait 各注入一个 `TranslationRepo`）；`Lang::parse` 映射；`dict_install` 返回 `DictInfoView`（docs/03 §4 偏差处理，ADR 关联裁定4）；frb_generated.rs + `app/lib/src/rust/**` 按 bridge/README 再生成；docs/03 §4 dict/translate 契约同步更新 | T-003, T-004, T-005 | 1.5d | US-17 通过：`dict_install/dict_remove/dict_list/dict_lookup/translate/translate_cache_clear/translate_set_config` 全部存在、签名与 02-design §2.7 一致（`Result<…, String>` 错误映射，含 US-3/US-12 文案）；`cargo test` 全绿（api 既有函数零行为变化）；Dart 侧 `rust.translate` 等可调用（rust_bridge_test 增 FFI 冒烟：自造词库 install→lookup 命中、translate(echo) 走通、clear 后行数归零）；docs/03 §4 契约已同步 |
| **T-007** | **app 服务层 + 阅读器接入 + 浮层/卡片**（design §5.1/§5.2）：`translate_backend.dart`（DTO + 抽象）、`rust_translate_backend.dart`、测试 `FakeTranslateBackend`；reader_page：`SelectionArea`（滚动模式）+ 选中工具条（翻译/查词/取消）+ 分页模式 `PagedWebView.onSelectedText`（paginationJs 选区监听 + `selectedText` callHandler，~20 行 JS）+ 可选 `translateBackend` 参数；`translation_popup.dart`（译文卡片含 Provider 名与缓存标记、词典卡片、loading/错误+重试）；US-15/16 widget 测试 | T-006 | 1.5d | US-15/US-16 widget 测试全绿：滚动模式注入选中（`SelectionArea.onSelectionChanged` 直接触发）→ 工具条含"翻译"入口 → 点击后 loading → 译文浮层展示 mock 文案 + Provider 名 + 缓存标记；失败显示错误文案与"重试"按钮（点击重发）；分页模式经 fake `PagedViewBuilder` 产生选中回调 → 同一翻译入口可用（真 JS 走 T-006 FFI 冒烟/真机验证）；查词：词条/音标/词性/释义渲染、未收录"未找到"、无词库引导文案；既有 reader_page_test/library_page_test 零回归 |
| **T-008** | **设置页最小区块**（design §5.3）："词典与翻译"区块——词库导入（file_picker 选 `.ifo`）/列表/移除、Provider key 输入（`setConfig`）、清空翻译缓存按钮；widget 测试（FakeTranslateBackend 注入） | T-006 | 1d | widget 测试绿：区块各控件渲染；导入按钮触发 `installDict`；列表展示 + 移除调用 `removeDict`；key 输入落 `setConfig('deepl', key)`；清空按钮调用 `clearCache`；TRANS-03 进阶 UI（Provider 启停/默认选择/离线开关）不出现（划界） |
| **T-009** | **测试强化 + 基准 + 回归**：变异测试（dict/、store/translation.rs、types 契约 ≥80%）、覆盖率（新代码行 ≥85%）、CRAP 报告（FAIL=0）、性能基准记录（US-8/US-14 实测值写入报告）、corpus 回归纳入 p0_corpus 模式、`scripts/build-android.sh` 回归（ureq+rustls 交叉编译） | T-003..T-006 | 1.5d | 闸门4 报告齐全：`04-mutation-report.md`（存活体 100% 有结论）、`04-coverage-report.md`、`03-crap-report.md`（FAIL=0）；基准记录文件（lookup 均值/缓存命中耗时实测）；既有 19 单测 + 5 语料 + FFI 端到端全绿；Android 构建脚本回归通过（rustls 无 OpenSSL 依赖验证，ADR 决策点4） |

## 依赖图
```
T-001 → T-002 ─┬→ T-003 ─┐
               └→ T-004 → T-005 ─┤
                                 ├→ T-006 ─┬→ T-007
                                 │         └→ T-008
T-003..T-006 ────────────────────────────────→ T-009
（无环；T-003/T-004 在 T-002 后并行；T-005 依赖 T-004（契约先行）；T-007/T-008 在 T-006 后并行；
 关键路径 T-001→T-002→T-004→T-005→T-006→T-007→T-009 ≈ 9.5d；T-003/T-008 不占关键路径）
```

## 语料候选源与校验（T-001 落地指引；URL 以开发阶段实测为准，下载失败登记缺口不阻塞）
| 语料 | 候选源 | 校验方式 |
|---|---|---|
| 朗道英汉 `stardict-langdao-ec-gb-2.4.2`（自由分发，默认验证词库） | `http://download.huzheng.org/zh_CN/stardict-langdao-ec-gb-2.4.2.tar.bz2`（StarDict 官方词库站；`.tar.bz2` 内含 `.ifo/.idx/.dict.dz`） | 解包后校验三件套存在、`sametypesequence` 含释义类型；`sha256sum` 记录；大小 <30MB；T-003 冒烟（查已知词命中、词条数 == wordcount） |
| 朗道汉英 `stardict-langdao-ce-gb-2.4.2`（汉英方向） | `http://download.huzheng.org/zh_CN/stardict-langdao-ce-gb-2.4.2.tar.bz2` | 同上；中文词条无音标字段断言（`phonetic=None`，US-1 可空） |
| 译典通 `stardict-xdict-ce-gb-2.4.2`（备选） | `http://download.huzheng.org/zh_CN/stardict-xdict-ce-gb-2.4.2.tar.bz2` | 同上（仅作备选，未下载不阻塞） |
| 简明英汉 `stardict-cdict-gb-2.4.2`（GPL，备选） | `http://download.huzheng.org/zh_CN/stardict-cdict-gb-2.4.2.tar.bz2` | 同上 |
| 自造 tgm 词库（CI 主语料，无版权争议） | `scripts/make_test_dict.py` 生成（仓库内脚本，`sametypesequence='tgm'`，含 .dict 与 .dict.dz 两变体、大小写混合词、`x` 例句、`n.` 词性标记） | 脚本两次运行产物 sha256 一致（可复现）；T-002/T-003 精确断言用 |
| 坏词库（截断/越界/缺 wordcount） | 脚本从自造词库派生：`.idx` 截断（尾部切断）、偏移越界（patch 条目 size/offset 超 .dict 长度）、`.ifo` 删 `wordcount` 行；`.dz` 损坏（gzip 流截断） | 对应 `Err(Corrupt)` 断言（US-6）；已装列表不受影响（T-003） |

> 语料规则（corpus/README.md + docs/05 §3）：只收无版权争议文件（StarDict 官方自由分发词库 /
> 自造样例）；单文件 <30MB；来源/许可/生成命令记录；变更需评审（影响快照与基准）。CI 只用自造
> 语料（确定性），真实词库用于用户侧与开发机验证（不入 CI 依赖，与 REQ-002 corpus 纪律一致）。

## 冲突检查结果
- **与既有业务无冲突（或已列处置）**：
  1. **ddd-rules 合规**（关键）：store 实现契约仅 `use crate::types`（ddd-lint infrastructure 禁
     `crate::dict`，ADR 决策点3）——处置：契约与载荷类型落共享内核 `types.rs`，规则表零改动；
     新增文件全部落在既有层声明路径内。
  2. **01-req §4 D3"既有选中能力"实际不存在**（reflow_engine.selectText=TODO、paged_web_view 无
     选区回调）——处置：滚动模式 `SelectionArea`（01-req 已授权）+ 分页最小选区回传纳入本 REQ
     （T-007），完整选区机制归 REQ-001 演进/笔记 REQ（ADR 决策点2）。
  3. **docs/03 §4 `dict_install` 返回类型与 US-7 冲突**——处置：采用 US-7（返回 DictInfo），
     docs/03 §4 契约随 T-006 同步更新；`dict_remove` 为 docs/03 §4 补充函数。
  4. **01-req §3"async fn translate"注释 vs docs/04 §7 同步签名**——处置：采 docs/04 §7 同步签名
     + FRB async 桥接（ADR 决策点1），注释为过时占位。
  5. **听读进度 / Locator 零影响**：不触碰 `locator`/`reading_progress`/`tts`；翻译/查词以选中
     纯文本为输入，不新增锚定（docs/04 §3/§9 不变式保持）。
  6. **限界上下文**（docs/04 §1）：全部改动在 Translation 上下文 + 共享内核 + infrastructure
     settings/缓存表；`vocabulary` 表不建（TRANS-04 排除，不占迁移号）；`TextSelection` 不新增
     （归笔记 REQ）。
  7. **既有 api 桥接零行为变化**：新增函数全为 async 新函数；既有 sync 函数、SERVICE 单例、
     library/store 路径不动（T-005 的 `migrate_conn` 提取为行为等价重构，回归验证）。
  8. **网络/隐私**：ureq+rustls 无 OpenSSL（Android NDK/WSL 构建回归 T-009）；Provider 请求只
     传 text/from/to（US-9/13 mock 断言）；缓存仅选中文本列 + 一键清空（docs/04 领域规则4）。
- **计划完整性**：T-001..T-009 覆盖"语料 → 解析内核 → 查词服务 → Provider/缓存 → store 迁移 →
  桥接 FFI → app UI/浮层/设置 → 测试强化/基准"全链，无缺口；任务粒度每项 ≤1.5d 且均有可断言
  验收；依赖图无环（T-003/T-004、T-007/T-008 并行）。
- **已知取舍（非冲突，已列处置）**：huzheng.org 下载在本环境可能受限（对齐 REQ-002 的 Feedbooks
  403 先例）——真实词库登记"已知缺口"，CI 主语料为自造词库，不阻塞；DeepL 需真实 key，FFI/集成
  用 echo Provider 覆盖（US-9/10/11/12 的计数/失败断言在 Rust 服务层注入 mock，不依赖真网络）。

## 闸门2 自评（计划部分）
- [x] 任务粒度可执行（每任务 ≤1.5d、有可断言验收）
- [x] 无依赖环（依赖图如上，T-003/T-004、T-007/T-008 并行，关键路径 ≈9.5d）
- [x] 冲突检查通过（8 项核对无冲突或已列处置；3 处已知取舍均含处置方案；ADR 备选 ≥2 且给理由）
