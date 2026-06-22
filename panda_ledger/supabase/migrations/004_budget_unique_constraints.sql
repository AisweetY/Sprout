-- ============================================================
-- 004 — 预算唯一约束
-- ============================================================
-- 防止同一用户同月出现多条 saving_goal 或同一分类多条 category_budget。
-- 使用部分唯一索引（partial unique index），仅约束未软删除的记录，
-- 允许删后重建（deleted=true 的不参与唯一性检查）。

-- 1. 储蓄目标：同一用户同月只能有一条活跃的 saving_goal
CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_saving_goal_unique
    ON budgets (user_id, month)
    WHERE type = 'saving_goal' AND deleted = false;

-- 2. 分类预算：同一用户同月同分类只能有一条活跃的 category_budget
CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_category_budget_unique
    ON budgets (user_id, month, category_id)
    WHERE type = 'category_budget' AND deleted = false;
