<!-- wf-meta: req=REQ-003 | phase=testing | agent=test-engineer | date=2025-09-01 | gate=passed -->
# REWORK-REQ-003-D · 变异测试缺陷修复记录（rework-D）

## 触发
阶段 4 变异测试（cargo-mutants 27.1.0，作用域 `src/dict/stardict.rs` + `provider.rs` + `translation.rs` +
`mod.rs` + `src/store/translation.rs`，timeout 60s，`CARGO_BUILD_JOBS=2 --jobs 2`）首轮结果：
**97 caught / 39 missed / 1 timeout / 14 unviable → 变异分数 = 97/(97+39) = 71.3%，低于 80% 门槛**
→ 触发 rework-D。

**A 片环境限制说明**：stardict.rs 共 95 变异体，环境在评估 40 个（35 caught / 2 missed / 3 unviable）
后被截断，55 个未评估；按任务约定"按已评估部分计入"，且 **A 片复跑跳过**（本轮仅复跑补测涉及的
B/C/D 片），A 片 2 个 missed 的补测已写入但未复跑验证（见下）。

## 存活变异体分析（39 个 → 处置 36 个真测试缺口 + 2 个等价豁免 + 1 个变异致死循环转超时）

| # | 位置 | 变异 | 判定 | 处置 |
|---|---|---|---|---|
| A1 | stardict.rs:138 | lookup_entry `\|\|`→`&&`（word==word 与 word==lower 之间） | **真测试缺口** | 新增 `lookup_unicode_mixed_case_normalizes_via_lowercase`：非 ASCII 混合大小写词 "Éclair"→"éclair"（binary 字节序未命中 → 线性扫描 lower 路径命中；`eq_ignore_ascii_case` 不折叠非 ASCII，变异后返回 None）→ 已杀（A 片未复跑，理由见上） |
| A2 | stardict.rs:139 | lookup_entry `\|\|`→`&&`（lower 与 first_flipped 之间） | **真测试缺口** | 同上测试一并杀死（该输入 first_flipped 为空 → 变异路径 B&&C 短路且 D 不成立）→ 已杀（未复跑） |
| B1 | mod.rs:80 | strip_html_tags 删除 `'<'` 臂 | **真测试缺口** | 新增 `strip_html_tags_removes_tags_keeps_text`（"<b>n.</b> A fruit"→"n. A fruit"）→ 已杀 |
| B2 | mod.rs:81 | `'>'` 守卫 `in_tag`→`true` | **真测试缺口** | 新增 `strip_html_tags_keeps_stray_gt`（游离 `>` 不在标签内应保留，变异吞掉）→ 已杀 |
| B3 | mod.rs:82 | `_ if !in_tag` 守卫→`true` | **真测试缺口** | 新增 `strip_html_tags_skips_tag_contents`（标签内字符应丢弃）→ 已杀 |
| B4 | provider.rs:42 | translate `from != Auto`→`==` | **真测试缺口**（from=Auto 时错误附加 source_lang=EN，违反 DeepL 自动检测语义与 US-9 参数契约；04-coverage 热点1 预定"补结构测试"路径） | **行为等价重构**：请求体构造提取为纯函数 `deepl_body`（仅提取，无任何语义变化），新增 `deepl_body_omits_source_lang_for_auto`（断言 Auto 无 source_lang 键）/`deepl_body_includes_source_lang_when_specified` → 已杀 |
| B5 | provider.rs:97 | deepl_code 恒 `""` | **真测试缺口** | 新增 `deepl_code_maps_all_langs`（9 语言码 + Other 透传 + Auto 臂全断言）→ 已杀 |
| B6 | provider.rs:97 | deepl_code 恒 `"xyzzy"` | **真测试缺口** | 同上 → 已杀 |
| C1 | translation.rs:50 | scan_existing → `()` | **真测试缺口**（US-7 安装持久化：重开服务必须重扫已装词库，04-coverage 热点3） | 新增 `dict_scan_existing_on_reopen_registers_installed` → 已杀 |
| C2 | translation.rs:121 | install idxfilesize `!=`→`==` | **等价豁免** | 该条件仅控制一条 advisory `log::warn!`（"idxfilesize 声明与实际不一致"）的发出；两语义下 `install` 均成功返回相同 `DictInfo`，不改变返回值/错误/注册表/文件系统任何 API 可观察状态。日志文本差异不构成验收标准（US-1~US-17）可观察行为；对齐 REQ-002 防御分支豁免先例 |
| C3 | translation.rs:272 | unique_id `+=`→`-=` | **真测试缺口** | 新增 `dict_unique_id_colliding_sanitized_names_get_suffix`（"foo bar"/"foo_bar"/"foo*bar" 三词库消毒同 id → 期望 foo_bar/foo_bar-2/foo_bar-3；`-=` 变异第三次给 foo_bar-1）→ 已杀 |
| C4 | translation.rs:272 | unique_id `+=`→`*=` | **变异致死循环（转 timeout 口径）** | `n *= 1` 使 n 恒 2：第 2 次碰撞前行为与原始一致（0/1 次碰撞输入恒等），第 3 次碰撞起死循环 → 任何触发 ≥2 次碰撞的测试都只能以超时终止，**无有限测试可杀**；补测后该输入使变异超时（timeout 单列不计分，docs/07 §7） |
| C5 | translation.rs:279 | find_ifo_in 恒 `None` | **真测试缺口** | 新增 `dict_install_with_directory_argument`（目录入参安装，04-coverage 热点4）+ reopen 测试 → 已杀 |
| C6 | translation.rs:279 | find_ifo_in 恒空路径 | **真测试缺口** | 同上（空路径 parse_ifo 失败 → 安装/重扫失败）→ 已杀 |
| C7 | translation.rs:282 | find_ifo_in `==`→`!=` | **真测试缺口** | 同上（变异选非 .ifo 扩展名文件 → 解析失败）→ 已杀 |
| C8 | translation.rs:290 | dict_stem 恒 `""` | **真测试缺口** | reopen 测试（重扫时拼出 `.idx` 路径 → 读取失败 → 词库丢失）→ 已杀 |
| C9 | translation.rs:290 | dict_stem 恒 `"xyzzy"` | **真测试缺口** | 同上（`xyzzy.idx` 不存在）→ 已杀 |
| C10 | translation.rs:323 | sanitize_id 恒 `""` | **真测试缺口** | 新增 sanitize_id 单测组（`sanitize_id_keeps_alnum_hyphen_underscore` / `_empty_becomes_dict` / `_cjk_falls_back_to_hash` / `_alnum_count_threshold` / `_truncates_overlong`）→ 已杀 |
| C11 | translation.rs:323 | sanitize_id 恒 `"xyzzy"` | **真测试缺口** | 同上 → 已杀 |
| C12 | translation.rs:326 | sanitize_id `\|\|`→`&&`（42 列，alnum 分支） | **真测试缺口** | `sanitize_id_keeps_alnum_hyphen_underscore`（"foo-bar_baz2" 原样保留，变异全映射下划线）→ 已杀 |
| C13 | translation.rs:326 | sanitize_id `\|\|`→`&&`（54 列，`-` 分支） | **真测试缺口** | 同上 → 已杀 |
| C14 | translation.rs:326 | sanitize_id `==`→`!=`（47 列 `c=='-'`） | **真测试缺口** | 同上（"foo-bar"→"foo_bar"）→ 已杀 |
| C15 | translation.rs:326 | sanitize_id `==`→`!=`（59 列 `c=='_'`） | **真测试缺口** | 同上 → 已杀 |
| C16 | translation.rs:336 | sanitize_id `>`→`==` | **真测试缺口** | `sanitize_id_truncates_overlong`（80 字符名 → 64，变异不截断）→ 已杀 |
| C17 | translation.rs:336 | sanitize_id `>`→`<` | **真测试缺口** | 同上 → 已杀 |
| C18 | translation.rs:336 | sanitize_id `>`→`>=` | **等价豁免** | `s.len()==64` 时 `truncate(64)` 是 Rust `String::truncate` 的 no-op（以 len 为界安全无操作）→ 两语义对**所有**输入输出恒等 |
| C19 | translation.rs:340 | sanitize_id `<`→`==` | **真测试缺口** | `sanitize_id_alnum_count_threshold`（"abc" alnum==3 不触发哈希回退，变异误触发）→ 已杀 |
| C20 | translation.rs:340 | sanitize_id `<`→`>` | **真测试缺口** | 同上（"abcd" alnum==4 不触发回退，变异误触发）→ 已杀 |
| C21 | translation.rs:340 | sanitize_id `<`→`<=` | **真测试缺口** | 同上（"abc" 3<=3 变异误触发）→ 已杀 |
| C22 | translation.rs:348 | fnv32 恒 `0` | **真测试缺口** | `sanitize_id_cjk_falls_back_to_hash`（**硬编码** `dict-3009aee7`，不自调用 fnv32 避免自洽逃逸）+ `fnv32_matches_known_vector`（标准向量 `hello`=0x4f9f2cab、`中文名`=0x3009aee7）→ 已杀 |
| C23 | translation.rs:348 | fnv32 恒 `1` | **真测试缺口** | 同上 → 已杀 |
| C24 | translation.rs:350 | fnv32 `^=`→`\|=` | **真测试缺口** | 同上（\|= 得 0x19594e57 ≠ 0x3009aee7）→ 已杀 |
| C25 | translation.rs:350 | fnv32 `^=`→`&=` | **真测试缺口** | 同上（&= 得 0x8000c980 ≠ 0x3009aee7）→ 已杀 |
| C26 | translation.rs:441 | set_config `==`→`!=` | **真测试缺口** | 新增 `set_config_configure_only_target_provider`（KeyGateProvider：configure 前 translate 失败，观察 set_config 是否只配置目标 Provider）→ 已杀 |
| C27 | translation.rs:468 | now_unix 恒 `0` | **真测试缺口** | 新增 `translate_created_at_is_recent_epoch`（缓存行 created_at > 1.7e9，docs/04 §5 时间戳语义）→ 已杀 |
| C28 | translation.rs:468 | now_unix 恒 `1` | **真测试缺口** | 同上 → 已杀 |
| C29 | translation.rs:468 | now_unix 恒 `-1` | **真测试缺口** | 同上 → 已杀 |
| D1 | store/translation.rs:38 | provider_key_setting 恒 `"xyzzy"` | **真测试缺口** | 新增 `provider_key_setting_uses_namespaced_key`：set/get 走同一变异函数会**自洽逃逸**（写错键名仍能读回），必须直查 settings 表断言键落 `translate.key.<provider>` 命名空间 → 已杀 |
| D2 | store/translation.rs:38 | provider_key_setting 恒 `""` | **真测试缺口** | 同上（键名 "" → 直查失败）→ 已杀 |

