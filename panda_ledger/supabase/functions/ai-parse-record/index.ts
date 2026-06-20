/// ============================================================
/// 熊猫记账 — AI 智能记账解析 Edge Function
///
/// 部署命令: supabase functions deploy ai-parse-record
///
/// 请求参数:
///   - mode: "single"（单笔识别）或 "batch"（一口气批量识别）
///   - input_text: 用户输入的原始文本
///
/// 返回:
///   - single 模式: { data: { type, amount, ... } }
///   - batch 模式:  { data: [{ type, amount, ... }, ...] }
///   - 错误:        { error: "错误信息" }
///
/// 需要的 Supabase Secrets:
///   - 按 ai_provider_configs 表中 api_key_secret_name 的值配置对应 Secret
///   - 例如: DEEPSEEK_API_KEY=sk-xxx
/// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── CORS ──
const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── 类型 ──
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

interface RequestBody {
  mode: "single" | "batch";
  input_text: string;
}

// ═══════════════════════════════════════════════════════════════
// 提示词模板（与 App 原版保持一致）
// ═══════════════════════════════════════════════════════════════

function singleSystemPrompt(catList: string, acctList: string): string {
  return `你是一个记账助手。用户会用中文描述一笔账单，你需要提取结构化信息并返回 JSON。

## 字段说明
- type: "expense"（支出）或 "income"（收入）
- amount: 金额数字（如 32.0）
- categoryName: 不再使用此字段，始终留空
- categoryId: 不再使用此字段，始终留空
- subcategoryName: 子分类名称（二级分类），从候选列表中做语义匹配，这是最细粒度的分类
- subcategoryId: 子分类 ID（候选列表中有），对应 subcategoryName
- accountName: 账户名称，从候选列表中做语义匹配
- accountId: 账户 ID（候选列表中有），对应 accountName；匹配不到则设为 null
- note: 一句完整通顺的中文自然语言描述，概括这笔账单的关键信息（如"购买钢笔一支"、"打车去公司"、"午餐宫保鸡丁饭"），不要分词堆砌，不要只有关键词
- occurredAt: ISO 8601 日期字符串，默认今天
- matchType: "existing"（已有分类匹配）/ "suggestNew"（建议新分类）/ "partial"（部分识别）
- newCategorySuggestion: 当 matchType 为 "suggestNew" 时的建议分类名，格式为"一级分类名→二级分类名"
- confidence: 0.0~1.0 之间的置信度

## 已有分类（名称→ID映射）
${catList}

## 已有账户（名称→ID映射）
${acctList}

## 核心规则
1. **分类模糊匹配**：用户可能用口语化称呼（如"午饭"指"午餐"、"夜宵"指"宵夜"、"星巴克"指"咖啡"），请根据语义相似度在已有分类列表中寻找最接近的匹配，不要求字符串完全一致。只匹配到二级分类（叶子节点）。
2. **分类匹配不到**：如果找不到合适的已有分类，matchType 设为 "suggestNew"，newCategorySuggestion 格式为"一级分类名→二级分类"（如"餐饮→快餐"）。
3. **账户模糊匹配**：用户可能用简称（如"花呗"指"支付宝花呗"），请在已有账户列表中按语义匹配最近的账户。如果确实匹配不到任何已有账户，accountId 和 accountName 都设为 null（不要凭空生成账户名称）。
4. **金额转换**：金额单位如果是"万"，转换为数字（如 1万 = 10000）。
5. **备注生成**：note 必须是完整通顺的中文短句，读起来像自然的日常记账备注。例如："午餐点了一份宫保鸡丁饭，花费35元"→"午餐宫保鸡丁饭"；"昨天打车从公司回家花了32元"→"打车回家"。不要分词堆砌。
6. 只返回 JSON，不要其他文字`;
}

