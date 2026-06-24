-- ============================================================
-- 熊猫记账 — 会员体系
-- Supabase PostgreSQL
-- 版本: 5.0
-- 日期: 2026-06-24
-- ============================================================
-- 表：membership_skus / memberships / orders
-- RPC：grant_membership()
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. membership_skus — 可配置 SKU（后台改表即生效，无需发版）
--    风格同 ai_provider_configs
-- ─────────────────────────────────────────────────────────────
CREATE TABLE membership_skus (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sku_code             TEXT NOT NULL UNIQUE,            -- monthly_30 / yearly_365 / lifetime
    title                TEXT NOT NULL,                   -- "月度会员"
    subtitle             TEXT NOT NULL DEFAULT '',        -- "解锁全部 AI 功能"
    price_cents          INT  NOT NULL,                   -- 单位：分，避免浮点
    original_price_cents INT  NULL,                       -- 划线原价（null = 不显示）
    duration_days        INT  NULL,                       -- null = 永久
    plan_type            TEXT NOT NULL,                   -- monthly / yearly / lifetime
    badge                TEXT NULL,                       -- "最划算" 角标（null = 不显示）
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,   -- 上下架开关
    sort_order           INT  NOT NULL DEFAULT 0,         -- 展示排序（升序）
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_sku_plan_type CHECK (plan_type IN ('monthly', 'yearly', 'lifetime')),
    CONSTRAINT chk_sku_price     CHECK (price_cents > 0)
);

DROP TRIGGER IF EXISTS trg_membership_skus_updated_at ON membership_skus;
CREATE TRIGGER trg_membership_skus_updated_at
    BEFORE UPDATE ON membership_skus
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS：认证用户可读（同 ai_provider_configs）；写入仅 service_role
ALTER TABLE membership_skus ENABLE ROW LEVEL SECURITY;
CREATE POLICY "会员SKU-认证用户可读" ON membership_skus
    FOR SELECT USING (auth.role() = 'authenticated');

-- ─────────────────────────────────────────────────────────────
-- 2. memberships — 会员状态（每用户一条，PK = user_id）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE memberships (
    user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    plan        TEXT        NOT NULL,                     -- monthly / yearly / lifetime
    status      TEXT        NOT NULL DEFAULT 'active',    -- active / expired / refunded
    expires_at  TIMESTAMPTZ NULL,                         -- null = 永久；有效期判断见视图
    source      TEXT        NOT NULL,                     -- redeem_code / alipay / wechat / iap / manual
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_membership_plan   CHECK (plan   IN ('monthly', 'yearly', 'lifetime')),
    CONSTRAINT chk_membership_status CHECK (status IN ('active', 'expired', 'refunded')),
    CONSTRAINT chk_membership_source CHECK (source IN ('redeem_code', 'alipay', 'wechat', 'iap', 'manual'))
);

DROP TRIGGER IF EXISTS trg_memberships_updated_at ON memberships;
CREATE TRIGGER trg_memberships_updated_at
    BEFORE UPDATE ON memberships
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS：用户只能读自己那条；写入禁止（统一走 grant_membership RPC）
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "会员状态-仅读自己" ON memberships
    FOR SELECT USING (auth.uid() = user_id);
-- INSERT / UPDATE / DELETE 无策略 ⇒ 默认拒绝（service_role 绕过 RLS）

-- ─────────────────────────────────────────────────────────────
-- 3. orders — 订单（阶段一建表，阶段三接支付时填充）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE orders (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_no         TEXT NOT NULL UNIQUE,                -- 商户订单号，格式 PL_<ts>_<rand>
    user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sku_code         TEXT NOT NULL,
    amount_cents     INT  NOT NULL,
    channel          TEXT NOT NULL DEFAULT 'pending',     -- alipay / wechat / xunhu / iap / redeem
    status           TEXT NOT NULL DEFAULT 'pending',     -- pending / paid / failed / closed / refunded
    channel_trade_no TEXT NULL,                           -- 支付宝/微信交易号
    paid_at          TIMESTAMPTZ NULL,
    raw_notify       JSONB NULL,                          -- 回调原文，审计用
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_order_channel CHECK (channel IN ('alipay', 'wechat', 'xunhu', 'iap', 'redeem', 'pending')),
    CONSTRAINT chk_order_status  CHECK (status  IN ('pending', 'paid', 'failed', 'closed', 'refunded'))
);

CREATE INDEX idx_orders_user_id   ON orders(user_id);
CREATE INDEX idx_orders_status    ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS：用户只能读自己的订单；写入禁止（统一走 Edge Function）
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "订单-仅读自己" ON orders
    FOR SELECT USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- 4. grant_membership() — 系统心脏：唯一的「开通/续费」入口
--    调用方：redeem-code / payment-notify / 后台手动
--    安全：SECURITY DEFINER（以函数所有者权限运行，绕过 RLS）
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION grant_membership(
    p_user_id  UUID,
    p_sku_code TEXT,
    p_source   TEXT,
    p_ref_id   TEXT DEFAULT NULL    -- 兑换码 code / 订单号 order_no / 备注
)
RETURNS memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sku      membership_skus;
    v_now      TIMESTAMPTZ := NOW();
    v_base     TIMESTAMPTZ;
    v_expires  TIMESTAMPTZ;
    v_result   memberships;
BEGIN
    -- 1. 查 SKU
    SELECT * INTO v_sku FROM membership_skus WHERE sku_code = p_sku_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SKU_NOT_FOUND: %', p_sku_code;
    END IF;

    -- 2. 计算到期时间
    IF v_sku.duration_days IS NULL THEN
        -- 永久会员
        v_expires := NULL;
    ELSE
        -- 续费叠加：未过期则在原到期日累加，否则从现在算
        SELECT CASE
            WHEN m.expires_at IS NOT NULL AND m.expires_at > v_now THEN m.expires_at
            ELSE v_now
        END
        INTO v_base
        FROM memberships m
        WHERE m.user_id = p_user_id;

        v_expires := COALESCE(v_base, v_now) + (v_sku.duration_days || ' days')::INTERVAL;
    END IF;

    -- 3. UPSERT（新用户 INSERT，老用户 UPDATE）
    INSERT INTO memberships (user_id, plan, status, expires_at, source, started_at, updated_at)
    VALUES (p_user_id, v_sku.plan_type, 'active', v_expires, p_source, v_now, v_now)
    ON CONFLICT (user_id) DO UPDATE SET
        plan       = EXCLUDED.plan,
        status     = 'active',
        expires_at = EXCLUDED.expires_at,
        source     = EXCLUDED.source,
        updated_at = v_now
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$;

-- 仅 service_role 可执行（Edge Function 用 service_role key 调用）
REVOKE EXECUTE ON FUNCTION grant_membership FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION grant_membership FROM authenticated;

-- ─────────────────────────────────────────────────────────────
-- 5. 默认 SKU seed 数据
-- ─────────────────────────────────────────────────────────────
INSERT INTO membership_skus
    (sku_code, title, subtitle, price_cents, original_price_cents,
     duration_days, plan_type, badge, is_active, sort_order)
VALUES
    ('monthly_30',  '月度会员', '解锁全部 AI 功能',  1800,  3000,  30,   'monthly',  NULL,     TRUE, 1),
    ('yearly_365',  '年度会员', '低至 1.6 元/天',   19900, 21600, 365,  'yearly',   '最划算', TRUE, 2),
    ('lifetime',    '永久会员', '一次买断，终身使用', 68000,  NULL,  NULL, 'lifetime', '限时优惠', TRUE, 3)
ON CONFLICT (sku_code) DO NOTHING;
