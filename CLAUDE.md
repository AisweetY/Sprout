# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
│   ├── category_dedup_service.dart  # 分类去重服务（启动时自动合并重名分类）
│   ├── local/                # Drift 表定义 + DAO + 数据库
│   │   ├── tables/           # 7 张表（含 sync_queue, sync_metadata, conflict_log）
│   │   └── dao/              # 每个表的数据访问对象（含 .g.dart 生成文件）
│   ├── remote/               # Supabase 客户端封装
│   ├── repository/           # 统一数据访问层（本地优先 + 同步逻辑）
│   └── sync/                 # 同步队列服务（push/pull/LWW/定时调度）
├── supabase/
│   ├── migrations/           # 数据库迁移（001→006，见下方迁移表）
│   └── functions/            # Edge Functions（ai-parse-record / redeem-code）
├── features/
│   ├── auth/                 # 邮箱登录/注册/登出 + 认证网关
│   ├── home/                 # 首页：净存款 + 储蓄目标 + 按天分组流水 + 同步状态
│   ├── record/               # 记账页：数字键盘 + 分类选择 + AI识别 + 一口气记账
│   ├── assets/               # 资产页：总资产 + 账户列表 + 趋势图
│   ├── insights/             # 分析页：文字结论 + 排行 + 月度对比
│   ├── membership/           # 会员页：SKU 展示 + 兑换码 + 状态查询
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
| `001_init.sql` | 初始表结构 + `record_transaction()` RPC + RLS 策略 |
| `002_sync_v2.sql` | 为所有表新增 `deleted`/`updated_at` + updated_at 索引 + 重建 RLS |
| `003_ai_provider_configs.sql` | AI 多平台配置表 + 默认 DeepSeek 配置 |
| `004_budget_unique_constraints.sql` | 预算部分唯一索引：同月同类型/同分类只能有一条活跃记录 |
| `005_membership.sql` | 会员体系：`membership_skus` / `memberships` / `orders` + `grant_membership()` RPC |
| `006_redemption_codes.sql` | 兑换码：`redemption_codes` 表（RLS 全拒客户端，只有 Edge Function 可操作） |

### Edge Functions

| 函数 | 说明 |
|---|---|
| `ai-parse-record` | AI 智能记账解析代理：校验 JWT → 读配置表 → 查用户数据 → 调 AI → 返回结构化 JSON |
| `redeem-code` | 兑换码核销：校验 JWT → 查码状态 → 调 `grant_membership()` → 标记已用 |

**部署**: `supabase functions deploy <function-name>`（需安装 Supabase CLI）
**配置**: Supabase Dashboard → Edge Functions → Secrets 中添加 `DEEPSEEK_API_KEY=sk-xxx`

## 会员体系

### 档位（membership_skus）

| sku_code | 名称 | 时长 |
|---|---|---|
| `monthly_30` | 月度会员 | 30 天 |
| `yearly_365` | 年度会员 | 365 天 |
| `lifetime` | 永久会员 | 永久（expires_at = null） |

### 核心规则

- **memberships 每用户一条**（PK = user_id），UPSERT 处理续费叠加（未过期时在原到期日累加）
- **开通/续费唯一入口**：`grant_membership(user_id, sku_code, source, ref_id)` RPC，SECURITY DEFINER，客户端无法直接写入
- **兑换码**（`redemption_codes`）：格式 `PANDA-XXXX-XXXX`，状态 `unused/used/disabled`，仅 Edge Function 通过 service_role 操作
- **orders** 表记录支付流水（channel: alipay/wechat/xunhu/iap/redeem），阶段三接支付时填充

### Flutter 侧

- `membershipProvider` — 会员状态 StateNotifier，启动时 + 从后台恢复时刷新
- `membershipGuard` / `requireMembership()` — 付费功能门禁（弹付费墙）
- AI 批量记账、其他付费功能在调用前通过 `requireMembership()` 验证

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
- 预算的增/改/删/撤销重创均正确入队
- 归档/恢复、软删除操作均同步对应字段到 Supabase

### 启动流程（`app_shell.dart` → `_initialize()`）