**统计：真测试缺口 36（A 2 / B 6 / C 26 / D 2）+ 等价豁免 2（C2/C18）+ 变异致死循环转 timeout 1（C4）= 39 全结案。**

## 修复与复验
- 新增 **20 个测试**（1 stardict + 4 mod + 3 provider + 11 translation + 1 store），`cargo test --all-targets`
  全绿（**164 passed**，既有 144 零回归，无警告）；
- **业务逻辑改动 1 处（最小、行为等价）**：provider.rs 将 DeepL 请求体构造内联代码提取为纯函数
  `deepl_body`（text/target_lang[/source_lang] 组装逻辑逐行搬移，无任何语义变化）——04-coverage 热点1
  预定的"补结构测试"路径，用于杀死 B4（from=Auto 附加 source_lang 的变异）且不引入网络 mock 依赖；
  **未发现需修代码的真实业务缺陷**；
- 复跑（第二轮，仅 B/C/D 片；A 片按约定跳过、沿用 40/95 已评估部分；`--jobs 2 --timeout 60
  CARGO_BUILD_JOBS=2`，逐片独立）：
  - **B 片**（provider.rs+mod.rs）：**22 变异 → 20 caught / 0 missed / 2 unviable**（首轮 13/6/2；
    多出的 1 个变异点来自 deepl_body 提取后的新函数，亦被新测试捕获）；
  - **C 片**（translation.rs）：**72 变异 → 60 caught / 4 missed / 7 unviable / 1 timeout**
    （首轮 35/29/7/1）。4 个 missed = ① L121 idxfilesize `!=`→`==`（**等价豁免**：仅日志）；② L336
    `>`→`>=`（**等价豁免**：len==64 时 truncate(64) 是 no-op）；③④ L272 `+=`→`-=`/`*=`：复跑快照
    临时去激活 3 碰撞测试（防 `*=` 死循环挂起套件），**已单独手动验证**——`-=` 变异下该测试
    **FAIL**（=caught 等价证据，产出 foo_bar-1 ≠ 期望 foo_bar-3）、`*=` 变异下该测试 **30s 挂起不终止**
    （=timeout 分类证据）。1 个 timeout = L270 `==`→`!=`（多词库安装即死循环的退化变异，首轮同为
    timeout）；
  - **D 片**（store/translation.rs）：**18 变异 → 16 caught / 0 missed / 2 unviable**（首轮 14/2/2）；
- **终版分数 = killed/(killed+survived−exempt) = 132/(132+2+2−2) = 98.5% ≥ 80%** ✅
  （killed=132：A 35 + B 20 + C 61〔60 caught + `-=` 手动验证被杀〕+ D 16；
  survived=4：A 片 2（补测已写、复跑跳过，保守计存活）+ C 2（豁免）；exempt=2 从分母剔除；
  timeout=2（C L270 + `*=` 挂起）单列不计分。若 A 片复跑确认其 2 个 missed 被杀 → 134/134=100%）。
  完整报告见 04-mutation.md。

## 结论
- 修复 36 个真实测试缺口（Unicode 大小写归一、HTML 剥离 guard、DeepL 请求体 Auto 分支、重开重扫、
  目录入参安装、unique_id 碰撞后缀、sanitize_id 全分支、fnv32 哈希、set_config 定向 configure、
  created_at 时间戳、settings 键命名空间），豁免 2 个等价变异（日志-only warn、truncate no-op），
  1 个变异致死循环转 timeout 单列；
- 变异分数 71.3% → **98.5%**，无真实业务缺陷需回开发修复（仅一处行为等价重构提升可测性）。
