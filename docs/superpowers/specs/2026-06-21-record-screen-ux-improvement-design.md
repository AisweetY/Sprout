# 记一笔页面体验优化 — 设计文档

**日期**: 2026-06-21
**状态**: 待实施
**方案**: A（精准修补）

---

## 目标

解决「记一笔」页面三个核心体验痛点，不改动整体布局结构：

1. 没有的分类新增很麻烦，要返回去分类管理添加再回来
2. 底部数字键盘占比大，且用不到的时候不消失
3. 分类和账户应该默认选择上一次记账时选择的

---

## 改动一：分类弹窗内直接新建

### 入口位置

`_CategoryPickerSheet` 底部，所有分类网格下方，用分隔线隔开。

### 交互流程

```
_CategoryPickerSheet 打开
  └── 分类网格正常展示
  └── Divider
  └── 「+ 新建分类」按钮
      └── 点击 → showDialog 弹出创建表单
          ├── 所属父分类：[下拉选择]
          │   ├── 列出当前 Tab 类型（支出/收入）下的一级分类
          │   └── 「+ 新建一级分类」→ 展开文本输入框
          ├── 子分类名称：[文本输入框，可留空]
          │   └── 留空 = 只创建一级分类
          └── 「创建」按钮
              ├── 已有父分类 + 子分类名 → 创建二级分类
              ├── 新建父分类 + 子分类名 → 先建父分类再建子分类
              ├── 新建父分类 + 子分类留空 → 只建一级分类
              └── 创建完成后：
                  ├── 自动选中新分类
                  ├── 刷新弹窗中的分类列表
                  └── 关闭创建表单
```

### 技术要点

- 创建表单通过 `showDialog` 在当前 `BottomSheet` 之上弹出
- 一级分类的 `kind` 由当前 Tab（支出→expense，收入→income）决定
- 调用 `categoryRepository.createCategory()` 创建，自动入同步队列
- 新分类默认图标使用 `Icons.category`
- 用户退出记账页面时同步刷新分类管理页面数据

### 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/features/record/record_screen.dart` | `_CategoryPickerSheet` 底部增加新建入口 + 创建表单 Dialog |
| `lib/data/repository/category_repository.dart` | 复用现有 `createCategory()`，无需改动 |

---

## 改动二：键盘自动收起 + 侧滑返回先收键盘

### 键盘展示/收起逻辑

| 触发方式 | 行为 |
|---|---|
| 页面打开 | 键盘显示，金额区域自动获得焦点 |
| 点击「选择分类」或「选择账户」 | 键盘收起 |
| 分类/账户弹窗关闭后 | 键盘继续保持收起 |
| 点击金额显示区域 | 键盘弹出 |
| 点击备注输入框 | 系统键盘接管 |
| 表单区域垂直滚动 | 键盘收起（`ScrollViewKeyboardDismissBehavior.onDrag`） |
| 系统侧滑返回手势 | 键盘打开时 → 只收起键盘，不返回上一页；键盘已收起 → 正常返回 |
| 提交完成 | 键盘收起 |

### 技术要点

- 金额区域使用隐藏的 `TextField` + `FocusNode`（`_amountFocus`）控制键盘显隐
- 金额显示区域包 `GestureDetector`，点击时 `_amountFocus.requestFocus()`
- 分类/账户选择触发时 `_amountFocus.unfocus()`
- `PopScope` 包裹页面：`canPop` 在 `_amountFocus.hasFocus` 为 `true` 时返回 `false`，先 `unfocus()`，状态更新后 `canPop` 自动变回 `true`
- `SingleChildScrollView` 设置 `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`（当前可能已有）

### 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/features/record/record_screen.dart` | 金额区域加 FocusNode + GestureDetector；PopScope 控制侧滑；分类/账户选择流程中触发 unfocus |

---

## 改动三：记住上一次选择

### 存储内容

使用 `SharedPreferences` 存储以下键值：

| Key | 值 | 说明 |
|---|---|---|
| `last_category_id` | `String?` | 上次选的二级分类 ID |
| `last_parent_category_id` | `String?` | 上次选的一级分类 ID（兜底） |
| `last_account_id` | `String?` | 上次选的账户 ID |
| `last_to_account_id` | `String?` | 上次转账的转入账户 ID |
| `last_record_type` | `String?` | 上次的类型（expense / income / transfer） |

### 恢复逻辑

```
页面 initState：
  1. 读取 last_record_type → 切换到对应 Tab
  2. 读取 last_category_id：
     a. 该分类存在且未被删除/归档 → 自动选中（二级分类）
     b. 否则读取 last_parent_category_id → 存在 → 自动选中（一级分类兜底）
     c. 否则不选
  3. 读取 last_account_id → 存在且未归档 → 自动选中
  4. 转账模式下读取 last_to_account_id → 存在且未归档且 ≠ 转出账户 → 自动选中
```

### 写入时机

每次提交成功后（`_submitRecord` 方法末尾）更新所有存储值：

- `last_record_type` = 当前 `_recordType`
- `last_category_id` = 当前选中的二级分类 ID（有则存，无则存一级分类 ID）
- `last_parent_category_id` = 当前选中的一级分类 ID
- `last_account_id` = 当前选中的账户 ID
- `last_to_account_id` = 转账模式下的转入账户 ID

### 技术要点

- 通过 `SharedPreferences` 存取（Flutter 标准库，项目中已有使用）
- 读取时需要额外验证分类和账户是否仍然存在且未被归档（防脏数据）
- 类型切换时**不清除**已选分类（当前行为是清除，本次顺手修正）

### 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/features/record/record_screen.dart` | initState 读取 + _submitRecord 写入 + 类型切换保留分类 |

---

## 影响范围

| 文件 | 改动程度 | 说明 |
|---|---|---|
| `lib/features/record/record_screen.dart` | 中等 | 三个改动的主要实施文件 |
| `lib/features/record/batch_record_screen.dart` | 不变 | 批量记账使用独立页面，不受影响 |

---

## 验收标准

### 改动一
- [ ] 分类弹窗底部可见「+ 新建分类」按钮
- [ ] 点击后弹出创建表单，包含父分类下拉和子分类名称两个字段
- [ ] 父分类下拉中包含「+ 新建一级分类」选项
- [ ] 创建成功后新分类自动选中，弹窗回到分类网格
- [ ] 退出记账页后分类管理页能看到新增的分类

### 改动二
- [ ] 页面打开时键盘显示，金额区域有焦点
- [ ] 点击分类/账户选择器时键盘收起
- [ ] 弹窗关闭后键盘保持收起
- [ ] 点击金额区域键盘重新弹出
- [ ] 表单区域上下滚动时键盘收起
- [ ] 键盘打开时系统侧滑返回只收起键盘，不离开页面
- [ ] 键盘收起后系统侧滑正常返回上一页

### 改动三
- [ ] 提交一笔记账后，下次打开页面自动选中上一次的分类
- [ ] 自动选中上一次的账户
- [ ] 自动选中上一次的类型 Tab
- [ ] 上次的分类被删除或归档后，不崩溃，回退到未选中状态
- [ ] 转账模式下，上次的转入账户也被恢复
