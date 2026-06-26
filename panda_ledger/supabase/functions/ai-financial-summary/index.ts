/// ============================================================
/// 熊猫记账 — AI 财务小结 Edge Function
///
/// 部署: supabase functions deploy ai-financial-summary
///
/// 返回格式：{ user_tag, tag_desc, opening, insights[], focus, advice }
/// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ProviderConfig {
  id: string;
  provider_name: string;
  base_url: string;
  model: string;
  api_key_secret_name: string;
  is_active: boolean;
}

interface AdviceHints {
  goal_status: string | null;       // 目标达成情况（Flutter 精算，如"当前完成72%，按节奏预计完成约85%，本月难达标"）
  top_gain_category: string | null; // 本期环比增幅最大的分类
  top_gain_amount: number | null;   // 该分类比上期多花了多少
  days_remaining: number;           // 当前周期剩余天数（0=已结束）
}

interface SummaryRequest {
  dimension_name: string;
  period_label: string;
  current_date: string;
  income: number;
  expense: number;
  net_saving: number;
  savings_rate: number;
  prev_income: number;
  prev_expense: number;
  top_categories: Array<{
    name: string;
    amount: number;
    ratio: number;
    prev_amount: number;
  }>;
  large_expenses: Array<{
    description: string;
    amount: number;
    category: string;
  }>;
  high_frequency_category: string | null;
  assets: { cash_ratio: number; invest_ratio: number } | null;
  historical_avg_expense: number | null;
  budget_status: string | null;
  advice_hints: AdviceHints;
}

// ═══════════════════════════════════════════════════════════════
// Prompt 构建
// ═══════════════════════════════════════════════════════════════

