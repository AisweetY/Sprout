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

# 运行应用（不含 AI）
cd panda_ledger && flutter run

# 运行应用（含 DeepSeek AI 智能记账 — 需自行获取 API Key）
cd panda_ledger && flutter run --dart-define=DEEPSEEK_API_KEY=sk-xxx

# 查看依赖版本
cd panda_ledger && flutter pub outdated
```

**重要**: 使用 `dart run build_runner build`（不是 `flutter pub run build_runner build`）。修改任何表定义或 DAO 后必须重新运行代码生成。

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

**核心原则**: 所有页面渲染仅读本地 Drift 数据库，不等待网络请求。写入操作先落本地库并立即更新 UI，再异步推送 Supabase。

## 目录结构

```
lib/
├── core/               # 主题、常量、工具、AI 识别服务
│   ├── theme/          # 语义化颜色（亮+暗双套）、字体层级
│   ├── services/text_recognition/  # AI 文字记账：规则引擎 + AI 接口 + 桩
│   └── utils/          # ID 生成器、日期工具
├── data/
│   ├── local/          # Drift 表定义 + DAO + 数据库
│   │   ├── tables/     # Accounts, Records, Categories, Budgets, SyncQueue
│   │   └── dao/        # 每个表的数据访问对象
│   ├── remote/         # Supabase 客户端封装
│   ├── repository/     # 统一数据访问层（本地优先+同步逻辑）
│   └── sync/           # 同步队列管理
├── features/
│   ├── auth/           # 邮箱登录/注册/登出 + 认证网关
│   ├── home/           # 首页：净存款 + 储蓄目标 + Top5支出
│   ├── record/         # 记账页：数字键盘 + 分类 + AI识别
│   ├── assets/         # 资产页：总资产 + 账户列表 + 趋势图
│   ├── insights/       # 分析页：文字结论 + 排行 + 月度对比
│   └── settings/       # 设置 + 账户管理 + 分类管理
└── main.dart           # Supabase 初始化 + 主题切换 + AuthGate
```

## 数据库关键设计

5 张核心表：`accounts`, `records`, `categories`, `budgets`, `sync_queue`（仅本地）

- `records.type`: expense / income / transfer / adjustment
- `records.source`: manual / text_ai / quick_button（追踪记账来源）
- `records.sync_status`: pending / synced / conflict
- `sync_queue` 仅本地 Drift，不上传 Supabase
- 转账户类型走 RPC function `record_transaction()` 保证原子性

完整 Supabase 迁移脚本见 `supabase/migrations/001_init.sql`。

## Provider 模式

所有 DAO 通过 Riverpod Provider 暴露：

- `appDatabaseProvider` → AppDatabase 单例
- `categoryDaoProvider` → CategoryDao（在 `app_database_provider.dart`）
- `accountDaoProvider` / `recordDaoProvider` → 在各自 repository 文件中
- `syncQueueServiceProvider` → 同步队列服务
- 页面级 Provider（`homeDataProvider`, `assetsDataProvider`, `insightsDataProvider`）用 `FutureProvider`

## 开发注意事项

1. **代码生成必须跑**: 修改 `lib/data/local/tables/` 下的任何表定义后，需重新运行 `build_runner`
2. **Drift check 约束**: 使用 `column.isIn(const [...])`，不用 `.equals().or()`
3. **`Record` 命名冲突**: Dart 内置 `Record` 类型与 Drift 生成的 `Record` 类冲突。repository 中从 `database.dart` 导入时用前缀或 import 别名
4. **Value 类型**: Companion 类的可选字段用 `Value()` 包装，来自 `package:drift/drift.dart`
5. **Supabase 初始化**: 通过环境变量 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 配置（在 `main.dart`），默认值指向本地开发实例
6. **深色模式**: 所有颜色通过 `AppColors` 语义变量引用，禁止在 Widget 中硬编码颜色值
7. **自定义查询**: 使用 `db.customSelect()` 配合 `Variable.withString()` 进行跨表聚合查询