```
1. pullFromSupabase()          — 拉取云端增量数据
2. seedService.seed()          — 新用户初始化种子数据（首次且 pull 后无数据时）
2.5 categoryDedupService       — 自动合并重名分类（见下方分类管理）
3. processQueue()              — 推送本地离线期间积累的变更
3.5 reconcileOnStartup()       — 一致性对账（修复 conflict 记录）
4. startPeriodicSync()         — 启动后台 5 分钟定时同步
5. membershipProvider.refresh() — 刷新会员状态
```

## 分类管理规则

### 层级与约束

- 最多两级（一级 parent，二级 child），`parentId` 为空的分类不可再有父级
- `kind` 字段：`expense`（支出）/ `income`（收入），每个分类必须属于某种类型
- **同层级不允许重名**：新建/编辑时通过 `CategoryDao.existsByName()` 校验
  - 一级分类：同 `kind` 下 `name` 唯一（`parentId IS NULL`）
  - 二级分类：同 `parentId` 下 `name` 唯一（不同父级可同名）

### 系统保留分类

- `'其他'`（支出）和 `'其他收入'`（收入）为系统保留分类
- **唯一时**不可归档/删除；**出现重名时**（历史脏数据）允许归档多余的那个
- 判断逻辑：`existsByName(name, kind, excludeId: self.id)` → 有重名则放行

### 自动去重（`CategoryDedupService`）

- 位置：`lib/data/category_dedup_service.dart`，Provider：`categoryDedupServiceProvider`
- 触发时机：应用每次启动（`_initialize()` 步骤 2.5），无重复时仅一次 SQL 查询
- 保留策略：同 kind+name 下按 `updated_at ASC` 保留最早的一个
- 合并流程：迁移多余分类的**子分类**（更新 `parent_id`）+ **流水**（更新 `category_id`）→ 软删除多余分类 → 所有变更入同步队列
- 公开方法：
  - `deduplicateOnce()` — 自动去重（含子分类迁移）
  - `mergeRecords(from, into)` — 只迁移流水 + 软删除（不碰子分类，供归档流程用）
  - `softDeleteCategory(category)` — 软删除 + 入队

### 归档智能判断链

**归档二级分类时：**

```
查分类下流水数量
  ├─ 无流水 → 弹「直接删除」确认（软删除，不进归档列表）
  └─ 有流水 → 查可迁移目标（同名一级 + 同名二级都要匹配）
               ├─ 找到目标 → 弹「迁移并删除 / 仅归档 / 取消」三选一
               └─ 未找到   → 弹正常归档确认（is_archived = true）
```

**归档一级分类时：**

```
子分类：各自独立走「归档二级分类」判断链（不跟着父类批量决策）
一级分类本身：同上流程
全部分析完成后：
  ├─ 全部都是正常归档 → 弹简洁确认弹窗（原逻辑）
  └─ 有删除/迁移操作  → 弹「处理计划预览」（列出每个分类的处理结果）→ 用户确认后批量执行
```

**可迁移目标判断规则**（`CategoryDao.findMergeTarget()`）：

- 一级分类：同 `kind+name` 的其他活跃（未归档未删除）一级分类
- 二级分类：**父级同名 + 自身同名**都要匹配（即一级名和二级名同时一样才算可迁移）

### 已归档列表功能

- **一键清理**（AppBar 扫帚图标）：批量软删除无流水的归档分类
- **每个 tile 异步检测**（`_ArchivedCategoryTile` 在 initState 查流水数量 + 迁移目标）：
  - 无流水 → 「恢复」+「🗑️删除」
  - 有流水 + 发现同名可迁移目标（归档后新建的同名分类也算）→ 「恢复」+「迁移并删除」
  - 有流水 + 无迁移目标 → 仅「恢复」

## Provider 体系

- `appDatabaseProvider` → AppDatabase 单例（schemaVersion: 2）
- `accountDaoProvider` / `recordDaoProvider` / `categoryDaoProvider` / `budgetDaoProvider` → DAO 实例
- `syncQueueDaoProvider` / `syncQueueServiceProvider` → 同步队列与调度服务
- `categoryDedupServiceProvider` → 分类去重服务（依赖 AppDatabase + SyncQueueService）
- `accountRepositoryProvider` / `recordRepositoryProvider` → 聚合 DAO + 同步逻辑的数据访问层
- `currentUserIdProvider` → 当前登录用户 ID
- `seedServiceProvider` → 种子数据初始化服务
- `membershipProvider` → 会员状态 StateNotifier
- `categoriesStreamProvider` / `allCategoriesStreamProvider` → 分类实时流（StreamProvider，自动响应 DB 变更）
- `monthlyRecordsStreamProvider` → 月度流水实时流
- 页面级 Provider（`homeDataProvider`, `assetsDataProvider`, `insightsDataProvider`）用 `FutureProvider`