function buildPrompt(d: SummaryRequest): string {
  // ── 分类 TOP3 ──
  let catText = "无消费分类数据";
  if (d.top_categories.length > 0) {
    catText = d.top_categories
      .map((c, i) => {
        const prevDiff = c.prev_amount > 0
          ? `，环比${c.amount >= c.prev_amount ? "+" : ""}¥${(c.amount - c.prev_amount).toFixed(0)}`
          : "";
        return `${i + 1}. ${c.name} ¥${c.amount.toFixed(0)}（占 ${c.ratio.toFixed(0)}%${prevDiff}）`;
      })
      .join("  ");
  }

  // ── 大额消费 ──
  let largeText = "无";
  if (d.large_expenses.length > 0) {
    largeText = d.large_expenses
      .map((e) => `"${e.description}" ¥${e.amount.toFixed(0)}`)
      .join("、");
  }

  // ── 历史均值 ──
  let histText = "无历史数据";
  let histDiffText = "";
  if (d.historical_avg_expense != null && d.historical_avg_expense > 0) {
    const diff = d.expense - d.historical_avg_expense;
    const pct = ((diff / d.historical_avg_expense) * 100).toFixed(0);
    histText = `过去 6 个月月均支出 ¥${d.historical_avg_expense.toFixed(0)}`;
    histDiffText = `本期${diff >= 0 ? "超出" : "低于"}均值 ¥${Math.abs(diff).toFixed(0)}（${diff >= 0 ? "+" : ""}${pct}%）`;
  }

  // ── 支出环比 ──
  const expDiff = d.prev_expense > 0
    ? `比上期${d.expense >= d.prev_expense ? "多" : "少"} ¥${Math.abs(d.expense - d.prev_expense).toFixed(0)}`
    : "无上期数据";

  // ── 资产 ──
  const assetText = d.assets
    ? `现金类 ${d.assets.cash_ratio}%，投资类 ${d.assets.invest_ratio}%`
    : "无资产数据";

  // ── 建议锚点（App 精确计算，AI 写 advice 只能引用这里的结论，不得编造）──
  const h: AdviceHints = d.advice_hints ?? {
    goal_status: null,
    top_gain_category: null,
    top_gain_amount: null,
    days_remaining: 0,
  };
  const anchorLines: string[] = [];

  anchorLines.push(h.goal_status
    ? `目标达成情况：${h.goal_status}`
    : "储蓄目标：无（用户未设置）"
  );

  anchorLines.push(h.top_gain_category && h.top_gain_amount != null
    ? `最大增支：「${h.top_gain_category}」比上期多花了 ¥${h.top_gain_amount.toFixed(0)}`
    : "最大增支：各分类未明显超出上期"
  );

  anchorLines.push(h.days_remaining > 0
    ? `周期剩余：还有 ${h.days_remaining} 天`
    : "周期状态：已结束"
  );

  const anchorText = anchorLines.join("\n");

  return `你是用户的私人财务参谋。根据下方数据写财务小结，只输出 JSON，不加任何其他文字。

数据（${d.dimension_name}·${d.period_label}·${d.current_date}）：
收入¥${d.income.toFixed(0)} 支出¥${d.expense.toFixed(0)} 结余¥${d.net_saving.toFixed(0)}${d.net_saving < 0 ? "[入不敷出]" : ""} 储蓄率${d.savings_rate.toFixed(0)}%
上期支出¥${d.prev_expense.toFixed(0)}（${expDiff}）| ${histText}${histDiffText ? " " + histDiffText : ""}
支出TOP3：${catText}
大额（≥500）：${largeText} | 高频：${d.high_frequency_category ?? "无"} | 资产：${assetText}
预算：${d.budget_status ?? "无"}

建议锚点（以下数字由App精算，advice只能用这些数字）：
${anchorText}

输出以下JSON结构（字段含义见括号，不要输出括号里的内容）：
{"user_tag":"消费人格4~8字","tag_desc":"诠释≤18字不重复标签","opening":"整体状态定调≤25字","insights":[{"conclusion":"判断≤12字","detail":"数字+对比≤35字"}],"focus":{"problem":"最大问题≤18字","vs_history":"量化对比≤20字"},"advice":"两句话共≤45字"}

写作规则：
1. user_tag 必须以「型」结尾，4~8字，描述消费个性，可以幽默接地气（如：月末惊魂型、手滑不自知型、默默存钱型、刚刚好型、餐饮刺客受害型），禁止营销腔
2. insights 2~3条，conclusion是判断句不是数据描述，detail必须含具体数字和上期/历史对比
3. advice 写法（两句话，共≤45字）：
   第一句：直接复述「目标达成情况」锚点里的结论，原话或近义改写，不加修饰
   第二句：给下期一条调整，围绕「最大增支」分类；若无增支则给一条通用下期建议
   禁止：给本期内"今天/这周"的具体行动；编造锚点外的金额数字
4. 禁用词：建议关注/值得注意/合理配置/保持健康/消费习惯/整体良好
5. focus无明显问题时设null
6. 只输出JSON，不加解释、不加代码块`;
}

// ═══════════════════════════════════════════════════════════════
// 工具函数
// ═══════════════════════════════════════════════════════════════

function extractJson(text: string): string {
  const mdMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (mdMatch) return mdMatch[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start !== -1 && end !== -1) return text.slice(start, end + 1).trim();
  return text.trim();
}

