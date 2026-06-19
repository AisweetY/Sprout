-- ============================================================
-- 熊猫记账 — 数据库初始化迁移
-- Supabase PostgreSQL
-- 版本: 1.0
-- 日期: 2026-06-19
-- ============================================================

-- 0. 启用 UUID 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. accounts — 账户表
-- ============================================================
CREATE TABLE accounts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    type            TEXT NOT NULL CHECK (type IN ('cash','bank','credit','loan','invest','other')),
    balance         NUMERIC(14,2) NOT NULL DEFAULT 0,
    currency        TEXT NOT NULL DEFAULT 'CNY',
    is_liability    BOOLEAN NOT NULL DEFAULT FALSE,
    include_in_net  BOOLEAN NOT NULL DEFAULT TRUE,
    is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order      INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_accounts_user ON accounts(user_id);

-- ============================================================
-- 2. categories — 分类表
-- ============================================================
CREATE TABLE categories (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
    icon        TEXT,
    kind        TEXT NOT NULL CHECK (kind IN ('expense','income')),
    sort_order  INT NOT NULL DEFAULT 0,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_categories_user ON categories(user_id);

-- ============================================================
-- 3. records — 流水主表
-- ============================================================
CREATE TABLE records (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    to_account_id   UUID REFERENCES accounts(id) ON DELETE RESTRICT,
    amount          NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    type            TEXT NOT NULL CHECK (type IN ('expense','income','transfer','adjustment')),
    category_id     UUID REFERENCES categories(id) ON DELETE SET NULL,
    note            TEXT,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     TEXT NOT NULL DEFAULT 'synced',
    source          TEXT NOT NULL DEFAULT 'manual'
);

CREATE INDEX idx_records_user_time ON records(user_id, occurred_at DESC);
CREATE INDEX idx_records_account ON records(account_id);
CREATE INDEX idx_records_category ON records(category_id);

-- ============================================================
-- 4. budgets — 预算/储蓄目标表
-- ============================================================
CREATE TABLE budgets (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month           TEXT NOT NULL, -- 'YYYY-MM'
    type            TEXT NOT NULL CHECK (type IN ('saving_goal','category_budget')),
    category_id     UUID REFERENCES categories(id) ON DELETE CASCADE,
    target_amount   NUMERIC(14,2) NOT NULL
);

CREATE INDEX idx_budgets_user_month ON budgets(user_id, month);

-- ============================================================
-- 5. 原子化记账函数（Postgres RPC）
-- ============================================================
CREATE OR REPLACE FUNCTION record_transaction(
    p_account_id    UUID,
    p_amount        NUMERIC,
    p_type          TEXT,
    p_to_account_id UUID DEFAULT NULL,
    p_category_id   UUID DEFAULT NULL,
    p_note          TEXT DEFAULT NULL,
    p_occurred_at   TIMESTAMPTZ DEFAULT NOW()
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record_id UUID;
BEGIN
    -- 插入流水记录
    INSERT INTO records (
        user_id, account_id, to_account_id, amount, type,
        category_id, note, occurred_at, sync_status, source
    ) VALUES (
        auth.uid(), p_account_id, p_to_account_id, p_amount, p_type,
        p_category_id, p_note, p_occurred_at, 'synced', 'manual'
    ) RETURNING id INTO v_record_id;

    -- 原子更新账户余额
    IF p_type = 'expense' THEN
        UPDATE accounts SET balance = balance - p_amount, updated_at = NOW()
        WHERE id = p_account_id;
    ELSIF p_type = 'income' THEN
        UPDATE accounts SET balance = balance + p_amount, updated_at = NOW()
        WHERE id = p_account_id;
    ELSIF p_type = 'transfer' AND p_to_account_id IS NOT NULL THEN
        UPDATE accounts SET balance = balance - p_amount, updated_at = NOW()
        WHERE id = p_account_id;
        UPDATE accounts SET balance = balance + p_amount, updated_at = NOW()
        WHERE id = p_to_account_id;
    END IF;

    RETURN v_record_id;
END;
$$;

-- ============================================================
-- 6. 行级安全策略（RLS）
-- ============================================================

-- accounts RLS
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户仅访问自己的账户" ON accounts
    FOR ALL USING (auth.uid() = user_id);

-- categories RLS
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户仅访问自己的分类" ON categories
    FOR ALL USING (auth.uid() = user_id);

-- records RLS
ALTER TABLE records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户仅访问自己的流水" ON records
    FOR ALL USING (auth.uid() = user_id);

-- budgets RLS
ALTER TABLE budgets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户仅访问自己的预算" ON budgets
    FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 7. updated_at 自动触发器
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_records_updated_at
    BEFORE UPDATE ON records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
