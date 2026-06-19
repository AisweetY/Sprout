# 熊猫记账 — 开发进展

> 最后更新: 2026-06-19

## 项目状态

| 指标 | 数值 |
|------|------|
| Dart 源文件 | 48 |
| 代码生成文件 | 83 |
| 编译错误 | 0 |
| 警告/建议 | 48（均为非关键） |
| Flutter 版本 | 3.44.2 |
| Dart 版本 | 3.12.2 |

## 已完成阶段

### ✅ 阶段一：基础架构

- Flutter 项目初始化 + 全部依赖配置（drift, supabase_flutter, riverpod, fl_chart）
- 主题系统：亮色/暗色双套 + 语义化颜色变量（`AppColors`）+ 字体层级（`AppTypography`）
- Drift 数据库：5 张表定义 + 5 个 DAO + 代码生成 pipeline
- Supabase 迁移脚本：完整建表 SQL + RLS 策略 + `record_transaction()` 原子化函数
- 邮箱认证流程：AuthGate → AuthScreen → Supabase Auth（登录/注册/密码重置）
- 同步框架：本地优先架构，SyncQueue 队列管理，启动增量拉取 + 写入后台推送
- 应用外壳：4 Tab 底部导航 + 中央 FAB「记一笔」

### ✅ 阶段二：核心记账闭环

- **账户管理**：创建/编辑/归档，按类型分组（现金/储蓄卡/信用卡/贷款/投资），余额手动校正
- **分类管理**：支出/收入双 Tab，一二级分类，添加/编辑/归档
- **完整记账页**：
  - 数字键盘（最小 48dp 点击热区）
  - 分类网格（一级 + 二级联动）
  - 账户选择器
  - 备注输入（选填）
  - 日期选择（补记 30 天内）
  - 常用金额快捷按钮
  - 确认反馈动画（缩放 + 淡出，2 秒自动消失）
- **AI 文字识别**：
  - 本地规则引擎（正则提取金额/时间词/场景词，50ms 内完成）
  - AI 服务抽象接口（`IAiParsingService`）
  - 桩实现（当前版本暂不接入云端 LLM）
  - 确认卡片 UI（每个字段可手动修改，建议新增分类需用户采纳）
- **种子数据**：首次启动自动创建 8 个支出分类 + 4 个收入分类 + 约 20 个二级分类

### ✅ 阶段三：首页+资产+分析

- **首页**：
  - 净存款大字展示（数字滚动动画）
  - 月度储蓄目标进度条（动态填充动画）
  - 本月收支 MiniLabel
  - 净资产卡片
  - Top5 支出分类（条形图 + 排名 + 金额）
  - 下拉刷新
- **资产页**：
  - 总资产/总负债/净资产数字滚动动画
  - 账户列表按类型分组（emoji + 金额）
  - 净资产趋势曲线（fl_chart 平滑曲线，最新数据点高亮，支持 3/6/12 月切换）
- **分析页**：
  - 自动文字结论引擎（基于规则的月度小结，置于页面顶部）
  - 月度概览（收入/支出/储蓄率三栏）
  - 分类排行横向柱状图（固定色彩映射）
  - 月度环比对比（上月/本月变化量）
  - 月份前后切换

## 待完成

### ✅ 阶段四：预算 + 导出 + 打磨

- **预算设置页面**（`budget_settings_screen.dart`）：
  - 月份前后切换（参考 insights 页面模式）
  - 月度储蓄目标编辑（BottomSheet 数字输入 + 保存/删除）
  - 分类预算上限列表（按支出分类逐行设置，实时进度条 + 超支红色标记）
  - MaterialBanner 超支提示横幅
  - 空状态引导卡片
- **预算数据 Provider**（`budget_settings_provider.dart`）：
  - `BudgetParams` 年月参数 + `FutureProvider.family`
  - 多表联查：储蓄目标 + 支出分类 + 当月支出 + 分类预算
  - `CategoryBudgetData` 聚合模型
- **数据导出**（`export_service.dart`）：
  - CSV 导出：流水 + 账户 + 分类三区段，`csv` 包生成
  - JSON 导出：结构化全量数据，`dart:convert` 序列化
  - 系统分享菜单：`share_plus` → `Share.shareXFiles()`
  - 临时文件命名：`panda_ledger_export_yyyyMMdd_HHmmss`
- **Provider 补充**：`budgetDaoProvider` 加入 `app_database_provider.dart`
- **设置页完善**：CSV/JSON 导出 + 预算页面入口全部接通，错误 SnackBar 提示
- **新增依赖**：`share_plus: ^10.1.4`、`csv: ^6.0.0`
- **Supabase 集成完善**：
  - 同步服务 `processQueue()` 实际推送逻辑（records/accounts/categories/budgets 四表）
  - 增量拉取 `pullFromSupabase()` — 应用启动时从 Supabase 同步数据到本地
  - 失败重试（最多 5 次）+ 冲突标记
  - `SupabaseClientWrapper` 清理去重
- **userId 统一**：所有 `'local'` 占位符替换为 `currentUserIdProvider`（未登录回退 'local'）
- **体验打磨**：
  - 记账页：无分类时显示 "请先在设置中创建分类" 引导
  - 资产页：无账户时显示空状态引导卡片
  - 预算页：空状态引导设置储蓄目标

### ✅ 阶段四全部完成

阶段四 5 项任务全部实现：预算设置页面 + 数据导出 + 设置页完善 + Supabase 联调代码 + 体验打磨。

### 🔲 后续版本（V2+）

| 功能 | 说明 |
|------|------|
| AI 云端接入 | 替换桩实现，连接 Claude API 做语义解析 |
| Widget 组件 | iOS/Android 桌面小组件 |
| 净资产历史快照 | `net_worth_snapshots` 表 + 自动快照任务 |
| 多设备同步 | Supabase Realtime 推送 |

## 关键文件索引

| 模块 | 路径 |
|------|------|
| 入口 | `lib/main.dart` |
| 主题 | `lib/core/theme/app_theme.dart` |
| 数据库 | `lib/data/local/database.dart` |
| 表定义 | `lib/data/local/tables/*.dart` |
| DAO | `lib/data/local/dao/*.dart` |
| Repository | `lib/data/repository/*.dart` |
| 同步服务 | `lib/data/sync/sync_queue_dao_provider.dart` |
| 规则引擎 | `lib/core/services/text_recognition/rule_engine.dart` |
| AI 接口 | `lib/core/services/text_recognition/ai_service_interface.dart` |
| 认证 | `lib/features/auth/` |
| 首页 | `lib/features/home/` |
| 记账页 | `lib/features/record/` |
| 资产页 | `lib/features/assets/` |
| 分析页 | `lib/features/insights/` |
| 设置 | `lib/features/settings/` |
| 预算设置 | `lib/features/settings/budget_settings_screen.dart` |
| 预算 Provider | `lib/features/settings/budget_settings_provider.dart` |
| 导出服务 | `lib/features/settings/export_service.dart` |
| Supabase 迁移 | `supabase/migrations/001_init.sql` |
| 需求文档 | `熊猫记账_产品需求文档 (1).docx` |
