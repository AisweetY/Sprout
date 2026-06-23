# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 项目概述

熊猫记账 (panda_ledger) — 个人记账与资产管理 Flutter App。替代随手记的自用应用，核心目标：「知道钱去哪了」+「持续存下钱」。

## 常用命令

```bash
# 安装依赖
cd panda_ledger && flutter pub get

# 代码生成（Drift .g.dart 文件）
cd panda_ledger && rm -rf .dart_tool/build && dart run build_runner build

# 静态分析
cd panda_ledger && flutter analyze

# 运行应用
cd panda_ledger && flutter run

# AI 智能记账：通过 Supabase Edge Function 代理调用（无需客户端 Key）
# 部署 Edge Function 后在 Supabase Secrets 中配置 DEEPSEEK_API_KEY 即可

# 查看依赖版本
cd panda_ledger && flutter pub outdated
```

**重要**: 使用 `dart run build_runner build`（不是 `flutter pub run build_runner build`）。修改任何表定义后必须重新运行代码生成。

## 技术栈

- **Flutter 3.44+** / **Dart 3.12+** / **Material 3**
- **Drift** (SQLite ORM) — 本地数据库，所有 UI 渲染的唯一数据源
- **Supabase** (PostgreSQL) — 云端同步备份，含认证 + RLS
- **Riverpod** — 响应式状态管理
- **fl_chart** — 趋势曲线和柱状图

## 架构：本地优先 (Local-First)

```
Flutter UI (Riverpod watch 本地DB → 即时渲染)
    ↓ 读/写
Drift/SQLite (唯一数据源，离线可用)
    ↓ 异步双向同步
Supabase/PostgreSQL (云端备份)
```

**核心原则**: 所有页面渲染仅读本地 Drift 数据库，不等待网络请求。写入操作先落本地库并立即更新 UI，再通过 `sync_queue` 异步推送 Supabase。

## 目录结构

```
lib/
├── core/                     # 主题、常量、工具、AI 识别服务
│   ├── theme/                # 语义化颜色（亮+暗双套）、字体层级
│   ├── services/
│   │   └── text_recognition/ # AI 文字记账：规则引擎 + Edge Function 代理 + 桩
│   │       └── models/       # ParsedTransaction 数据模型
│   ├── utils/                # ID 生成器、日期工具、分类图标解析、SnackBar 统一工具
│   └── widgets/              # 公共组件：RecordCard（流水卡片）、ShimmerLoading
├── data/
│   ├── local/                # Drift 表定义 + DAO + 数据库
│   │   ├── tables/           # 7 张表（含 sync_queue, sync_metadata, conflict_log）
│   │   └── dao/              # 每个表的数据访问对象（含 .g.dart 生成文件）
│   ├── remote/               # Supabase 客户端封装
│   ├── repository/           # 统一数据访问层（本地优先 + 同步逻辑）
│   └── sync/                 # 同步队列服务（push/pull/LWW/定时调度）
├── supabase/
│   ├── migrations/           # 数据库迁移（001_init → 002_sync_v2 → 003_ai_provider_configs）
│   └── functions/            # Edge Functions（ai-parse-record — AI 解析代理）
├── features/
│   ├── auth/                 # 邮箱登录/注册/登出 + 认证网关
│   ├── home/                 # 首页：净存款 + 储蓄目标 + 按天分组流水 + 同步状态
│   ├── record/               # 记账页：数字键盘 + 分类选择 + AI识别 + 一口气记账
│   ├── assets/               # 资产页：总资产 + 账户列表 + 趋势图
│   ├── insights/             # 分析页：文字结论 + 排行 + 月度对比
│   └── settings/             # 设置 + 账户管理 + 分类管理 + 预算 + 导出
└── main.dart                 # Supabase 初始化 + 主题切换 + AuthGate
```

## 数据库设计

### 核心表（5 张，同步到 Supabase）

| 表 | 关键字段 | 说明 |
|---|---|---|
| `accounts` | type, balance, is_liability, is_archived, deleted | 资产/负债账户 |
| `records` | type, amount, account_id, category_id, source, sync_status, deleted | 记账流水 |
| `categories` | name, parent_id, icon, kind, is_archived, deleted | 两级分类（支出/收入） |
| `budgets` | month, type, category_id, target_amount, deleted | 月度储蓄目标 + 分类预算 |
| `sync_queue` | operation_type, tbl_name, record_id, payload, retry_count | 仅本地 Drift，不上传 Supabase |

### 本地辅助表（2 张，仅 Drift）

| 表 | 说明 |
|---|---|
| `sync_metadata` | 键值存储：last_pull_at 游标 + initial_sync_done 标记 |
| `conflict_log` | LWW 冲突裁决日志（云端覆盖本地时记录） |

### 字段约定

- `records.type`: `expense` / `income` / `transfer` / `adjustment`
- `records.source`: `manual` / `text_ai` / `quick_button`
- `records.sync_status`: `pending` / `synced` / `conflict`
- `budgets.type`: `saving_goal` / `category_budget`
- 所有表含 `updated_at` 列（Drift + Supabase 双向维护），用于 LWW 冲突解决
- 软删除统一使用 `deleted` 布尔列，归档使用 `is_archived` 布尔列

### Supabase 迁移

