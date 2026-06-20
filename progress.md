# 熊猫记账 — 项目进展

> 最后更新：2026-06-20

## 当前版本

**v1.0.1**（基于 v1.0.0 的 bug 修复 + 功能增强）

## 技术栈

Flutter 3.44+ / Dart 3.12+ / Material 3 / Drift (SQLite) / Supabase (PostgreSQL) / Riverpod

## 架构

```
Flutter UI (Riverpod watch 本地DB → 即时渲染)
    ↓ 读/写
Drift/SQLite (唯一数据源，离线可用)
    ↓ 异步双向同步
Supabase/PostgreSQL (云端备份)
```

## 已实现功能

### 5 个 Tab 页面
| 页面 | 功能 |
|---|---|
| **首页** | 净存款卡片、储蓄目标进度条、净资产行、按天分组的当月流水（点击查看详情、左滑删除）、"查看全部"跳转历史流水 |
| **资产** | 总资产/总负债/净资产、按类型分组账户列表、多维度趋势图（日/周/月/年/自定义） |
| **分析** | 多时间维度（日/周/月/年/自定义）、收支汇总、环比对比、分类排行、文字结论 |
| **记一笔** | 数字键盘、支出/收入/转账三 Tab、二级分类选择、账户选择、日期选择、AI 智能记账、编辑模式 |
| **设置** | 账户管理、分类管理、预算与储蓄目标、CSV/JSON 导出、清空所有数据、登出 |

### 底部三区记账卡片（仅首页显示）
- 左：「记一笔收支」→ 跳转记账页
- 中：绿色麦克风悬浮按钮（高于卡片，白色描边，语音识别开发中）
- 右：「一口气记账」→ AI 批量录入

### 历史流水页
- 备注关键字搜索
- 时间范围 / 分类 / 账户组合筛选
- 按天分组倒序展示
- 分页加载（滚动到底触发）+ 下拉刷新
- 点击编辑（复用记一笔表单）
- 左滑删除（二次确认）

### 一口气记账（批量录入）
- 输入一段含多笔收支的文字 → AI 自动拆分识别
- 识别结果以卡片列表呈现
- 卡片交互：点击编辑 / 左滑删除 / 长按拖拽排序
- 批量保存（每条独立 ID，走 verified 写入链路）

### 数据同步
- 本地优先写入 → SnackBar 即时反馈 → 异步推送 Supabase
- 同步链路埋点日志（节点 1-4）
- 推送时同步更新 Supabase 账户余额
- 应用启动时从 Supabase 增量拉取
- 支持 insert / update / delete 三种同步操作

## v1.0.1 修复与改动（相对于 v1.0.0）

### P0 — 严重 Bug
| # | 问题 | 修复 |
|---|---|---|
| 1 | **日期查询类型不匹配**：`customSelect` 用 ISO8601 字符串与 INTEGER 毫秒时间戳比较，聚合结果恒为 0 | 所有 `Variable.withString(date.toIso8601String())` → `Variable.withDateTime(date)`；`strftime`/`DATE` 增加 `/1000, 'unixepoch'` 修饰符（6 个文件 17 处） |
| 2 | **分类未同步到 Supabase**：种子分类和手动创建分类不入 sync_queue，导致带分类记账时 Supabase 外键失败 | seed_service 和 category_manage_screen 增删分类均入队同步 |

### P1 — 高优先级
| # | 问题 | 修复 |
|---|---|---|
| 3 | **无默认账户**：新用户无账户，记账被校验拦截 | seed_service 自动创建「现金」账户并同步 |
| 4 | **推送不更新远端余额**：流水同步后 Supabase 账户余额不变 | `_pushRecord` 新增 `_syncAccountBalance`，推送后同步更新 Supabase 账户余额（含转账双账户） |
| 5 | **归档分类 Toast 不消失** | `addPostFrameCallback` 延迟 + `clearSnackBars` + `dismissDirection` |

### P1 — 功能优化
| # | 改动 | 说明 |
|---|---|---|
| 6 | **首页改版**：分类排行 → 按天分组流水 | 新增 DailyRecordGroup/RecordItem 数据模型、联表查询（records+categories+accounts）、按天 Card 展示、点击弹详情窗、左滑删除 |
| 7 | **分类为空默认归入「其他」** | 记账提交时自动查「其他」/「其他收入」填入；分类管理禁止归档这两个系统保留分类 |
| 8 | **历史流水页**（新建） | 搜索/筛选/分页/编辑/删除 |
| 9 | **记账入口改版** + 一口气记账 | FAB → 三区卡片（仅首页显示）；批量 AI 解析 + 卡片交互 + 批量保存 |
| 10 | **编辑/删除记录** | record_screen 支持编辑模式；record_repository 增加 updateRecord/deleteRecord（含余额撤销重算）；同步队列支持 delete |

### P2 — 功能优化
| # | 改动 | 说明 |
|---|---|---|
| 11 | **清空所有数据** | 设置页新增入口，二次确认后清空本地 5 表 + Supabase 远端对应数据，自动重建种子数据 |

## 数据库结构

5 张核心表（Drift 本地）+ sync_queue（仅本地）：

| 表 | 关键字段 |
|---|---|
| `accounts` | id, user_id, name, type, balance, currency, is_liability, include_in_net, is_archived |
| `records` | id, user_id, account_id, to_account_id, amount, type, category_id, note, occurred_at, source, sync_status |
| `categories` | id, user_id, name, parent_id, icon, kind, is_archived |
| `budgets` | id, user_id, month, type, category_id, target_amount |
| `sync_queue` | id, operation_type, tbl_name, record_id, payload, retry_count (仅本地) |

## 关键设计决策

- **userId 统一**：未登录回退 `'local'`（`currentUserIdProvider`）
- **分类层级**：最多两级（一级 → 二级），UI 上通过底部弹窗选择二级分类
- **系统保留分类**：「其他」（支出）和「其他收入」（收入）不可归档
- **ID 生成**：`IdGenerator.generate()` 基于 UUID v4，碰撞重试最多 3 次
- **转账处理**：`records.type = 'transfer'`，不扣分类，to_account_id 记录对方账户
- **余额调整**：`records.type = 'adjustment'`，amount 存差值绝对值，note 记录前后余额

## 仍待完善

| 优先级 | 事项 |
|---|---|
| P1 | 语音识别接入（三区卡片中间按钮已预留，当前仅 Toast 提示"开发中"） |
| P2 | Supabase RPC `record_transaction()` 原子记账（当前分步 insert + update balance） |
| P2 | 离线同步冲突处理 UI（当前队列超限重试后标 conflict 静默移除） |
| P2 | 转账场景远端双账户余额同步（`_syncAccountBalance` 已支持 to_account_id） |
| P3 | 预算超限提醒通知 |
| P3 | 分类图标自定义（当前固定映射） |
| P3 | 深色模式手动切换（当前跟随系统） |
