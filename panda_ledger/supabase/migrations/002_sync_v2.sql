-- ============================================================
-- 熊猫记账 — 同步 v2 升级迁移
-- Supabase PostgreSQL
-- 版本: 2.0
-- 日期: 2026-06-20
-- ============================================================

-- 1. accounts — 新增 deleted 列 + updated_at 触发器
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT FALSE;
-- updated_at 列已存在，但缺少触发器，补建
DROP TRIGGER IF EXISTS trg_accounts_updated_at ON accounts;
CREATE TRIGGER trg_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. categories — 新增 updated_at, deleted 列 + 触发器
ALTER TABLE categories ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE categories ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT FALSE;
DROP TRIGGER IF EXISTS trg_categories_updated_at ON categories;
CREATE TRIGGER trg_categories_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. budgets — 新增 updated_at, deleted 列 + 触发器
ALTER TABLE budgets ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE budgets ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT FALSE;
DROP TRIGGER IF EXISTS trg_budgets_updated_at ON budgets;
CREATE TRIGGER trg_budgets_updated_at
    BEFORE UPDATE ON budgets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. records — 新增 deleted 列
ALTER TABLE records ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT FALSE;
-- updated_at 触发器已在 001_init.sql 中创建，无需重复

-- 5. 增量同步索引（基于 updated_at 的高效过滤）
CREATE INDEX IF NOT EXISTS idx_accounts_updated_at ON accounts(updated_at);
CREATE INDEX IF NOT EXISTS idx_categories_updated_at ON categories(updated_at);
CREATE INDEX IF NOT EXISTS idx_records_updated_at ON records(updated_at);
CREATE INDEX IF NOT EXISTS idx_budgets_updated_at ON budgets(updated_at);

-- 6. 重建 RLS 策略（确保 deleted 列也在 RLS 保护范围内）
-- 策略本身无需修改：FOR ALL USING (auth.uid() = user_id) 已覆盖所有列
-- 仅重建以确保与新增列兼容
DROP POLICY IF EXISTS "用户仅访问自己的账户" ON accounts;
CREATE POLICY "用户仅访问自己的账户" ON accounts
    FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "用户仅访问自己的分类" ON categories;
CREATE POLICY "用户仅访问自己的分类" ON categories
    FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "用户仅访问自己的流水" ON records;
CREATE POLICY "用户仅访问自己的流水" ON records
    FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "用户仅访问自己的预算" ON budgets;
CREATE POLICY "用户仅访问自己的预算" ON budgets
    FOR ALL USING (auth.uid() = user_id);