| 文件 | 内容 |
|---|---|
| `supabase/migrations/001_init.sql` | 初始表结构 + `record_transaction()` RPC + RLS 策略 |
| `supabase/migrations/002_sync_v2.sql` | 为所有表新增 `deleted`/`updated_at` + updated_at 索引 + 重建 RLS |
| `supabase/migrations/003_ai_provider_configs.sql` | AI 多平台配置表 + 默认 DeepSeek 配置 |

### Edge Functions

| 函数 | 说明 |
|---|---|
| `ai-parse-record` | AI 智能记账解析代理：校验 JWT → 读配置表 → 查用户数据 → 调 AI → 返回结构化 JSON |

**部署**: `supabase functions deploy ai-parse-record`（需安装 Supabase CLI）
**配置**: 在 Supabase Dashboard → Edge Functions → Secrets 中添加 `DEEPSEEK_API_KEY=sk-xxx`

## 同步机制

### 推送 (Push) — `sync_queue_dao_provider.dart`

1. 本地写操作 → 入队 `sync_queue`（操作类型 + 表名 + 记录 ID + JSON payload）
2. 立即异步调用 `processQueue()` → 遍历队列逐条 UPSERT 到 Supabase（`onConflict: 'id'`）
3. 推送成功后本地 `sync_status` 标记为 `'synced'`，项目出队
4. 失败重试最多 5 次，超过后标记 `'conflict'` 并出队
5. 触达时机：每次写入后立即触发 + 应用启动 + 从后台恢复 + 每 5 分钟定时

### 拉取 (Pull) — `pullFromSupabase()`

1. 增量拉取：首轮全量，后续仅拉 `updated_at >= last_pull_at` 的记录
2. 拉取顺序：accounts → categories → records(limit 500 首轮) → budgets
3. LWW 冲突解决：`remote.updated_at >= local.updated_at` → 云端覆盖本地
4. 云端 `deleted=true` 的记录覆盖本地为软删除状态
5. 冲突日志写入 `conflict_log` 表

### 同步覆盖范围

所有四种实体类型（accounts / categories / records / budgets）均支持双向同步。
特别关注：
- 记录推送后会同步更新关联账户余额到 Supabase
- 预算的增/改/删/撤销重创均正确入队（v1 中遗漏，已修复）
- 归档/恢复操作均同步 `is_archived` 标志到 Supabase

## Provider 体系

- `appDatabaseProvider` → AppDatabase 单例（schemaVersion: 2）
- `accountDaoProvider` / `recordDaoProvider` / `categoryDaoProvider` / `budgetDaoProvider` → DAO 实例
- `syncQueueDaoProvider` / `syncQueueServiceProvider` → 同步队列与调度服务
- `accountRepositoryProvider` / `recordRepositoryProvider` → 聚合 DAO + 同步逻辑的数据访问层
- `currentUserIdProvider` → 当前登录用户 ID
- `seedServiceProvider` → 种子数据初始化服务
- 页面级 Provider（`homeDataProvider`, `assetsDataProvider`, `insightsDataProvider`）用 `FutureProvider`
- `allAccountsProvider` / `activeCategoriesProvider` / `allCategoriesProvider` → 列表数据自动刷新

## 统一工具

| 文件 | 用途 |
|---|---|
| `core/utils/IdGenerator` | UUID v4 生成（格式 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`） |
| `core/utils/snackbar_utils.dart` | 统一 SnackBar：`show()` / `showUndo()` / `showError()`，支持 `afterDialogClose` |
| `core/utils/category_icon_utils.dart` | 分类图标解析：DB 键 → Material IconData，含预设图标列表 |
| `core/utils/accessibility_utils.dart` | 无障碍：根据系统设置调整动画时长 |
| `core/widgets/record_card.dart` | 统一流水卡片组件（含同步状态指示 + 左滑删除） |
| `core/widgets/shimmer_loading.dart` | 骨架屏加载占位 |

## 开发注意事项

1. **代码生成必须跑**: 修改 `lib/data/local/tables/` 下的任何表定义后，需重新运行 `build_runner`
2. **Drift check 约束**: 使用 `column.isIn(const [...])`，不用 `.equals().or()`
3. **`Record` 命名冲突**: Dart 内置 `Record` 类型与 Drift 生成的 `Record` 类冲突。repository 中从 `database.dart` 导入时用 `import` 别名或前缀
4. **Value 类型**: Companion 类的可选字段用 `Value()` 包装，来自 `package:drift/drift.dart`；`parentId: Value.absentIfNull(value)` 用于可空字段
5. **Supabase 初始化**: 通过环境变量 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 配置（在 `main.dart`），默认值指向本地开发实例
6. **深色模式**: 所有颜色通过 `AppColors` 语义变量引用，禁止在 Widget 中硬编码颜色值
7. **自定义查询**: 使用 `db.customSelect()` 配合 `Variable.withString()` / `Variable.withDateTime()` 进行跨表聚合查询
8. **分类层级约束**: 最多两级（一级为 parent，二级为 child），`parentId` 为空的分类不可再有父级
9. **系统保留分类**: `'其他'`（支出）和 `'其他收入'`（收入）不可归档/删除
10. **SnackBar 使用**: 所有提示统一使用 `SnackbarUtils`，归档/删除的撤销提示必须传 `afterDialogClose: true`
11. **sync_queue 入队**: 本地写操作后必须立即入队 + 触发 `processQueue()`，不可遗漏任何一种实体类型
12. **build_runner 缓存**: 代码生成出问题时先 `rm -rf .dart_tool/build` 清除缓存再重试