function batchSystemPrompt(catList: string, acctList: string): string {
  return `你是批量记账助手。用户输入一段文本，可能包含多笔独立的收支记录。

## 工作步骤
1. **拆分**：先判断输入文本中包含几笔独立的收支事件。按消费/收入行为拆分，不要仅按标点分割。例如："中午吃饭35元，晚上看电影60元"应拆为2笔。
2. **逐笔提取**：对拆分出的每一笔，分别提取以下字段。
3. **返回**：JSON 数组 [{...}, {...}]，每笔一个对象。

## 每笔字段说明
- type: "expense"（支出）或 "income"（收入）
- amount: 金额数字（如 32.0）
- categoryName: 始终留空
- categoryId: 始终留空
- subcategoryName: 二级分类名称，从候选列表做语义匹配
- subcategoryId: 子分类 ID（候选列表中有）
- accountName: 账户名称，从候选列表语义匹配；匹配不到则设为 null
- accountId: 账户 ID，匹配不到则设为 null
- note: 完整通顺的中文短句，不是分词堆砌
- occurredAt: 不输出此字段，日期由 App 端统一设为当天
- matchType: "existing" / "suggestNew" / "partial"
- newCategorySuggestion: 当 matchType 为 "suggestNew" 时，格式"一级分类名→二级分类名"
- confidence: 0.0~1.0

## 已有分类（名称→ID映射）
${catList}

## 已有账户（名称→ID映射）
${acctList}

## 核心规则
1. **拆分判断**：仔细分析语义，将不同时间/场景/对象的收支事件拆开。不要合并，也不要漏掉任何一笔。
2. **分类模糊匹配**：用户可能用口语化称呼，请在已有分类列表中按语义相似度匹配最近的，不要求字符串完全一致。
3. **分类匹配不到**：matchType 设为 "suggestNew"，newCategorySuggestion 格式"一级分类名→二级分类"。
4. **账户模糊匹配**：优先在已有账户列表中匹配。如果确实匹配不到，accountId 和 accountName 设为 null。
5. **金额转换**："万"转换为数字（1万=10000）。
6. **备注生成**：每笔的 note 必须是完整通顺的中文短句。
7. **不要识别日期**：不要从文本中提取日期信息，occurredAt 字段不要输出。
8. 只返回 JSON 数组，不要其他文字`;
}

// ═══════════════════════════════════════════════════════════════
// 主处理
// ═══════════════════════════════════════════════════════════════

