-- ============================================================
-- 熊猫记账 — 兑换码
-- Supabase PostgreSQL
-- 版本: 6.0
-- 日期: 2026-06-24
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. redemption_codes — 兑换码
--    RLS 全拒客户端直接读写，只有 Edge Function（service_role）可操作
-- ─────────────────────────────────────────────────────────────
CREATE TABLE redemption_codes (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code       TEXT NOT NULL UNIQUE,           -- PANDA-XXXX-XXXX，大写
    sku_code   TEXT NOT NULL,                  -- 兑换后开通哪个档位
    status     TEXT NOT NULL DEFAULT 'unused', -- unused / used / disabled
    used_by    UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    used_at    TIMESTAMPTZ NULL,
    batch      TEXT NULL,                      -- 运营批次，如 "kol_2026q3"
    expires_at TIMESTAMPTZ NULL,               -- 码本身有效期（null = 永不过期）
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_code_status CHECK (status IN ('unused', 'used', 'disabled')),
    -- 已使用的码必须有 used_by / used_at
    CONSTRAINT chk_code_used_fields CHECK (
        (status = 'used' AND used_by IS NOT NULL AND used_at IS NOT NULL)
        OR status != 'used'
    )
);

CREATE INDEX idx_redemption_codes_status ON redemption_codes(status);
CREATE INDEX idx_redemption_codes_batch  ON redemption_codes(batch) WHERE batch IS NOT NULL;

DROP TRIGGER IF EXISTS trg_redemption_codes_updated_at ON redemption_codes;
CREATE TRIGGER trg_redemption_codes_updated_at
    BEFORE UPDATE ON redemption_codes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS：启用但不建任何 SELECT/INSERT/UPDATE/DELETE 策略
-- ⇒ 普通用户（authenticated / anon）完全无法直接读写
-- ⇒ service_role 天然绕过 RLS，Edge Function 用它操作
ALTER TABLE redemption_codes ENABLE ROW LEVEL SECURITY;