## CategoryDao 关键方法

| 方法 | 说明 |
|---|---|
| `existsByName(name, kind, {parentId, excludeId})` | 重名校验：同层级是否已有同名未删除分类 |
| `findMergeTarget(category)` | 查可迁移目标（一级：同名活跃一级；二级：父级同名+自身同名） |
| `getRecordCount(categoryId)` | 查分类下的未删除流水数量 |
| `getSubCategories(parentId)` | 查子分类列表 |
| `archiveCategory(id)` / `unarchiveCategory(id)` | 归档/取消归档 |
| `softDeleteCategory(id)` | 软删除（deleted=true，不可从 UI 恢复） |
| `moveCategory(childId, newParentId)` | 更换子分类的父级 |

## 统一工具

| 文件 | 用途 |
|---|---|
| `core/utils/IdGenerator` | UUID v4 生成（格式 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`） |
| `core/utils/snackbar_utils.dart` | 统一 SnackBar：`show()` / `showUndo()` / `showError()`，支持 `afterDialogClose` |
| `core/utils/category_icon_utils.dart` | 分类图标解析：DB 键 → Material IconData，含预设图标列表 |
| `core/utils/accessibility_utils.dart` | 无障碍：根据系统设置调整动画时长 |
| `core/widgets/record_card.dart` | 统一流水卡片组件（含同步状态指示 + 左滑删除） |
| `core/widgets/shimmer_loading.dart` | 骨架屏加载占位 |
| `data/category_dedup_service.dart` | 分类去重：自动合并重名分类 + 归档流程的迁移/软删除工具方法 |

## 开发注意事项

1. **代码生成必须跑**: 修改 `lib/data/local/tables/` 下的任何表定义后，需重新运行 `build_runner`
2. **Drift check 约束**: 使用 `column.isIn(const [...])`，不用 `.equals().or()`
3. **`Record` 命名冲突**: Dart 内置 `Record` 类型与 Drift 生成的 `Record` 类冲突。repository 中从 `database.dart` 导入时用 `import` 别名或前缀
4. **`Category` 命名冲突**: `flutter/foundation.dart` 里有 `@Category` 注解，与 Drift 生成的 `Category` 数据类冲突。需 `import 'package:flutter/foundation.dart' hide Category;`
5. **Value 类型**: Companion 类的可选字段用 `Value()` 包装，来自 `package:drift/drift.dart`；`parentId: Value.absentIfNull(value)` 用于可空字段
6. **Supabase 初始化**: 通过环境变量 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 配置（在 `main.dart`），默认值指向本地开发实例
7. **深色模式**: 所有颜色通过 `AppColors` 语义变量引用，禁止在 Widget 中硬编码颜色值
8. **自定义查询**: 使用 `db.customSelect()` 配合 `Variable.withString()` / `Variable.withDateTime()` 进行跨表聚合查询
9. **分类层级约束**: 最多两级（一级为 parent，二级为 child），`parentId` 为空的分类不可再有父级
10. **系统保留分类**: `'其他'`（支出）和 `'其他收入'`（收入）唯一时不可归档/删除；出现重名（历史脏数据）时允许归档多余的那个
11. **分类重名校验**: 新建/编辑分类时必须调用 `existsByName()` 校验，同层级不允许同名
12. **SnackBar 使用**: 所有提示统一使用 `SnackbarUtils`，归档/删除的撤销提示必须传 `afterDialogClose: true`
13. **sync_queue 入队**: 本地写操作后必须立即入队 + 触发 `processQueue()`，不可遗漏任何一种实体类型；软删除、归档、迁移操作同样需要入队
14. **build_runner 缓存**: 代码生成出问题时先 `rm -rf .dart_tool/build` 清除缓存再重试
15. **Drift & Flutter 完整导入**: 需要 Drift 表达式的 `&` 运算符时必须 `import 'package:drift/drift.dart'`（不能仅 `show Value`），否则 `Expression<bool>` 的 `&` 不可用