// ═══════════════════════════════════════════════════════════════
// 主处理
// ═══════════════════════════════════════════════════════════════

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "仅支持 POST 请求" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    // ── 1. 身份校验 ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "未登录" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonResponse({ error: "服务端配置缺失" }, 500);
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return jsonResponse({ error: "身份校验失败" }, 401);

    // ── 2. 会员校验 ──
    const { data: membership } = await supabase
      .from("memberships")
      .select("status, expires_at")
      .eq("user_id", user.id)
      .maybeSingle();

    const membershipActive =
      membership?.status === "active" &&
      (membership.expires_at === null || new Date(membership.expires_at) > new Date());

    if (!membershipActive) return jsonResponse({ error: "MEMBERSHIP_REQUIRED" }, 402);

    // ── 3. 解析请求 ──
    const body: SummaryRequest = await req.json().catch(() => null);
    if (!body || body.dimension_name == null) {
      return jsonResponse({ error: "缺少必填参数" }, 400);
    }

    // ── 4. 读 AI 配置 ──
    const { data: config, error: configError } = await supabase
      .from("ai_provider_configs")
      .select("*")
      .eq("is_active", true)
      .single();

    if (configError || !config) {
      return jsonResponse({ error: "未找到生效的 AI 提供商配置" }, 500);
    }

    const provider = config as ProviderConfig;
    const apiKey = Deno.env.get(provider.api_key_secret_name);
    if (!apiKey) {
      return jsonResponse({ error: `未配置 ${provider.api_key_secret_name}` }, 500);
    }

    // ── 5. 调 AI ──
    const prompt = buildPrompt(body);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 28_000);

    let aiResponse: Response;
    try {
      aiResponse = await fetch(`${provider.base_url}/chat/completions`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: provider.model,
          messages: [{ role: "user", content: prompt }],
          temperature: 0.5,
          max_tokens: 900,
        }),
        signal: controller.signal,
      });
    } catch (fetchErr) {
      clearTimeout(timeout);
      if (fetchErr.name === "AbortError") {
        return jsonResponse({ error: "AI 服务响应超时，请稍后重试" }, 504);
      }
      return jsonResponse({ error: `调用 AI 服务失败: ${fetchErr.message}` }, 502);
    } finally {
      clearTimeout(timeout);
    }

    if (!aiResponse.ok) {
      let errDetail = "";
      try {
        errDetail = await aiResponse.text();
        if (errDetail.length > 500) errDetail = errDetail.slice(0, 500) + "…";
      } catch { /* ignore */ }
      return jsonResponse(
        { error: `AI 服务返回错误 (${aiResponse.status})`, detail: errDetail },
        502
      );
    }

    const result = await aiResponse.json();
    const content: string | null | undefined = result.choices?.[0]?.message?.content;
    const finishReason: string | undefined = result.choices?.[0]?.finish_reason;

    // 记录关键调试信息，方便在 Supabase Dashboard → Logs 里排查
    console.log(`[ai-financial-summary] finish_reason=${finishReason}, content_len=${content?.length ?? 0}`);

    if (!content || content.trim().length === 0) {
      const reason = finishReason === "content_filter"
        ? "AI 内容过滤拦截，请稍后重试"
        : finishReason === "length"
          ? "AI 输出被截断（token 不足），请稍后重试"
          : "AI 服务返回了空内容";
      console.error(`[ai-financial-summary] empty content: finish_reason=${finishReason}, raw_result=${JSON.stringify(result).slice(0, 300)}`);
      return jsonResponse({ error: reason }, 502);
    }

    // ── 6. 解析结构化 JSON ──
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(extractJson(content));
    } catch (e) {
      console.error("⚠️ JSON 解析失败:", e, "\n原始内容:", content);
      return jsonResponse({ error: "AI 返回格式异常，请重试" }, 502);
    }

    // 校验必填字段
    const userTag = String(parsed.user_tag ?? "").trim();
    const tagDesc = String(parsed.tag_desc ?? "").trim();
    const opening = String(parsed.opening ?? "").trim();
    const rawInsights = parsed.insights;
    const insights = Array.isArray(rawInsights)
      ? rawInsights
          .map((i) => ({
            conclusion: String((i as Record<string, unknown>).conclusion ?? "").trim(),
            detail: String((i as Record<string, unknown>).detail ?? "").trim(),
          }))
          .filter((i) => i.conclusion && i.detail)
      : [];
    const advice = String(parsed.advice ?? "").trim();

    if (!userTag || !opening || insights.length === 0 || !advice) {
      console.error("⚠️ 结构不完整:", { userTag, opening, insights, advice });
      return jsonResponse({ error: "AI 返回了不完整的内容，请重试" }, 502);
    }

    // focus 可选（本期无明显问题时 AI 会返回 null）
    const rawFocus = parsed.focus as Record<string, unknown> | null | undefined;
    const focus = rawFocus && rawFocus.problem
      ? {
          problem: String(rawFocus.problem ?? "").trim(),
          vs_history: String(rawFocus.vs_history ?? "").trim(),
        }
      : null;

    return jsonResponse({ user_tag: userTag, tag_desc: tagDesc, opening, insights, focus, advice });

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
