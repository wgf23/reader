<!-- wf-meta: req=REQ-003 | phase=testing | agent=test-engineer | date=2025-08-31 | gate=passed -->
# REQ-003 · 覆盖率报告（阶段4）

## 数据（cargo llvm-cov 0.9，`cargo llvm-cov --workspace`，2025-08-31；初测，变异阶段补测后更新终版）

| 口径 | 行覆盖 | 说明 |
|---|---|---|
| 全部文件 | 3939/5210（75.6%） | 含 frb_generated（0%）与 api.rs（cargo 视角 57.1%） |
| 排除生成代码 frb_generated | 3939/4325（91.1%） | |
| 排除生成代码 + api.rs（桥接胶水，FFI 端到端覆盖，REQ-001/002 先例豁免） | 3827/4129（92.7%） | |
| **REQ-003 新增代码（dict/stardict.rs + dict/provider.rs + dict/translation.rs + dict/mod.rs + store/translation.rs + types.rs REQ-003 契约段）** | **1457/1597（91.2%）** | **门槛 ≥85% ✅** |

### REQ-003 新增/相关文件逐文件行覆盖

| 文件 | 行覆盖 | 说明 |
|---|---|---|
| dict/stardict.rs | 312/326（95.7%） | StarDict 解析内核（.ifo/.idx/二分+归一查词/parse_entry/take_field/.dz 解压）；未覆盖为防御分支 |
| dict/provider.rs | 109/139（78.4%） | DeepL 网络错误路径闭包（into_json 解析失败/缺 translations[0].text）、Default impl、deepl_code 未用语言码臂（见热点 1/2） |
| dict/translation.rs | 744/829（89.7%） | DictService（安装/移除/查词/扫描）+ TranslationService（缓存优先编排）；未覆盖为启动扫描/目录安装/防御分支（见热点 3/4） |
| dict/mod.rs | 24/25（96.0%） | DictEntry/DictInfo/trait/extract_pos/strip_html_tags；未覆盖 1 行为空行 continue 防御分支 |
| store/translation.rs | 243/245（99.2%） | TranslationRepo（get/put UPSERT/incr_hit/clear/count + settings 读写 + v2→v3 迁移） |
| types.rs（REQ-003 契约段 L65-177） | 25/33（75.8%） | Lang 枚举码 as_str 未用臂（Auto/Ja/Ko/Fr/De/Es/Ru/Other，见热点 2）；parse/Serialize/Deserialize 已全覆盖 |
| api.rs（新增 7 个 async 桥接，cargo 视角） | 112/196（57.1%） | 桥接胶水层：REQ-001/002 先例豁免口径（FFI 端到端 `rust_bridge_test.dart` + `translate_corpus.rs::api_bridge_dict_translate_cache_full_chain` 覆盖新桥接函数），不计入本闸门口径 |

## 未覆盖热点与结论

1. **provider.rs DeepL 网络错误路径（~10 行，L53-59/62-66）**：`resp.into_json()` 解析失败与
   `translations[0].text` 缺失的 `Error::Network` 闭包 —— 仅真实 HTTP 往返可达；ureq blocking 无内置
   mock，测试不真发网络（`deepl_configured_builds_request_without_network` 只断言错误变体为 Network）。
   → 防御性错误路径，变异阶段按"无网络 mock、尽力而为降级线（01-req §5 风险7 对齐 REQ-002 Huff 先例）"
   论证豁免或补结构测试（若变异存活需结论）。
2. **语言码封闭集臂（types.rs L90/93-99 + provider.rs deepl_code L98/101-107，~17 行）**：
   `Lang::as_str`/`deepl_code` 的 Auto/Ja/Ko/Fr/De/Es/Ru/Other 臂未被执行（测试只用 en/zh）。
   属封闭枚举的"别名映射"，US-17 桥接契约的 `Lang::parse` 反方向已全覆盖 → 补一个全码
   as_str↔parse 往返单测即可闭合（变异阶段一并处理）。
3. **dict/translation.rs 启动扫描（L59-62/67-86，scan_existing/load_from_installed_dir）**：无测试
   覆盖"重开服务后已装词库被重新注册"（US-7 的安装持久化语义；真实产品重启后 dict_list 必须含
   既有词库）。→ **真测试缺口**，变异阶段补 `DictService::new` 重扫测试。
4. **dict/translation.rs 防御/边缘分支（~20 行）**：install 的目录入参分支（L92-93）、缺 .idx（L111）/
   缺 .dict（L132-133）/idxfilesize 不一致 warn（L122）、lookup dict_id 不存在 → NotFound（L200）、
   sanitize_id 空名/哈希回退（L334/339-342）、空文本翻译 → Err（L387）、`attempted==0` 死分支（L238）、
   unique_id 撞 id（L271）—— 多数为便宜可测边缘，变异阶段逐条判定（补测或等价论证）。
5. **既有非本 REQ 缺口**（error.rs From<rusqlite>、format/mod.rs 未实现格式臂、tts 33.3%、api.rs 既有
   函数）：属其他 REQ/既有代码，不在本 REQ 新代码口径内，不阻塞本闸门（与 REQ-001/002 报告口径一致）。

## 闸门4 自评（覆盖部分）
- [x] 新代码行覆盖率 ≥ 85%（**91.2%** = 1457/1597；dict 五文件 + types 契约段；api.rs 桥接按先例
  豁免口径单列）
- [x] 关键分支（错误路径/边界）已覆盖：坏词库（截断 idx/缺 wordcount/偏移越界 → Corrupt 不 panic）、
  .dz 解压（含截断 gzip 流）、tgm/tgmx/旧格式/未知类型码解析、大小写归一查词、多词库安装序、幂等安装、
  移除回落 US-3、缓存命中计数/语言对/Provider 区分、失败不写缓存、清空重翻、v2→v3 迁移存量不丢、
  ≥1000 行缓存命中 ≤100ms、100 次查词 ≤200ms（US-8/14 基准）
- [ ] 剩余未覆盖热点（1-4）在变异阶段逐条给结论（补测或等价豁免），见 04-mutation.md