serve(async (req: Request): Promise<Response> => {
  // CORS 预检
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 只接受 POST
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
      return jsonResponse({ error: "未登录，请先登录后再使用 AI 识别" }, 401);
    }

    // 用用户的 JWT 创建 Supabase 客户端（后续 DB 查询自动遵守 RLS）
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonResponse(
        { error: "服务端配置缺失：SUPABASE_URL / SUPABASE_ANON_KEY" },
        500
      );
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return jsonResponse({ error: "身份校验失败，请重新登录" }, 401);
    }

    // ── 2. 解析请求参数 ──
    const body: RequestBody = await req.json().catch(() => ({} as RequestBody));
    const { mode, input_text } = body;

    if (!mode || !input_text) {
      return jsonResponse(
        { error: "缺少必填参数 mode（single / batch）或 input_text（用户输入文本）" },
        400
      );
    }

    if (mode !== "single" && mode !== "batch") {
      return jsonResponse({ error: "mode 必须为 single 或 batch" }, 400);
    }

    if (input_text.trim().length === 0) {
      return jsonResponse({ error: "input_text 不能为空" }, 400);
    }

    // ── 3. 查询生效的 AI 提供商配置 ──
    const { data: config, error: configError } = await supabase
      .from("ai_provider_configs")
      .select("*")
      .eq("is_active", true)
      .single();

    if (configError || !config) {
      return jsonResponse(
        { error: "未找到生效的 AI 提供商配置，请先在 ai_provider_configs 表中设置 is_active=true" },
        500
      );
    }

    const provider = config as ProviderConfig;

    // ── 4. 从 Secrets 取 API Key ──
    const apiKey = Deno.env.get(provider.api_key_secret_name);
    if (!apiKey) {
      return jsonResponse(
        {
          error: `AI 服务未配置：请在 Supabase Edge Function Secrets 中添加 ${provider.api_key_secret_name}`,
        },
        500
      );
    }

    // ── 5. 查询用户的账户和分类（RLS 自动限制为当前用户数据）──
    const [{ data: accounts }, { data: categories }] = await Promise.all([
      supabase.from("accounts").select("id, name").eq("deleted", false),
      supabase.from("categories").select("id, name, parent_id").eq("deleted", false),
    ]);

    const catMap: Record<string, string> = {};
    for (const c of categories ?? []) {
      catMap[c.name] = c.id;
    }
    const acctMap: Record<string, string> = {};
    for (const a of accounts ?? []) {
      acctMap[a.name] = a.id;
    }

    // ── 6. 组装 prompt ──
    const catList = Object.entries(catMap)
      .map(([name, id]) => `- ${name} (id: ${id})`)
      .join("\n");
    const acctList = Object.entries(acctMap)
      .map(([name, id]) => `- ${name} (id: ${id})`)
      .join("\n");

    const systemPrompt =
      mode === "batch"
        ? batchSystemPrompt(catList, acctList)
        : singleSystemPrompt(catList, acctList);

    // ── 7. 调用 AI 服务 ──
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25_000); // 25s 超时

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
            { role: "system", content: systemPrompt },
            { role: "user", content: input_text.trim() },
          ],
          temperature: 0.1,
          max_tokens: mode === "batch" ? 2048 : 512,
          // single 模式强制 JSON 输出，batch 模式不设置以返回数组
          ...(mode === "single" ? { response_format: { type: "json_object" } } : {}),
        }),
        signal: controller.signal,
      });
    } catch (fetchErr) {
      clearTimeout(timeout);
      if (fetchErr.name === "AbortError") {
        return jsonResponse(
          { error: "AI 服务响应超时（超过 25 秒），请稍后重试" },
          504
        );
      }
      return jsonResponse(
        { error: `调用 AI 服务失败: ${fetchErr.message}` },
        502
      );
    } finally {
      clearTimeout(timeout);
    }

    if (!aiResponse.ok) {
      let errDetail = "";
      try {
        errDetail = await aiResponse.text();
        // 截断过长的错误信息
        if (errDetail.length > 500) errDetail = errDetail.slice(0, 500) + "…";
      } catch {
        errDetail = "(无法读取错误详情)";
      }
      return jsonResponse(
        {
          error: `AI 服务 (${provider.display_name}) 返回错误 (${aiResponse.status})`,
          detail: errDetail,
        },
        502
      );
    }

    const result = await aiResponse.json();
    const content: string | undefined = result.choices?.[0]?.message?.content;

    if (!content) {
      return jsonResponse(
        { error: `AI 服务 (${provider.display_name}) 返回了空内容` },
        502
      );
    }

    // ── 8. 解析 AI 返回内容 ──
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch {
      return jsonResponse(
        {
          error: "AI 服务返回了无法解析的内容",
          raw: content.slice(0, 300),
        },
        502
      );
    }

    // ── 9. 返回结构化结果 ──
    if (mode === "single") {
      return jsonResponse({ data: parsed });
    }

    // batch 模式：规范化数组输出
    let list: unknown[];
    if (Array.isArray(parsed)) {
      list = parsed;
    } else if (typeof parsed === "object" && parsed !== null) {
      const obj = parsed as Record<string, unknown>;
      const raw =
        obj.transactions ?? obj.items ?? obj.results ?? obj.records ?? obj.data;
      list = Array.isArray(raw) ? raw : [];
    } else {
      list = [];
    }

    // 过滤掉完全无结果的条目
    const filtered = list.filter((item: unknown) => {
      if (typeof item !== "object" || item === null) return false;
      const t = item as Record<string, unknown>;
      return t.amount != null || t.type != null;
    });

    return jsonResponse({ data: filtered });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: `服务内部错误: ${message}` }, 500);
  }
});

// ── 辅助：返回 JSON 响应 ──
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
