# 🐼 熊猫记账 UI/UX 优化方案

> 最后更新：2026-06-19 ｜ 进度：P0 ✅ P1 ✅ P2 8/11 ✅ → 剩余 3 项

## 状态说明

- ✅ 已完成（19 项）
- 🔴 待实施（13 项）
- ~~已覆盖~~（由前置阶段完成，不计入本阶段工作量）

| 阶段 | 完成 | 待实施 | 完成率 |
|------|------|--------|--------|
| P0 Bug 修复 | 5 | 0 | 100% |
| P1 关键改进 | 8 | 0 | 100% |
| P2 体验升级 | 8 | 3 | 73% |
| P3 差异化建设 | 0 | 8 | 0% |
| **合计** | **21** | **11** | **66%** |

---

## P0 — Bug 修复

| # | 状态 | 问题 | 文件 | 完成时间 |
|---|------|------|------|---------|
| 1 | ✅ | 中间 Tab 占位 → 4 Tab 替代 | `app_shell.dart` | 2026-06-19 |
| 2 | ✅ | 超支"查看"按钮空回调 | `budget_settings_screen.dart:462` | 2026-06-19 |
| 3 | ✅ | 趋势图月份切换器 TODO | `net_worth_chart.dart:78` | 2026-06-19 |
| 4 | ✅ | 记账失败静默无反馈 | `record_screen.dart:100-102` | 2026-06-19 |
| 5 | ✅ | 资产页趋势数据 `data: []` | `assets_screen.dart` + `assets_provider.dart` | 2026-06-19 |

---

## P1 — 关键改进

| # | 状态 | 类别 | 改进项 | 文件 |
|---|------|------|--------|------|
| 6 | ✅ | 可访问性 | 所有 emoji 替换为 Material Icons | 多文件 | 2026-06-19 |
| 7 | ✅ | 可访问性 | 关键交互元素添加 tooltip/semanticLabel | 多文件 | 2026-06-19 |
| 8 | ✅ | 触控 | ActionChip 高度提升至 44px | `record_screen.dart` | 2026-06-19 |
| 9 | ✅ | 触控 | 记账成功 2 秒阻塞 → SnackBar + 即时重置 + haptic | `record_screen.dart` | 2026-06-19 |
| 10 | ✅ | 排版 | 全局金额添加 `FontFeature.tabularFigures()` | `typography.dart` + `app_theme.dart` | 2026-06-19 |
| 11 | ✅ | 颜色 | 净存款正负值增加趋势箭头图标 | `home_screen.dart` | 2026-06-19 |
| 12 | ✅ | 导航 | 4 Tab 设计（已在 P0-1 完成） | `app_shell.dart` | 2026-06-19 |
| 13 | ✅ | 动画 | 全局 7 处动画添加 reduced-motion 检测 | 多文件 + 新增 `accessibility_utils.dart` | 2026-06-19 |

---

## P2 — 体验升级

| # | 状态 | 类别 | 改进项 | 文件 | 完成时间 |
|---|------|------|--------|------|---------|
| 14 | ✅ | 性能 | 骨架屏加载替代全屏转圈 | 多文件 + 新增 `shimmer_loading.dart` | 2026-06-19 |
| 15 | ✅ | 风格 | 配色体系竹青化（含暗色模式独立调校） | `colors.dart` | 2026-06-19 |
| 19 | ✅ | 表单 | 归档/删除操作添加 undo toast | 3 页面 + 2 DAO 新增 unarchive | 2026-06-19 |
| 23 | ✅ | 布局 | 统一间距 token（xs/sm/md/lg/xl/2xl + 圆角） | `constants.dart` | 2026-06-19 |
| — | ~~P2-17~~ | ~~触控~~ | ~~haptic feedback~~ → 已在 P1-9 完成 | — | — |
| — | ~~P2-18~~ | ~~表单~~ | ~~记账表单内联验证~~ → 已在 P0-4 完成 | — | — |
| — | ~~P2-20~~ | ~~排版~~ | ~~金额等宽数字~~ → 已在 P1-10 完成 | — | — |
| — | ~~P2-21~~ | ~~创新~~ | ~~心流模式~~ → 已在 P1-9 完成 | — | — |
| 16 | 🔴 | 风格 | 3 级卡片层级实施 | `app_theme.dart` + 各页面 | — |
| 22 | 🔴 | 创新 | 分析页时间线 UI | `insights_screen.dart` | — |
| 24 | 🔴 | 图表 | 分类排行添加图案/纹理辅助 | `insights_screen.dart` | — |

---

## P3 — 差异化建设

| # | 状态 | 类别 | 改进项 | 文件 |
|---|------|------|--------|------|
| 25 | 🔴 | 签名 | 竹节生长进度条 | `home_screen.dart` |
| 26 | 🔴 | 签名 | 首页 Hero 卡片渐变背景 | `home_screen.dart` |
| 27 | 🔴 | 创新 | 搜索/自然语言查询 | 新增 |
| 28 | 🔴 | 创新 | iOS/Android 桌面 Widget | 新增 |
| 29 | 🔴 | 导航 | 深层链接支持 | 多文件 |
| 30 | 🔴 | 动画 | 页面间共享元素过渡 | 多文件 |
| 31 | 🔴 | 响应式 | 横屏适配 | 多文件 |
| 32 | 🔴 | 引导 | 冷启动 onboarding | 新增 |

