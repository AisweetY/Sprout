-- ============================================================
-- 熊猫记账 — AI 多平台提供商配置表
-- Supabase PostgreSQL
-- 版本: 3.0
-- 日期: 2026-06-20
-- ============================================================

-- 1. ai_provider_configs — AI 平台配置
--    驱动 Edge Function 动态切换 AI 提供商，无需重新部署
CREATE TABLE ai_provider_configs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_name       TEXT NOT NULL UNIQUE,                          -- 平台标识: deepseek, openai, moonshot, qwen ...
    display_name        TEXT NOT NULL,                                 -- 给人看的名称: "DeepSeek V4 Flash"
    base_url            TEXT NOT NULL,                                 -- API 地址，如 https://api.deepseek.com/v1
    model               TEXT NOT NULL,                                 -- 模型名称，如 deepseek-v4-flash
    api_key_secret_name TEXT NOT NULL,                                 -- Secret 名称，不存 Key 本身
    adapter_type        TEXT NOT NULL DEFAULT 'openai_compatible',     -- 请求/响应解析方式
    is_active           BOOLEAN NOT NULL DEFAULT FALSE,                -- 当前生效的平台（仅一条为 true）
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 确保同一时间只有一个生效平台（部分唯一索引）
CREATE UNIQUE INDEX idx_ai_provider_configs_active
    ON ai_provider_configs(is_active) WHERE is_active = TRUE;

-- 2. updated_at 触发器
CREATE TRIGGER trg_ai_provider_configs_updated_at
    BEFORE UPDATE ON ai_provider_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. RLS：所有认证用户可读（Edge Function 在服务端以用户身份读取）
ALTER TABLE ai_provider_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "允许所有认证用户读取 AI 配置" ON ai_provider_configs
    FOR SELECT USING (auth.role() = 'authenticated');

-- 4. 默认配置 — DeepSeek V4 Flash
--    注意：DEEPSEEK_API_KEY 需要在 Supabase 后台 Dashboard → Settings → Edge Functions → Secrets 中手动添加
INSERT INTO ai_provider_configs
    (provider_name, display_name, base_url, model, api_key_secret_name, adapter_type, is_active)
VALUES
    ('deepseek', 'DeepSeek V4 Flash', 'https://api.deepseek.com/v1', 'deepseek-v4-flash', 'DEEPSEEK_API_KEY', 'openai_compatible', TRUE);
