//
//  PiCotToolsExtension.swift
//
//  CotEditor
//  https://coteditor.com
//
//  ---------------------------------------------------------------------------
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Generates the managed TypeScript extension (`extensions/cot-tools.ts`) loaded by Pi 1.6+ RPC daemons.
///
/// Gives Butler and NEWS AI real callable tools for live stock quotes, local SQLite documents/memory,
/// cached & live news search, web search/fetch, and direct CotEditor UI control via `agent_command_queue`.
nonisolated enum PiCotToolsExtension {
    
    static let filename = "cot-tools.ts"
    
    static let source: String = #"""
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36";
const EM_SEARCH_TOKEN = "D43BF722C8E33DA55D5C6812C6C46";

interface ResolvedInstrument {
  namespace: "sh" | "sz" | "bj" | "hk" | "us";
  symbol: string;
  name: string;
  eastmoneySecID: string;
  tencentCode: string;
}

const ALIAS_CATALOG: Array<{ keys: string[]; inst: ResolvedInstrument }> = [
  { keys: ["hstech", "恒生科技", "恒生科技指数", "恒科"], inst: { namespace: "hk", symbol: "HSTECH", name: "恒生科技指数", eastmoneySecID: "124.HSTECH", tencentCode: "hkHSTECH" } },
  { keys: ["hsi", "恒生指数", "恒指"], inst: { namespace: "hk", symbol: "HSI", name: "恒生指数", eastmoneySecID: "100.HSI", tencentCode: "hkHSI" } },
  { keys: ["上证", "上证指数", "大盘", "000001.sh"], inst: { namespace: "sh", symbol: "000001", name: "上证指数", eastmoneySecID: "1.000001", tencentCode: "sh000001" } },
  { keys: ["沪深300", "hs300", "000300"], inst: { namespace: "sh", symbol: "000300", name: "沪深300", eastmoneySecID: "1.000300", tencentCode: "sh000300" } },
  { keys: ["创业板", "创业板指", "399006"], inst: { namespace: "sz", symbol: "399006", name: "创业板指", eastmoneySecID: "0.399006", tencentCode: "sz399006" } },
  { keys: ["腾讯", "腾讯控股", "00700", "700"], inst: { namespace: "hk", symbol: "00700", name: "腾讯控股", eastmoneySecID: "116.00700", tencentCode: "hk00700" } },
  { keys: ["阿里", "阿里巴巴", "09988", "9988"], inst: { namespace: "hk", symbol: "09988", name: "阿里巴巴-W", eastmoneySecID: "116.09988", tencentCode: "hk09988" } },
  { keys: ["小米", "小米集团", "01810", "1810"], inst: { namespace: "hk", symbol: "01810", name: "小米集团-W", eastmoneySecID: "116.01810", tencentCode: "hk01810" } },
  { keys: ["美团", "03690", "3690"], inst: { namespace: "hk", symbol: "03690", name: "美团-W", eastmoneySecID: "116.03690", tencentCode: "hk03690" } },
  { keys: ["茅台", "贵州茅台", "600519"], inst: { namespace: "sh", symbol: "600519", name: "贵州茅台", eastmoneySecID: "1.600519", tencentCode: "sh600519" } },
  { keys: ["宁德", "宁德时代", "300750"], inst: { namespace: "sz", symbol: "300750", name: "宁德时代", eastmoneySecID: "0.300750", tencentCode: "sz300750" } },
  { keys: ["比亚迪", "002594"], inst: { namespace: "sz", symbol: "002594", name: "比亚迪", eastmoneySecID: "0.002594", tencentCode: "sz002594" } },
  { keys: ["nvda", "nvidia", "英伟达"], inst: { namespace: "us", symbol: "NVDA", name: "英伟达", eastmoneySecID: "105.NVDA", tencentCode: "usNVDA.OQ" } },
  { keys: ["aapl", "apple", "苹果"], inst: { namespace: "us", symbol: "AAPL", name: "苹果", eastmoneySecID: "105.AAPL", tencentCode: "usAAPL.OQ" } },
  { keys: ["msft", "microsoft", "微软"], inst: { namespace: "us", symbol: "MSFT", name: "微软", eastmoneySecID: "105.MSFT", tencentCode: "usMSFT.OQ" } },
  { keys: ["tsla", "tesla", "特斯拉"], inst: { namespace: "us", symbol: "TSLA", name: "特斯拉", eastmoneySecID: "105.TSLA", tencentCode: "usTSLA.OQ" } },
  { keys: ["googl", "goog", "google", "谷歌"], inst: { namespace: "us", symbol: "GOOGL", name: "Alphabet", eastmoneySecID: "105.GOOGL", tencentCode: "usGOOGL.OQ" } },
  { keys: ["meta", "facebook"], inst: { namespace: "us", symbol: "META", name: "Meta", eastmoneySecID: "105.META", tencentCode: "usMETA.OQ" } },
  { keys: ["amzn", "amazon", "亚马逊"], inst: { namespace: "us", symbol: "AMZN", name: "亚马逊", eastmoneySecID: "105.AMZN", tencentCode: "usAMZN.OQ" } },
  { keys: ["tsm", "tsmc", "台积电"], inst: { namespace: "us", symbol: "TSM", name: "台积电", eastmoneySecID: "106.TSM", tencentCode: "usTSM.N" } },
];

function dbPath(): string {
  return (process.env.COT_DB_PATH || "").trim();
}

function sqlQuote(v: string): string {
  return "'" + v.replace(/'/g, "''") + "'";
}

function execFileAsync(
  file: string,
  args: string[],
  timeoutMs = 4000,
  signal?: AbortSignal
): Promise<string> {
  if (signal?.aborted) {
    return Promise.reject(new Error("Aborted"));
  }
  return new Promise((resolve, reject) => {
    const child = execFile(
      file,
      args,
      {
        encoding: "utf8",
        timeout: timeoutMs,
        killSignal: "SIGKILL",
        maxBuffer: 4 * 1024 * 1024,
      },
      (err, stdout) => {
        signal?.removeEventListener("abort", onAbort);
        if (err) {
          reject(err);
        } else {
          resolve(typeof stdout === "string" ? stdout : String(stdout || ""));
        }
      }
    );
    const onAbort = () => {
      try {
        child.kill("SIGKILL");
      } catch {
        // ignore
      }
      reject(new Error("Aborted"));
    };
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

async function runSqliteJson(sql: string, signal?: AbortSignal): Promise<any[]> {
  const p = dbPath();
  if (!p || !existsSync(p)) return [];
  try {
    const out = (
      await execFileAsync("/usr/bin/sqlite3", ["-readonly", "-cmd", ".timeout 2500", "-json", p, sql], 4000, signal)
    ).trim();
    if (!out) return [];
    const parsed = JSON.parse(out);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function enqueueEditorAction(
  actionType: string,
  payloadObj: Record<string, any>,
  signal?: AbortSignal
): Promise<boolean> {
  const p = dbPath();
  if (!p || !existsSync(p)) return false;
  const payloadJSON = JSON.stringify({ ...payloadObj, type: actionType });
  const nowSec = Date.now() / 1000;
  try {
    const sql = `INSERT INTO agent_command_queue (action_type, payload_json, status, result_note, created_at) VALUES (${sqlQuote(actionType)}, ${sqlQuote(payloadJSON)}, 'pending', '', ${nowSec});`;
    await execFileAsync("/usr/bin/sqlite3", ["-cmd", ".timeout 2500", p, sql], 4000, signal);
    return true;
  } catch {
    return false;
  }
}

async function fetchText(
  url: string,
  referer?: string,
  timeoutMs = 7000,
  signal?: AbortSignal,
  maxBytes = 512 * 1024
): Promise<string> {
  if (signal?.aborted) {
    throw new Error("Aborted");
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(new Error(`Timeout after ${timeoutMs}ms`)), timeoutMs);
  const onAbort = () => ctrl.abort(new Error("Aborted"));
  signal?.addEventListener("abort", onAbort, { once: true });
  try {
    const headers: Record<string, string> = { "User-Agent": UA };
    if (referer) headers["Referer"] = referer;
    const res = await fetch(url, { headers, signal: ctrl.signal, redirect: "follow" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    if (!res.body || typeof res.body.getReader !== "function") {
      const full = await res.text();
      return full.slice(0, maxBytes);
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: false });
    let totalBytes = 0;
    let output = "";
    try {
      while (totalBytes < maxBytes) {
        if (ctrl.signal.aborted) {
          throw new Error("Fetch timed out or aborted");
        }
        const { done, value } = await reader.read();
        if (done) break;
        if (value) {
          totalBytes += value.byteLength;
          output += decoder.decode(value, { stream: true });
        }
      }
      output += decoder.decode();
    } finally {
      try {
        await reader.cancel();
      } catch {
        // ignore cancel error
      }
    }
    return output;
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }
}

function currencyForNamespace(ns: ResolvedInstrument["namespace"]): string {
  if (ns === "us") return "$";
  if (ns === "hk") return "HK$";
  return "¥";
}

function normalizeInstrument(item: any): ResolvedInstrument | null {
  const code = String(item?.Code || "").trim();
  const name = String(item?.Name || "").trim();
  const classify = String(item?.Classify || "").toLowerCase();
  const jys = String(item?.JYS || "").toUpperCase();
  const mktNum = String(item?.MktNum || "").trim();
  const quoteID = String(item?.QuoteID || "").trim();
  if (!code || !name) return null;

  let namespace: ResolvedInstrument["namespace"] | null = null;
  if (mktNum === "1" && ["astock", "index", "fund", "bond"].includes(classify)) {
    namespace = "sh";
  } else if (mktNum === "0" && ["astock", "index", "fund", "neeq"].includes(classify)) {
    namespace = classify === "neeq" || /^[489]/.test(code) ? "bj" : "sz";
  } else if (mktNum === "116" && classify === "hk") {
    namespace = "hk";
  } else if ((mktNum === "124" || mktNum === "100") && (jys === "HS" || ["HSTECH", "HSI", "HSCEI"].includes(code.toUpperCase()) || classify === "universalindex")) {
    namespace = "hk";
  } else if (["105", "106", "107"].includes(mktNum) && ["usstock", "usindex", "fund"].includes(classify)) {
    namespace = "us";
  }
  if (!namespace) return null;

  const normalizedSymbol =
    namespace === "hk" && /^\d+$/.test(code) && code.length < 5
      ? code.padStart(5, "0")
      : namespace === "us" || namespace === "hk"
        ? code.toUpperCase()
        : code;

  const eastmoneySecID =
    quoteID ||
    (namespace === "sh"
      ? `1.${normalizedSymbol}`
      : namespace === "sz" || namespace === "bj"
        ? `0.${normalizedSymbol}`
        : namespace === "hk"
          ? (/^\d+$/.test(normalizedSymbol) ? `116.${normalizedSymbol}` : `124.${normalizedSymbol}`)
          : `105.${normalizedSymbol}`);

  const tencentCode =
    namespace === "sh"
      ? `sh${normalizedSymbol}`
      : namespace === "sz"
        ? `sz${normalizedSymbol}`
        : namespace === "bj"
          ? `bj${normalizedSymbol}`
          : namespace === "hk"
            ? `hk${normalizedSymbol}`
            : `us${normalizedSymbol}`;

  return { namespace, symbol: normalizedSymbol, name, eastmoneySecID, tencentCode };
}

async function resolveUSCode(inst: ResolvedInstrument, signal?: AbortSignal): Promise<string> {
  if (inst.namespace !== "us" || inst.tencentCode.includes(".")) return inst.tencentCode;
  try {
    const url = `https://smartbox.gtimg.cn/s3/?v=2&q=${encodeURIComponent(inst.symbol)}&t=all&c=1`;
    const body = await fetchText(url, "https://gu.qq.com/", 4500, signal);
    const re = /us~([A-Za-z0-9.-]+)~/gi;
    let m: RegExpExecArray | null;
    while ((m = re.exec(body)) !== null) {
      const parts = m[1].split(".");
      if (parts.length === 2 && parts[0].toUpperCase() === inst.symbol.toUpperCase()) {
        return `us${parts[0].toUpperCase()}.${parts[1].toUpperCase()}`;
      }
    }
  } catch {
    // ignore fallback
  }
  return `us${inst.symbol}.OQ`;
}

async function resolveStock(query: string, signal?: AbortSignal): Promise<ResolvedInstrument | null> {
  const q = query.trim();
  const lower = q.toLowerCase();
  for (const entry of ALIAS_CATALOG) {
    if (entry.keys.some((k) => k === lower || lower === k.toLowerCase())) {
      return entry.inst;
    }
  }
  try {
    const url = `https://searchapi.eastmoney.com/api/suggest/get?input=${encodeURIComponent(q)}&type=14&token=${EM_SEARCH_TOKEN}&count=10`;
    const raw = await fetchText(url, "https://quote.eastmoney.com/", 5500, signal);
    const parsed = JSON.parse(raw);
    const rows: any[] = parsed?.QuotationCodeTable?.Data || [];
    for (const row of rows) {
      const inst = normalizeInstrument(row);
      if (inst) return inst;
    }
  } catch {
    // ignore suggest failure
  }
  return null;
}

function toNum(v: any): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function decodeHtmlEntities(input: string): string {
  return input
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, n) => {
      const code = Number(n);
      return Number.isFinite(code) ? String.fromCodePoint(code) : "";
    });
}

function stripTags(html: string): string {
  return decodeHtmlEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
      .replace(/<\/(p|div|li|tr|h1|h2|h3|h4|h5|h6|br|article|section)>/gi, "\n")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/[ \t\r]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export default function (pi: ExtensionAPI) {
  // Dynamically reload per-turn system prompt written by CotEditor before every turn.
  pi.on("before_agent_start", async () => {
    const promptFile = (process.env.COT_DYNAMIC_SYSTEM_PROMPT_FILE || "").trim();
    if (promptFile && existsSync(promptFile)) {
      try {
        const dynamicPrompt = readFileSync(promptFile, "utf8").trim();
        if (dynamicPrompt.length > 0) {
          return { systemPrompt: dynamicPrompt };
        }
      } catch {
        // Keep existing system prompt on read failure
      }
    }
    return undefined;
  });

  // Guard built-in shell & filesystem tools from runaway timeouts or scanning `/`
  pi.on("tool_call", async (event: any) => {
    const toolName = String(event?.toolName || "");
    const input = event?.input;
    if (!input || typeof input !== "object") return undefined;

    if (toolName === "bash") {
      const rawTimeout = Number(input.timeout);
      if (!Number.isFinite(rawTimeout) || rawTimeout <= 0 || rawTimeout > 30) {
        input.timeout = 25;
      }
      const cmd = String(input.command || "");
      if (/\b(?:find|rg|grep)\s+\/(?:\s|$)/.test(cmd)) {
        return { block: true, reason: "Refused to scan root directory '/'. Specify a concrete workspace subdirectory." };
      }
    } else if (toolName === "find" || toolName === "grep" || toolName === "ls") {
      const targetPath = String(input.path || "").trim();
      if (targetPath === "/" || (!targetPath && process.cwd() === "/")) {
        return { block: true, reason: "Refused to scan root directory '/'. Specify a concrete file or project path." };
      }
    }
    return undefined;
  });

  // 1. Live Stock Quote & K-Line Lookup
  pi.registerTool({
    name: "lookup_stock_quote",
    label: "查询实时行情",
    description:
      "查询 A股 / 港股 / 美股 / 指数的实时最新价、涨跌幅、今开、最高、最低、成交量及近期日K/周K走势。用户询问任何股票、板块龙头或指数现状时必须先调用本工具获取真实数据，禁止编造价格。",
    parameters: Type.Object({
      query: Type.String({ description: "股票中文名、代码或英文 Ticker，如 三安光电、600703、NVDA、恒生科技、腾讯" }),
      period: Type.Optional(Type.String({ description: "K线周期：day（默认）| week | month" })),
    }),
    async execute(_id, params, signal) {
      const q = String(params.query || "").trim();
      const period = ["day", "week", "month"].includes(String(params.period || "")) ? String(params.period) : "day";
      if (!q) {
        return { content: [{ type: "text", text: "缺少股票名称或代码。" }], details: {} };
      }

      const inst = await resolveStock(q, signal);
      if (!inst) {
        return { content: [{ type: "text", text: `未找到与「${q}」匹配的证券标的，请确认名称或代码。` }], details: {} };
      }
      const tc = await resolveUSCode(inst, signal);

      const klineUrl = `https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=${encodeURIComponent(`${tc},${period},,,40,qfq`)}`;
      const intradayUrl = `https://push2delay.eastmoney.com/api/qt/stock/trends2/get?secid=${encodeURIComponent(inst.eastmoneySecID)}&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13&fields2=f51,f52,f53,f54,f55,f56,f57,f58&iscr=0&ndays=1`;

      const [klineText, intradayText] = await Promise.all([
        fetchText(klineUrl, "https://gu.qq.com/", 6500, signal).catch(() => ""),
        fetchText(intradayUrl, "https://quote.eastmoney.com/", 6500, signal).catch(() => ""),
      ]);

      let bars: Array<{ date: string; open: number; close: number; high: number; low: number; vol: number }> = [];
      let qtLast: number | null = null;
      let qtPrev: number | null = null;
      let qtOpen: number | null = null;
      let qtHigh: number | null = null;
      let qtLow: number | null = null;
      let qtTime = "";
      let qtTurnoverPct: number | null = null;
      let qtPE: number | null = null;
      let qtMarketCap: number | null = null;

      if (klineText) {
        try {
          const root = JSON.parse(klineText);
          const dataObj = root?.data || {};
          const payload = dataObj[tc] || Object.values(dataObj)[0] as any;
          const rawRows: any[] = payload?.[`qfq${period}`] || payload?.[period] || [];
          bars = rawRows
            .map((r) => ({
              date: String(r?.[0] || ""),
              open: toNum(r?.[1]) ?? 0,
              close: toNum(r?.[2]) ?? 0,
              high: toNum(r?.[3]) ?? 0,
              low: toNum(r?.[4]) ?? 0,
              vol: toNum(r?.[5]) ?? 0,
            }))
            .filter((b) => b.close > 0);
          const qtObj = payload?.qt || {};
          const fields: any[] = qtObj[tc] || (Object.values(qtObj)[0] as any) || [];
          if (Array.isArray(fields) && fields.length > 5) {
            qtLast = toNum(fields[3]);
            qtPrev = toNum(fields[4]);
            qtOpen = toNum(fields[5]);
            qtTime = String(fields[30] || "");
            qtHigh = toNum(fields[33]);
            qtLow = toNum(fields[34]);
            qtTurnoverPct = toNum(fields[38]);
            qtPE = toNum(fields[39]);
            qtMarketCap = toNum(fields[45]);
          }
        } catch {
          // ignore parse error
        }
      }

      let intradayLast: number | null = null;
      let intradayPrev: number | null = null;
      let intradayHigh: number | null = null;
      let intradayLow: number | null = null;
      let intradayTime = "";
      if (intradayText) {
        try {
          const env = JSON.parse(intradayText);
          const trends: string[] = env?.data?.trends || [];
          intradayPrev = toNum(env?.data?.preClose);
          if (trends.length > 0) {
            const parsed = trends
              .map((line) => line.split(","))
              .filter((cols) => cols.length >= 5)
              .map((cols) => ({
                time: cols[0],
                close: Number(cols[2]),
                high: Number(cols[3]),
                low: Number(cols[4]),
              }))
              .filter((t) => Number.isFinite(t.close) && t.close > 0);
            if (parsed.length > 0) {
              const last = parsed[parsed.length - 1];
              intradayLast = last.close;
              intradayTime = last.time;
              intradayHigh = Math.max(...parsed.map((p) => p.high));
              intradayLow = Math.min(...parsed.map((p) => p.low));
            }
          }
        } catch {
          // ignore
        }
      }

      const lastPrice = intradayLast ?? qtLast ?? (bars.length ? bars[bars.length - 1].close : null);
      const prevClose = intradayPrev ?? qtPrev ?? (bars.length >= 2 ? bars[bars.length - 2].close : lastPrice);
      const dayOpen = qtOpen ?? (bars.length ? bars[bars.length - 1].open : lastPrice);
      const dayHigh = qtHigh ?? intradayHigh ?? (bars.length ? bars[bars.length - 1].high : lastPrice);
      const dayLow = qtLow ?? intradayLow ?? (bars.length ? bars[bars.length - 1].low : lastPrice);

      if (lastPrice === null) {
        return {
          content: [{ type: "text", text: `已匹配到 ${inst.name} (${inst.namespace.toUpperCase()}:${inst.symbol})，但行情接口暂未返回最新成交价。` }],
          details: { instrument: inst },
        };
      }

      const chg = prevClose ? lastPrice - prevClose : 0;
      const chgPct = prevClose && prevClose > 0 ? (chg / prevClose) * 100 : 0;
      const cur = currencyForNamespace(inst.namespace);
      const sign = chg >= 0 ? "+" : "";

      const lines: string[] = [
        `标的：${inst.name} (${inst.namespace.toUpperCase()}:${inst.symbol} | ${tc})`,
        `最新价：${cur}${lastPrice.toFixed(2)}（${sign}${chg.toFixed(2)} / ${sign}${chgPct.toFixed(2)}%）`,
        `昨收：${prevClose ? cur + prevClose.toFixed(2) : "-"} | 今开：${dayOpen ? cur + dayOpen.toFixed(2) : "-"} | 最高：${dayHigh ? cur + dayHigh.toFixed(2) : "-"} | 最低：${dayLow ? cur + dayLow.toFixed(2) : "-"}`,
      ];
      const extras: string[] = [];
      if (qtTurnoverPct !== null && qtTurnoverPct > 0) extras.push(`换手率 ${qtTurnoverPct.toFixed(2)}%`);
      if (qtPE !== null && qtPE !== 0) extras.push(`市盈率(动) ${qtPE.toFixed(2)}`);
      if (qtMarketCap !== null && qtMarketCap > 0) extras.push(`总市值 ${qtMarketCap.toFixed(2)}亿`);
      if (intradayTime || qtTime) extras.push(`行情时间 ${intradayTime || qtTime}`);
      if (extras.length) lines.push(extras.join(" | "));

      if (bars.length >= 5) {
        const base5 = bars[Math.max(0, bars.length - 6)].close;
        const pct5 = base5 > 0 ? ((lastPrice - base5) / base5) * 100 : 0;
        const base20 = bars[Math.max(0, bars.length - 21)].close;
        const pct20 = base20 > 0 ? ((lastPrice - base20) / base20) * 100 : 0;
        const recent20 = bars.slice(-20);
        const hi20 = Math.max(...recent20.map((b) => b.high));
        const lo20 = Math.min(...recent20.map((b) => b.low));
        lines.push(`区间表现：近5根${pct5 >= 0 ? "+" : ""}${pct5.toFixed(2)}% | 近20根${pct20 >= 0 ? "+" : ""}${pct20.toFixed(2)}% | 近20根区间 ${cur}${lo20.toFixed(2)} ~ ${cur}${hi20.toFixed(2)}`);
        lines.push("最近5根K线：");
        for (const b of bars.slice(-5)) {
          lines.push(`- ${b.date}: 开 ${b.open.toFixed(2)} 收 ${b.close.toFixed(2)} 高 ${b.high.toFixed(2)} 低 ${b.low.toFixed(2)} 量 ${Math.round(b.vol)}`);
        }
      }

      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: { instrument: inst, lastPrice, changePct: chgPct },
      };
    },
  });

  // 2. Search Local Cached NEWS + Live HN Fallback
  pi.registerTool({
    name: "search_news",
    label: "检索资讯热点",
    description: "从 CotEditor 本地 NEWS 缓存（AI/科技/金融等中文热点）和公开资讯流中按关键词检索最新新闻。",
    parameters: Type.Object({
      query: Type.Optional(Type.String({ description: "关键词（留空则返回最新热点前若干条）" })),
      category: Type.Optional(Type.String({ description: "可选分类过滤，如 AI、科技、金融" })),
      limit: Type.Optional(Type.Number({ description: "最多返回条数，默认 8" })),
    }),
    async execute(_id, params, signal) {
      const q = String(params.query || "").trim().toLowerCase();
      const cat = String(params.category || "").trim().toLowerCase();
      const limit = Math.min(20, Math.max(1, Number(params.limit || 8)));
      const matches: string[] = [];

      const rows = await runSqliteJson(`SELECT value FROM configs WHERE key = 'analytics.aiHotNewsCacheJSON' LIMIT 1;`, signal);
      if (rows.length > 0 && typeof rows[0]?.value === "string") {
        try {
          const parsed = JSON.parse(rows[0].value);
          const items: any[] = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.items) ? parsed.items : [];
          for (const item of items) {
            const title = String(item?.title || "").trim();
            const summary = String(item?.summary || "").trim();
            const category = String(item?.category || "").trim();
            const source = String(item?.source || "").trim();
            const url = String(item?.url || "").trim();
            if (!title) continue;
            if (cat && !category.toLowerCase().includes(cat)) continue;
            if (q && !(title.toLowerCase().includes(q) || summary.toLowerCase().includes(q) || category.toLowerCase().includes(q))) {
              continue;
            }
            matches.push(`- [${category || source || "NEWS"}] ${title}${summary ? ` — ${summary.slice(0, 140)}` : ""}${url ? ` (${url})` : ""}`);
            if (matches.length >= limit) break;
          }
        } catch {
          // ignore malformed cache
        }
      }

      if (matches.length < 3 && q) {
        try {
          const hnUrl = `https://hn.algolia.com/api/v1/search_by_date?query=${encodeURIComponent(q)}&tags=story&hitsPerPage=${limit}`;
          const raw = await fetchText(hnUrl, undefined, 5000, signal);
          const data = JSON.parse(raw);
          for (const hit of (data?.hits || []).slice(0, limit - matches.length)) {
            if (!hit?.title) continue;
            matches.push(`- [HN] ${hit.title}${hit.url ? ` (${hit.url})` : ""}`);
          }
        } catch {
          // ignore
        }
      }

      if (matches.length === 0) {
        return { content: [{ type: "text", text: q ? `本地资讯缓存中暂未找到与「${q}」相关的条目，可改用 web_search 检索全网最新消息。` : "本地 NEWS 缓存为空。" }], details: {} };
      }
      return { content: [{ type: "text", text: matches.join("\n") }], details: { count: matches.length } };
    },
  });

  // 3. Web Search (Bing RSS + DuckDuckGo HTML fallback)
  pi.registerTool({
    name: "web_search",
    label: "全网搜索",
    description: "通过搜索引擎查询实时新闻、财报、公告、技术文档或事实信息。",
    parameters: Type.Object({
      query: Type.String({ description: "搜索关键词" }),
      limit: Type.Optional(Type.Number({ description: "返回条数，默认 6" })),
    }),
    async execute(_id, params, signal) {
      const q = String(params.query || "").trim();
      const limit = Math.min(12, Math.max(1, Number(params.limit || 6)));
      if (!q) return { content: [{ type: "text", text: "搜索关键词不能为空。" }], details: {} };

      const results: Array<{ title: string; url: string; snippet: string }> = [];

      // Try Bing RSS first (fast, reliable XML)
      try {
        const rss = await fetchText(`https://www.bing.com/search?format=rss&q=${encodeURIComponent(q)}`, "https://www.bing.com/", 6000, signal);
        const itemRe = /<item>([\s\S]*?)<\/item>/gi;
        let m: RegExpExecArray | null;
        while ((m = itemRe.exec(rss)) !== null && results.length < limit) {
          const block = m[1];
          const title = decodeHtmlEntities((block.match(/<title>([\s\S]*?)<\/title>/i)?.[1] || "").trim());
          const link = decodeHtmlEntities((block.match(/<link>([\s\S]*?)<\/link>/i)?.[1] || "").trim());
          const desc = stripTags(block.match(/<description>([\s\S]*?)<\/description>/i)?.[1] || "");
          if (title && link) results.push({ title, url: link, snippet: desc.slice(0, 200) });
        }
      } catch {
        // fallback below
      }

      if (results.length === 0) {
        try {
          const html = await fetchText(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(q)}`, "https://duckduckgo.com/", 4500, signal);
          const linkRe = /<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
          let m: RegExpExecArray | null;
          while ((m = linkRe.exec(html)) !== null && results.length < limit) {
            const url = decodeHtmlEntities(m[1]);
            const title = stripTags(m[2]);
            if (title) results.push({ title, url, snippet: "" });
          }
        } catch {
          // ignore
        }
      }

      if (results.length === 0) {
        return { content: [{ type: "text", text: `未能从网络获取到「${q}」的搜索结果（可能是网络受限或超时）。` }], details: {} };
      }

      const text = results
        .map((r, i) => `${i + 1}. ${r.title}\n   URL: ${r.url}${r.snippet ? `\n   摘要: ${r.snippet}` : ""}`)
        .join("\n");
      return { content: [{ type: "text", text }], details: { count: results.length } };
    },
  });

  // 4. Web Fetch
  pi.registerTool({
    name: "web_fetch",
    label: "读取网页正文",
    description: "抓取指定 HTTP/HTTPS 网页并提取可读纯文本内容。",
    parameters: Type.Object({
      url: Type.String({ description: "完整 http:// 或 https:// URL" }),
      maxChars: Type.Optional(Type.Number({ description: "最大字符数，默认 6000" })),
    }),
    async execute(_id, params, signal) {
      const url = String(params.url || "").trim();
      if (!/^https?:\/\//i.test(url)) {
        return { content: [{ type: "text", text: "仅支持 http:// 或 https:// 网址。" }], details: {} };
      }
      const maxChars = Math.min(16000, Math.max(500, Number(params.maxChars || 6000)));
      try {
        const html = await fetchText(url, undefined, 8000, signal);
        const text = stripTags(html).slice(0, maxChars);
        return { content: [{ type: "text", text: text || "页面未提取到有效文本。" }], details: { url, chars: text.length } };
      } catch (err: any) {
        const msg = err instanceof Error ? err.message : String(err || "请求超时");
        return {
          content: [{ type: "text", text: `无法抓取该网页（${msg}）。` }],
          details: { url, error: msg },
          isError: true,
        };
      }
    },
  });

  // 5. Read Live CotEditor Workspace Context
  pi.registerTool({
    name: "get_workspace_context",
    label: "感知当前工作区",
    description: "获取用户当前在 CotEditor 中打开的窗口、分屏、标签页、正在编辑的文档正文与选区、当前看盘标的及正在播放的播客。",
    parameters: Type.Object({}),
    async execute(_id, _params, signal) {
      const rows = await runSqliteJson(`SELECT payload_json FROM workspace_live_state WHERE slot = 'active_workspace' LIMIT 1;`, signal);
      if (rows.length === 0 || !rows[0]?.payload_json) {
        return { content: [{ type: "text", text: "当前暂无工作区快照。" }], details: {} };
      }
      try {
        const snap = JSON.parse(String(rows[0].payload_json));
        const parts: string[] = [];
        if (snap.activeDocumentTitle) parts.push(`当前活动文档：${snap.activeDocumentTitle}`);
        if (snap.activeDocumentSelection) parts.push(`当前选中文本：\n${String(snap.activeDocumentSelection).slice(0, 1500)}`);
        if (snap.activeDocumentExcerpt) parts.push(`当前文档内容摘录：\n${String(snap.activeDocumentExcerpt).slice(0, 2400)}`);
        if (snap.activeMarketInstrument) parts.push(`当前看盘标的：${snap.activeMarketInstrument}`);
        if (snap.activePodcastTitle) parts.push(`当前播放播客：${snap.activePodcastTitle}`);
        const tabs: string[] = [];
        for (const w of snap.windows || []) {
          for (const p of w.panes || []) {
            for (const t of p.tabs || []) {
              tabs.push(`${t.isSelected ? "*" : ""}${t.boardKind ? `[${t.boardKind}] ` : ""}${t.title}`);
            }
          }
        }
        if (tabs.length) parts.push(`已打开标签页：${tabs.slice(0, 16).join(" | ")}`);
        return { content: [{ type: "text", text: parts.join("\n\n") || "工作区当前空白。" }], details: {} };
      } catch {
        return { content: [{ type: "text", text: String(rows[0].payload_json).slice(0, 3000) }], details: {} };
      }
    },
  });

  // 6. Search Local CotEditor Documents & Weekly Reports
  pi.registerTool({
    name: "search_documents",
    label: "检索本地笔记与周报",
    description: "在 CotEditor 本地文档库（documents）与周报库（weekly_reports）中按标题或正文关键词检索笔记。",
    parameters: Type.Object({
      query: Type.Optional(Type.String({ description: "关键词（留空则列出最近更新的文档）" })),
      limit: Type.Optional(Type.Number({ description: "最多返回条数，默认 10" })),
      includeWeeklyReports: Type.Optional(Type.Boolean({ description: "是否同时搜索历史周报，默认 true" })),
    }),
    async execute(_id, params, signal) {
      const q = String(params.query || "").trim();
      const limit = Math.min(20, Math.max(1, Number(params.limit || 10)));
      const includeWeekly = params.includeWeeklyReports !== false;
      const likeClause = q ? `AND (title LIKE ${sqlQuote(`%${q}%`)} OR content LIKE ${sqlQuote(`%${q}%`)})` : "";

      const docs = await runSqliteJson(
        `SELECT id, title, group_name, syntax, substr(content, 1, 180) AS snippet, datetime(updated_at, 'unixepoch', 'localtime') AS updated FROM documents WHERE deleted_at IS NULL ${likeClause} ORDER BY updated_at DESC LIMIT ${limit};`,
        signal
      );
      const lines: string[] = [];
      for (const d of docs) {
        const snippet = String(d.snippet || "").replace(/\s+/g, " ").trim();
        lines.push(`- [文档] ${d.title} (id: ${d.id}${d.group_name ? `, 分组: ${d.group_name}` : ""}, 更新: ${d.updated})\n  摘录: ${snippet}`);
      }
      if (includeWeekly) {
        const wClause = q ? `WHERE title LIKE ${sqlQuote(`%${q}%`)} OR content LIKE ${sqlQuote(`%${q}%`)}` : "";
        const reps = await runSqliteJson(
          `SELECT id, period_label, title, substr(content, 1, 160) AS snippet FROM weekly_reports ${wClause} ORDER BY updated_at DESC LIMIT 5;`,
          signal
        );
        for (const r of reps) {
          const snippet = String(r.snippet || "").replace(/\s+/g, " ").trim();
          lines.push(`- [周报 ${r.period_label}] ${r.title} (id: ${r.id})\n  摘录: ${snippet}`);
        }
      }
      return {
        content: [{ type: "text", text: lines.length ? lines.join("\n") : (q ? `未找到包含「${q}」的本地笔记或周报。` : "本地文档库暂无记录。") }],
        details: { count: lines.length },
      };
    },
  });

  // 7. Read Full Document Content
  pi.registerTool({
    name: "read_document",
    label: "读取本地文档全文",
    description: "按文档 ID 或标题读取 CotEditor 本地文档或周报的完整内容。",
    parameters: Type.Object({
      idOrTitle: Type.String({ description: "文档 ID 或标题（支持模糊匹配）" }),
      maxChars: Type.Optional(Type.Number({ description: "最大字符数，默认 8000" })),
    }),
    async execute(_id, params, signal) {
      const target = String(params.idOrTitle || "").trim();
      if (!target) return { content: [{ type: "text", text: "请提供文档 ID 或标题。" }], details: {} };
      const maxChars = Math.min(20000, Math.max(500, Number(params.maxChars || 8000)));

      const exact = await runSqliteJson(
        `SELECT id, title, syntax, content FROM documents WHERE deleted_at IS NULL AND (id = ${sqlQuote(target)} OR title = ${sqlQuote(target)} OR title LIKE ${sqlQuote(`%${target}%`)}) ORDER BY updated_at DESC LIMIT 1;`,
        signal
      );
      if (exact.length > 0) {
        const d = exact[0];
        return {
          content: [{ type: "text", text: `# ${d.title} (${d.syntax})\n\n${String(d.content || "").slice(0, maxChars)}` }],
          details: { id: d.id },
        };
      }
      const rep = await runSqliteJson(
        `SELECT id, period_label, title, content FROM weekly_reports WHERE id = ${sqlQuote(target)} OR title LIKE ${sqlQuote(`%${target}%`)} ORDER BY updated_at DESC LIMIT 1;`,
        signal
      );
      if (rep.length > 0) {
        const r = rep[0];
        return {
          content: [{ type: "text", text: `# [${r.period_label}] ${r.title}\n\n${String(r.content || "").slice(0, maxChars)}` }],
          details: { id: r.id },
        };
      }
      return { content: [{ type: "text", text: `未找到名为「${target}」的本地文档。` }], details: {} };
    },
  });

  // 8. Read User KYC Memory & Watchlist / Follows
  pi.registerTool({
    name: "read_memory",
    label: "读取长期记忆与自选清单",
    description: "读取用户的 KYC 长期记忆画像、股票自选池、关注的信息源与创作者列表。",
    parameters: Type.Object({}),
    async execute(_id, _params, signal) {
      const [memories, stocks, feeds, creators] = await Promise.all([
        runSqliteJson(
          `SELECT dimension, fact_key, title, detail, is_pinned FROM user_kyc_memories WHERE is_archived = 0 ORDER BY is_pinned DESC, confidence DESC, updated_at DESC LIMIT 40;`,
          signal
        ),
        runSqliteJson(
          `SELECT instrument_id, symbol, name, thesis_note, last_price, last_change_pct FROM user_watchlist_stocks ORDER BY sort_order ASC, updated_at DESC LIMIT 30;`,
          signal
        ),
        runSqliteJson(`SELECT title, site_url, category FROM user_followed_feeds ORDER BY is_pinned DESC, updated_at DESC LIMIT 20;`, signal),
        runSqliteJson(`SELECT platform, handle, display_name, why_following FROM user_followed_creators ORDER BY is_pinned DESC, updated_at DESC LIMIT 20;`, signal),
      ]);

      const sections: string[] = [];
      if (memories.length) {
        sections.push(
          "## 用户长期记忆\n" +
            memories.map((m) => `- [${m.dimension}${m.is_pinned ? " ★" : ""}] ${m.title}${m.detail ? `：${m.detail}` : ""}`).join("\n")
        );
      }
      if (stocks.length) {
        sections.push(
          "## 自选股票\n" +
            stocks
              .map((s) => `- ${s.name} (${s.symbol})${s.last_price ? ` 现价 ${s.last_price}` : ""}${s.thesis_note ? ` | 逻辑：${s.thesis_note}` : ""}`)
              .join("\n")
        );
      }
      if (feeds.length) {
        sections.push("## 关注信息源\n" + feeds.map((f) => `- ${f.title} (${f.site_url})`).join("\n"));
      }
      if (creators.length) {
        sections.push("## 关注创作者\n" + creators.map((c) => `- @${c.handle} (${c.platform}) ${c.display_name || ""} ${c.why_following || ""}`).join("\n"));
      }
      return { content: [{ type: "text", text: sections.join("\n\n") || "暂无已保存的长期记忆与自选资产。" }], details: {} };
    },
  });

  // 9. Native CotEditor UI & Memory Action Bridge
  pi.registerTool({
    name: "editor_action",
    label: "执行编辑器操作",
    description:
      "向 CotEditor 发送即时操作指令：打开/切换看盘(market)/播客(podcast)/资讯(news)/总管(butler)看板、新建文档(open_document)、向当前编辑器插入文本(insert_to_editor)、加减自选股(watch_stock/unwatch_stock)、写入或删除长期记忆(upsert_memory/delete_memory)、改名(rename_butler)、调整 Bot 人设(update_bot/update_global_persona)、关注信息源/博主(follow_feed/follow_creator)。",
    parameters: Type.Object({
      type: Type.String({
        description:
          "动作类型：open_board | convert_tab | open_document | insert_to_editor | watch_stock | unwatch_stock | upsert_memory | delete_memory | rename_butler | update_bot | update_global_persona | play_podcast | follow_feed | follow_creator",
      }),
      board: Type.Optional(Type.String({ description: "看板类型：market | podcast | news | butler | document" })),
      query: Type.Optional(Type.String({ description: "标的/搜索词（如 三安光电、NVDA）" })),
      splitRight: Type.Optional(Type.Boolean({ description: "是否在右侧新建分屏打开" })),
      title: Type.Optional(Type.String({ description: "文档标题或记忆标题" })),
      content: Type.Optional(Type.String({ description: "新建文档内容" })),
      text: Type.Optional(Type.String({ description: "insert_to_editor 要插入的文本" })),
      replaceSelection: Type.Optional(Type.Boolean({ description: "是否替换当前选区" })),
      dimension: Type.Optional(Type.String({ description: "记忆维度：identity|cognition|writingStyle|goals|finance|informationDiet|workflow|taboos" })),
      key: Type.Optional(Type.String({ description: "记忆 key" })),
      detail: Type.Optional(Type.String({ description: "详细说明" })),
      isPinned: Type.Optional(Type.Boolean({ description: "是否置顶记忆" })),
      keyOrID: Type.Optional(Type.String({ description: "要删除的记忆 key 或 ID" })),
      thesis: Type.Optional(Type.String({ description: "股票关注逻辑" })),
      symbolOrID: Type.Optional(Type.String({ description: "股票代码或 instrument_id" })),
      name: Type.Optional(Type.String({ description: "总管新名字" })),
      nickname: Type.Optional(Type.String({ description: "总管新称呼" })),
      botID: Type.Optional(Type.String({ description: "Bot ID" })),
      persona: Type.Optional(Type.String({ description: "人设提示词" })),
      prompt: Type.Optional(Type.String({ description: "全局人设提示词" })),
      modelOverride: Type.Optional(Type.String({ description: "Bot 模型覆盖" })),
      isEnabled: Type.Optional(Type.Boolean({ description: "是否启用 Bot" })),
      siteURL: Type.Optional(Type.String({ description: "信息源网址" })),
      feedURL: Type.Optional(Type.String({ description: "RSS 地址" })),
      category: Type.Optional(Type.String({ description: "分类" })),
      platform: Type.Optional(Type.String({ description: "创作者平台，如 x" })),
      handle: Type.Optional(Type.String({ description: "创作者 handle" })),
      displayName: Type.Optional(Type.String({ description: "创作者名称" })),
      why: Type.Optional(Type.String({ description: "关注原因" })),
    }),
    async execute(_id, params, signal) {
      const actionType = String(params.type || "").trim();
      if (!actionType) {
        return { content: [{ type: "text", text: "缺少 action type。" }], details: {} };
      }
      const ok = await enqueueEditorAction(actionType, params as Record<string, any>, signal);
      if (!ok) {
        return {
          content: [{ type: "text", text: `未能将操作 ${actionType} 写入本地队列（COT_DB_PATH 不可用）。` }],
          details: { ok: false, actionType },
        };
      }
      const label = [actionType, params.board, params.query, params.title, params.name].filter(Boolean).join(" · ");
      return {
        content: [{ type: "text", text: `已下发编辑器操作：${label}（CotEditor 将立即执行）。` }],
        details: { ok: true, actionType, label },
      };
    },
  });
}
"""#
}