---

## 设计 Token（最终版）

### 配色

```
竹青系（品牌主色）
├── primary:      #5B9A3B   主操作 / 正向指标
├── primaryLight: #EAF4E1   浅背景 / Chip 选中
├── primaryDark:  #3D6B27   暗色模式 primary

暖橙系（警示色）
├── danger:       #D96459   超支 / 负债 / 删除
├── dangerLight:  #FDF0ED   浅警示背景

中性系
├── bg:           #FAFAF8   页面背景
├── surface:      #FFFFFF   卡片背景
├── surfaceAlt:   #F2F1ED   次级容器
├── textPrimary:  #1C1C1C   主文字
├── textSecondary:#6E6E6E   次要文字
├── textTertiary: #A0A0A0   禁用/占位
├── border:       #E2E2DE   卡片边框
└── divider:      #EDEDE9   细分割线

暗色模式
├── bgDark:       #1A1D1A   极深竹底
├── surfaceDark:  #262926   暗色卡片
├── primaryDark:  #7CB342   暗色下更亮的绿
```

### 字体

| 角色 | 字体 | 策略 |
|------|------|------|
| UI 正文 | 系统默认 | 0 KB |
| 金额数字 | 系统默认 + tabularFigures | 0 KB |
| 展示标题 | 系统默认 + 加粗字重 | 0 KB |

### 间距 Token

```
xs  4px     sm  8px     md  16px
lg  24px    xl  32px    2xl 48px
```

---

## 核心设计原则

> 精确的数字需要等宽字体和清晰对比度；
> 生长的叙事需要竹青渐层和竹节视觉符号；
> 低焦虑的体验需要触觉反馈、即时响应和宽容的表单。

---

## 实施记录

### P0 — 2026-06-19

**修改文件（6 个）**：

| 文件 | 改动 |
|------|------|
| `lib/app_shell.dart` | 移除中间假 Tab（5→4），消除 IndexedStack 索引错位 |
| `lib/features/settings/budget_settings_screen.dart` | `_OverBudgetBanner` 改为 StatefulWidget，"查看"→"知道了"关闭横幅 |
| `lib/features/assets/net_worth_chart.dart` | 改为 StatefulWidget，3/6/12 月切换生效 |
| `lib/features/record/record_screen.dart` | 新增 `_showValidationError()`，表单不完整时 SnackBar 提示 |
| `lib/features/assets/assets_provider.dart` | 新增 `_computeMonthlySnapshots()` 从流水回溯 12 月趋势 |
| `lib/features/assets/assets_screen.dart` | 连线真实趋势数据 |

### P1 — 2026-06-19

**修改文件（10 个） + 新增（1 个）**：

| 文件 | 改动 |
|------|------|
| `lib/core/utils/accessibility_utils.dart` | **新增** — `motionDuration()` / `shouldReduceMotion()` |
| `lib/features/assets/assets_provider.dart` | `AccountTypeConfig` emoji→IconData |
| `lib/features/assets/assets_screen.dart` | emoji 调用→Icon + reduced-motion |
| `lib/features/auth/auth_screen.dart` | 🐼 emoji→`Icons.savings` Logo 容器 |
| `lib/features/settings/settings_screen.dart` | 🐼 CircleAvatar→Icon |
| `lib/features/settings/account_manage_screen.dart` | 💡 emoji→Icon+Text Row |
| `lib/features/record/ai_recognition_sheet.dart` | ✨✓→Icon |
| `lib/features/record/record_screen.dart` | 触控 44px、即时重置+Haptic、表单验证、日期 tooltip |
| `lib/features/insights/insights_screen.dart` | 月份箭头 tooltip + reduced-motion |
| `lib/features/home/home_screen.dart` | 净存款趋势箭头 + reduced-motion |
| `lib/core/theme/typography.dart` | `FontFeature.tabularFigures()` |
| `lib/core/theme/app_theme.dart` | TextTheme 等宽数字 |

### P2 — 2026-06-19

**修改文件（11 个） + 新增（1 个）**：

| 文件 | 改动 |
|------|------|
| `lib/core/widgets/shimmer_loading.dart` | **新增** — `ShimmerBox` + `PageSkeletons`（4 种布局） |
| `lib/core/theme/colors.dart` | 竹青配色全量重构（亮色+暗色+分类色板） |
| `lib/core/constants.dart` | 间距 Token 体系（xs→2xl）+ 圆角 Token + 触控常量 |
| `lib/data/local/dao/account_dao.dart` | 新增 `unarchiveAccount()` |
| `lib/data/local/dao/category_dao.dart` | 新增 `unarchiveCategory()` |
| `lib/data/repository/account_repository.dart` | 新增 `unarchive()` |
| `lib/features/auth/auth_gate.dart` | 骨架屏替换转圈 |
| `lib/features/home/home_screen.dart` | 骨架屏替换转圈 |
| `lib/features/assets/assets_screen.dart` | 骨架屏替换转圈 |
| `lib/features/insights/insights_screen.dart` | 骨架屏替换转圈 |
| `lib/features/settings/budget_settings_screen.dart` | 骨架屏 + 删除储蓄目标 undo |
| `lib/features/settings/account_manage_screen.dart` | 骨架屏 + 归档 undo |
| `lib/features/settings/category_manage_screen.dart` | 骨架屏 + 归档 undo |
