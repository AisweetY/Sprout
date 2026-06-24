/// ============================================================
/// 熊猫记账 — 兑换码兑换 Edge Function
///
/// 部署命令: supabase functions deploy redeem-code
///
/// 请求参数（POST JSON）:
///   { code: "PANDA-XXXX-XXXX" }
///
/// 返回:
///   成功: { plan, status, expires_at }     200
///   失败: { error: "CODE_INVALID" }        402
///         { error: "UNAUTHORIZED" }         401
///         { error: "..." }                  400/500
/// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request): Promise<Response> => {
  // ── CORS 预检 ──
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "仅支持 POST 请求" }, 405);
  }

  try {
    // ── 1. 身份校验（复用现有鉴权模式）──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "UNAUTHORIZED" }, 401);
    }

    const supabaseUrl  = Deno.env.get("SUPABASE_URL")      ?? "";
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseSvc  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseAnon || !supabaseSvc) {
      return jsonResponse({ error: "服务端配置缺失" }, 500);
    }

    // user-scoped client（JWT 身份）
    const userClient = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
      auth:   { persistSession: false },
    });

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return jsonResponse({ error: "UNAUTHORIZED" }, 401);
    }

    // service_role client（绕过 RLS，操作 redemption_codes）
    const svcClient = createClient(supabaseUrl, supabaseSvc, {
      auth: { persistSession: false },
    });

    // ── 2. 解析请求 ──
    const body = await req.json().catch(() => null);
    if (!body || typeof body.code !== "string" || body.code.trim() === "") {
      return jsonResponse({ error: "缺少 code 参数" }, 400);
    }

    const code = (body.code as string).trim().toUpperCase();

    // ── 3. 原子标记兑换码（防并发重复使用）──
    //    条件 UPDATE：仅 unused 且未过期的码才能被标记
    const { data: rows, error: updateError } = await svcClient
      .from("redemption_codes")
      .update({
        status:  "used",
        used_by: user.id,
        used_at: new Date().toISOString(),
      })
      .eq("code", code)
      .eq("status", "unused")
      .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`)
      .select("sku_code")
      .returns<Array<{ sku_code: string }>>();

    if (updateError) {
      console.error("兑换码标记失败:", updateError);
      return jsonResponse({ error: "服务内部错误" }, 500);
    }

    if (!rows || rows.length === 0) {
      // 0 行被更新 = 码无效 / 已使用 / 已过期
      return jsonResponse({ error: "CODE_INVALID" }, 402);
    }

    const skuCode = rows[0].sku_code;

    // ── 4. 调 grant_membership RPC 开通会员 ──
    const { data: membership, error: rpcError } = await svcClient.rpc(
      "grant_membership",
      {
        p_user_id:  user.id,
        p_sku_code: skuCode,
        p_source:   "redeem_code",
        p_ref_id:   code,
      }
    );

    if (rpcError) {
      console.error("grant_membership 调用失败:", rpcError);
      // 回滚：将码重置为 unused（尽力而为）
      await svcClient
        .from("redemption_codes")
        .update({ status: "unused", used_by: null, used_at: null })
        .eq("code", code);
      return jsonResponse({ error: `开通失败: ${rpcError.message}` }, 500);
    }

    // ── 5. 返回最新会员状态 ──
    return jsonResponse({
      plan:       membership.plan,
      status:     membership.status,
      expires_at: membership.expires_at,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: `服务内部错误: ${message}` }, 500);
  }
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
