/// ============================================================
/// 熊猫记账 — AI 财务小结 Edge Function
///
/// 部署: supabase functions deploy ai-financial-summary
///
/// 接收 App 端预聚合的财务数据，调用 AI 生成 200-500 字自然语言小结。
/// 复用 ai_provider_configs 表决定调用哪个平台/模型。
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
  display_name: string;
  base_url: string;
  model: string;
  api_key_secret_name: string;
  adapter_type: string;
  is_active: boolean;
}

interface SummaryRequest {
  dimension_name: string;    // "本周" / "本月" / "2024年" / "6月1日-6月20日"
  period_label: string;      // 同 dimension_name，用于显示
  current_date: string;      // "2026-06-20"
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
  assets: {
    cash_ratio: number;
    invest_ratio: number;
  } | null;
  historical_avg_expense: number | null;
  budget_status: string | null;
}

// ═══════════════════════════════════════════════════════════════
// Prompt 构建
// ═══════════════════════════════════════════════════════════════

function buildPrompt(data: SummaryRequest): string {
  // 分类 TOP3 文本
  let catText = "";
  if (data.top_categories.length > 0) {
    catText = data.top_categories
      .map((c, i) => {
        const diff =
          c.prev_amount > 0
            ? ` (${data.dimension_name === "本日" || data.dimension_name === "本周" ? "对比" : "环比"}${c.amount >= c.prev_amount ? "+" : ""}${c.amount - c.prev_amount >= 0 ? "¥" : "-¥"}${Math.abs(c.amount - c.prev_amount).toFixed(0)})`
            : "";
        return `第${i + 1}：${c.name} ¥${c.amount.toFixed(0)}，占比 ${c.ratio.toFixed(0)}%${diff}`;
      })
      .join("；");
  } else {
    catText = "暂无消费分类数据";
  }

  // 大额消费
  let largeText = "无";
  if (data.large_expenses.length > 0) {
    largeText = data.large_expenses
      .map((e) => `${e.description}（${e.category}，¥${e.amount.toFixed(0)}）`)
      .join("；");
  }

  // 资产
  let assetText = "暂无资产数据";
  if (data.assets) {
    assetText = `现金类资产占比 ${data.assets.cash_ratio}%，投资类资产占比 ${data.assets.invest_ratio}%`;
  }

  // 历史均值
  let histText = "暂无历史数据";
  if (data.historical_avg_expense != null && data.historical_avg_expense > 0) {
    const diff = data.expense - data.historical_avg_expense;
    const label = diff >= 0 ? "超出" : "低于";
    histText = `历史月均支出 ¥${data.historical_avg_expense.toFixed(0)}，当期${label} ¥${Math.abs(diff).toFixed(0)}`;
  }

  // 预算
  let budgetText = data.budget_status ?? "暂无预算数据";

  return `你是一名专业财富顾问，请根据用户在【${data.dimension_name}（${data.period_label}）】内的财务状况，生成一份简洁专业的财务小结。

## 用户财务数据（已为您聚合计算好，无需再查原始明细）

- 当前日期：${data.current_date}
- 时间维度：${data.dimension_name}
- 总收入：¥${data.income.toFixed(0)}
- 总支出：¥${data.expense.toFixed(0)}
- 结余：¥${data.net_saving.toFixed(0)}${data.net_saving < 0 ? "（入不敷出）" : ""}
- 储蓄率：${data.savings_rate.toFixed(0)}%
- 上期收入：¥${data.prev_income.toFixed(0)}
- 上期支出：¥${data.prev_expense.toFixed(0)}
- 支出环比变化：${data.prev_expense > 0 ? ((data.expense - data.prev_expense) >= 0 ? "+¥" : "-¥") + Math.abs(data.expense - data.prev_expense).toFixed(0) : "无上期数据"}
- 收入环比变化：${data.prev_income > 0 ? ((data.income - data.prev_income) >= 0 ? "+¥" : "-¥") + Math.abs(data.income - data.prev_income).toFixed(0) : "无上期数据"}

### 消费结构
${catText}

### 大额 / 异常消费
${largeText}

### 高频消费分类
${data.high_frequency_category ?? "无明显高频消费"}

### 历史对照
${histText}

### 资产配置
${assetText}

### 预算达成
${budgetText}

## 分析维度（作为你内部判断的思考框架，不需要逐项在输出中体现）

1. 资产变化总览：总资产变化金额、增长或下降原因
2. 收支情况：总收入、总支出、结余、储蓄率、收支健康度
3. 消费结构分析：TOP3消费类别、占比、结构特点
4. 异常消费识别：大额消费、高频消费、新增消费类型、超出历史均值消费
5. 趋势变化分析：与上一周期相比明显变化的消费类别、收支变化趋势
6. 收入来源分析：收入构成、收入稳定性
7. 现金流风险分析：当前余额安全性、是否存在资金压力
8. 资产配置分析（若有资产数据）：现金类/投资类占比、配置合理性
9. 用户财务习惯洞察：消费风格和财务特征总结
10. 财务建议：1~3条最有价值的建议

## 时间维度适用性参考

- 日/周（短周期）：重点关注收支情况、消费结构、异常消费、近期趋势对比
- 月：在上述基础上增加趋势变化分析、收入来源分析
- 年/自定义（长周期）：可进一步纳入资产配置分析、现金流风险分析、用户财务习惯洞察、财务建议

## 输出要求

- 不要罗列原始数据，重点输出有价值的洞察和结论
- 语言专业、简洁、有温度
- 字数控制在200~500字
- 优先分析变化、异常和趋势
- 避免空泛建议
- 某分析项数据不足时直接跳过，不要在正文中提及"该项暂无数据"
- 输出内容融合成连贯的自然段落，不使用标题、编号或列表
- 不添加任何开场白或结束语，直接输出小结正文本身
- 最终输出应像私人财富顾问写给用户的一段简短总结

请直接输出小结正文，不要输出 JSON 或其他包装格式。`;
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
    if (!authHeader) {
      return jsonResponse({ error: "未登录" }, 401);
    }

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
    if (authError || !user) {
      return jsonResponse({ error: "身份校验失败" }, 401);
    }

    // ── 2. 会员校验（服务端强校验，防止客户端门禁被绕过）──
    const { data: membership } = await supabase
      .from("memberships")
      .select("status, expires_at")
      .eq("user_id", user.id)
      .maybeSingle();

    const membershipActive =
      membership?.status === "active" &&
      (membership.expires_at === null ||
        new Date(membership.expires_at) > new Date());

    if (!membershipActive) {
      return jsonResponse({ error: "MEMBERSHIP_REQUIRED" }, 402);
    }

    // ── 3. 解析请求 ──
    const body: SummaryRequest = await req.json().catch(() => null);
    if (!body || body.dimension_name == null) {
      return jsonResponse({ error: "缺少必填参数" }, 400);
    }

    // ── 4. 读配置表 ──
    const { data: config, error: configError } = await supabase
      .from("ai_provider_configs")
      .select("*")
      .eq("is_active", true)
      .single();

    if (configError || !config) {
      return jsonResponse({ error: "未找到生效的 AI 提供商配置" }, 500);
    }

    const provider = config as ProviderConfig;

    // ── 5. 取 API Key ──
    const apiKey = Deno.env.get(provider.api_key_secret_name);
    if (!apiKey) {
      return jsonResponse(
        { error: `未配置 ${provider.api_key_secret_name}` },
        500
      );
    }

    // ── 6. 组装 prompt & 调 AI ──
    const prompt = buildPrompt(body);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25_000);

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
          messages: [
            { role: "user", content: prompt },
          ],
          temperature: 0.7,
          max_tokens: 1024,
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
    const content: string | undefined = result.choices?.[0]?.message?.content;

    if (!content || content.trim().length === 0) {
      return jsonResponse({ error: "AI 服务返回了空内容" }, 502);
    }

    // ── 7. 返回小结 ──
    return jsonResponse({ summary: content.trim() });
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
