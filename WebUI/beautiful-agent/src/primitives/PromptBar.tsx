import { useEffect, useImperativeHandle, useLayoutEffect, useRef, useState, forwardRef, type ReactNode } from "react";
import { createShader, playSweep, accentChain, ACCENTS } from "glimm";
import type { ContextSourceItem, EffortLevel, ModelOption, SlashCommandItem } from "../types";

/* ─────────────────────────────────────────────────────────
 * PROMPT BAR (adapted directly from beautifului.dev)
 * Real composer with:
 *   · @ context sources + / slash commands with gliding hover highlight
 *   · Model picker with gliding hover highlight + rainbow glimm sweep
 *   · Quoted passage attachment pill
 *   · Optional reasoning effort toggle (News mode)
 *   · Tactile Send ↔ Stop button
 * ───────────────────────────────────────────────────────── */

const RAINBOW = accentChain([
  ACCENTS.red,
  ACCENTS.orange,
  ACCENTS.yellow,
  ACCENTS.green,
  ACCENTS.cyan,
  ACCENTS.blue,
  ACCENTS.purple,
]);

function Icon({ children, size = 15, strokeWidth = 1.8 }: { children: ReactNode; size?: number; strokeWidth?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

const SOURCE_GLYPHS: Record<ContextSourceItem["glyph"], ReactNode> = {
  doc: (
    <g>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <path d="M14 2v6h6M8 13h8M8 17h5" />
    </g>
  ),
  selection: (
    <g>
      <path d="M4 7h16M4 12h10M4 17h13" />
    </g>
  ),
  market: <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />,
  news: (
    <g>
      <path d="M4 5h16v14H4z" />
      <path d="M8 9h8M8 13h5" />
    </g>
  ),
  memory: (
    <g>
      <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
    </g>
  ),
  globe: (
    <g>
      <circle cx="12" cy="12" r="10" />
      <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
    </g>
  ),
};

function parseToken(draft: string): { kind: "at" | "slash"; query: string; start: number } | null {
  const match = /(^|\s)([@/])([^\s]*)$/.exec(draft);
  if (!match) return null;
  return {
    kind: match[2] === "@" ? "at" : "slash",
    query: match[3].toLowerCase(),
    start: match.index + match[1].length,
  };
}

export type PromptBarHandle = {
  focus: () => void;
  setDraft: (text: string) => void;
};

type PromptBarProps = {
  placeholder: string;
  locale: "zh" | "en";
  isStreaming: boolean;
  tall?: boolean;
  availableModels: ModelOption[];
  selectedModelID: string;
  selectedModelTitle: string;
  contextSources: ContextSourceItem[];
  slashCommands: SlashCommandItem[];
  quotedExcerpt?: string | null;
  effort?: EffortLevel;
  showEffort?: boolean;
  onClearQuote?: () => void;
  onSelectModel: (model: ModelOption) => void;
  onSelectEffort?: (effort: EffortLevel) => void;
  onOpenSettings: () => void;
  onSend: (text: string) => void;
  onAbort: () => void;
};

const PromptBar = forwardRef<PromptBarHandle, PromptBarProps>(function PromptBar(
  {
    placeholder,
    locale,
    isStreaming,
    tall = false,
    availableModels,
    selectedModelID,
    selectedModelTitle,
    contextSources,
    slashCommands,
    quotedExcerpt,
    effort = "balanced",
    showEffort = false,
    onClearQuote,
    onSelectModel,
    onSelectEffort,
    onOpenSettings,
    onSend,
    onAbort,
  },
  ref,
) {
  const [draft, setDraft] = useState("");
  const [dismissed, setDismissed] = useState(false);
  const [plusOpen, setPlusOpen] = useState(false);
  const [modelOpen, setModelOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [engaged, setEngaged] = useState(false);
  const [rowBox, setRowBox] = useState<{ top: number; height: number } | null>(null);
  const [modelBox, setModelBox] = useState<{ top: number; height: number } | null>(null);
  const [modelHovered, setModelHovered] = useState<number | null>(null);
  const [modelMenuLeft, setModelMenuLeft] = useState(0);
  const [modelMenuBottom, setModelMenuBottom] = useState(0);

  const composerAnchorRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const modelRef = useRef<HTMLButtonElement>(null);
  const rowRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const modelRowRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const glimmRef = useRef<HTMLCanvasElement>(null);
  const shaderRef = useRef<ReturnType<typeof createShader> | null>(null);
  const sweepingRef = useRef(false);

  useImperativeHandle(ref, () => ({
    focus: () => inputRef.current?.focus(),
    setDraft: (text: string) => {
      setDraft(text);
      setDismissed(true);
      requestAnimationFrame(() => inputRef.current?.focus());
    },
  }));

  const token = dismissed ? null : parseToken(draft);
  const menu: "at" | "slash" | null = plusOpen ? "at" : token?.kind ?? null;
  const query = plusOpen ? "" : token?.query ?? "";

  const rows =
    menu === "at"
      ? contextSources.filter(
          (s) => s.name.toLowerCase().includes(query) || s.desc.toLowerCase().includes(query) || s.key.includes(query),
        )
      : menu === "slash"
        ? slashCommands.filter(
            (c) => c.name.slice(1).toLowerCase().includes(query) || c.desc.toLowerCase().includes(query),
          )
        : [];

  useEffect(() => {
    setActive(0);
    setEngaged(false);
  }, [menu, query]);

  useLayoutEffect(() => {
    const target = rowRefs.current[active];
    if (target) setRowBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [menu, query, active, rows.length]);

  const modelIndex = Math.max(
    0,
    availableModels.findIndex((m) => m.modelID === selectedModelID || m.title === selectedModelTitle),
  );

  useLayoutEffect(() => {
    if (!modelOpen) return;
    const target = modelRowRefs.current[modelHovered ?? modelIndex];
    if (target) setModelBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [modelOpen, modelHovered, modelIndex]);

  useLayoutEffect(() => {
    if (!modelOpen || !composerAnchorRef.current || !modelRef.current) return;
    const anchorRect = composerAnchorRef.current.getBoundingClientRect();
    const triggerRect = modelRef.current.getBoundingClientRect();
    setModelMenuLeft(Math.max(0, Math.min(triggerRect.left - anchorRect.left, Math.max(0, anchorRect.width - 210))));
    setModelMenuBottom(anchorRect.bottom - triggerRect.top + 8);
  }, [modelOpen, selectedModelTitle]);

  useEffect(() => {
    if (!modelOpen) setModelHovered(null);
  }, [modelOpen]);

  // Glimm rainbow shader sweep when switching flagship models
  const makeShader = () => {
    const canvas = glimmRef.current;
    if (!canvas) return null;
    const random = Math.random;
    Math.random = () => 0;
    try {
      return createShader({
        canvas,
        palette: RAINBOW,
        direction: "ltr",
        bandTight: 10,
        swellAmount: 0.85,
      });
    } catch {
      return null;
    } finally {
      Math.random = random;
    }
  };

  useEffect(() => {
    shaderRef.current = makeShader();
    return () => {
      try {
        shaderRef.current?.destroy();
      } catch {}
      shaderRef.current = null;
    };
  }, []);

  const celebrate = () => {
    if (sweepingRef.current) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    try {
      shaderRef.current?.destroy();
      const shader = makeShader();
      shaderRef.current = shader;
      if (!shader) return;
      sweepingRef.current = true;
      const sweep = playSweep(shader, {
        palette: RAINBOW,
        direction: "ltr",
        sweepMs: 540,
        outroMs: 80,
        peakAlpha: 1.15,
        bandTight: 10,
        brightness: 1.35,
        swellAmount: 0.95,
        waveSpeed: 1.8,
        easing: "easeOutExpo",
      });
      sweep.done.finally(() => {
        sweepingRef.current = false;
      });
    } catch {
      sweepingRef.current = false;
    }
  };

  // Auto-size textarea cleanly
  useLayoutEffect(() => {
    const input = inputRef.current;
    if (!input) return;
    const minH = tall ? 46 : 26;
    const maxH = 128;
    input.style.height = "0px";
    const h = input.scrollHeight;
    input.style.height = `${Math.min(Math.max(h, minH), maxH)}px`;
    input.style.overflowY = h > maxH ? "auto" : "hidden";
  }, [draft, tall]);

  useEffect(() => {
    if (!modelOpen && !plusOpen) return;
    const close = (event: PointerEvent) => {
      if (!(event.target as Element).closest("[data-promptbar]")) {
        setModelOpen(false);
        setPlusOpen(false);
      }
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [modelOpen, plusOpen]);

  const closeMenus = () => {
    setPlusOpen(false);
    setModelOpen(false);
  };

  const pickRow = (row: ContextSourceItem | SlashCommandItem) => {
    const prefix = token ? draft.slice(0, token.start) : draft;
    setDraft(`${prefix}${row.insertText} `);
    setPlusOpen(false);
    setDismissed(true);
    inputRef.current?.focus();
  };

  const canSend = !isStreaming && draft.trim().length > 0;
  const submit = () => {
    if (!canSend) return;
    const text = draft.trim();
    setDraft("");
    closeMenus();
    onSend(text);
  };

  const cycleEffort = () => {
    if (!onSelectEffort) return;
    const order: EffortLevel[] = ["simple", "balanced", "deep"];
    const next = order[(order.indexOf(effort) + 1) % order.length];
    onSelectEffort(next);
  };

  const effortLabel =
    locale === "zh"
      ? effort === "simple"
        ? "快速"
        : effort === "deep"
          ? "深度"
          : "均衡"
      : effort === "simple"
        ? "Fast"
        : effort === "deep"
          ? "Deep"
          : "Balanced";

  return (
    <div data-promptbar className="w-full">
      <div ref={composerAnchorRef} className="relative">
        {/* ── @ / slash menu ─────────────────────────────── */}
        {menu && (
          <div
            onMouseLeave={() => setEngaged(false)}
            className="absolute inset-x-0 bottom-full z-20 mb-2 max-h-60 overflow-y-auto rounded-[10px] bg-surface p-1 shadow-raised bui-scroll"
            style={{ animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "bottom center" }}
          >
            <span
              aria-hidden
              className="pointer-events-none absolute inset-x-1 rounded-[6px] bg-hover"
              style={{
                top: rowBox?.top ?? 0,
                height: rowBox?.height ?? 0,
                opacity: rowBox && engaged && rows.length > 0 ? 1 : 0,
                transition:
                  "top 200ms cubic-bezier(0.23,1,0.32,1), height 200ms cubic-bezier(0.23,1,0.32,1), opacity 140ms ease",
              }}
            />
            {rows.map((row, i) => {
              const sourceRow = "glyph" in row ? (row as ContextSourceItem) : null;
              return (
                <button
                  key={row.key}
                  type="button"
                  ref={(el) => {
                    rowRefs.current[i] = el;
                  }}
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseEnter={() => {
                    setActive(i);
                    setEngaged(true);
                  }}
                  onClick={() => pickRow(row)}
                  className="relative z-10 flex h-8.5 w-full items-center gap-2.5 rounded-[6px] px-2 text-left"
                >
                  {sourceRow && (
                    <span className="flex size-5 shrink-0 items-center justify-center text-ink-2">
                      <Icon size={14}>{SOURCE_GLYPHS[sourceRow.glyph]}</Icon>
                    </span>
                  )}
                  <span className="shrink-0 text-[12.5px] font-medium text-ink">{row.name}</span>
                  <span className="min-w-0 flex-1 truncate text-[11.5px] text-ink-3">{row.desc}</span>
                </button>
              );
            })}
            {rows.length === 0 && (
              <div className="flex h-8 items-center px-2 text-[12px] text-ink-3">
                {locale === "zh" ? `没有匹配“${query}”` : `No matches for "${query}"`}
              </div>
            )}
            <div className="mt-1 border-t border-line px-2 pt-1.5 pb-1 text-[10.5px] text-ink-3">
              {menu === "at"
                ? locale === "zh"
                  ? "选择要带入的上下文来源"
                  : "Attach workspace context"
                : locale === "zh"
                  ? "选择快捷指令（↑↓ 选择，Enter 插入）"
                  : "Choose a command"}
            </div>
          </div>
        )}

        {/* ── model menu ─────────────────────────────────── */}
        {modelOpen && (
          <div
            onMouseLeave={() => setModelHovered(null)}
            className="bui-scroll absolute z-20 max-h-60 w-52 overflow-y-auto rounded-[10px] bg-surface p-1 shadow-raised"
            style={{
              left: modelMenuLeft,
              bottom: modelMenuBottom,
              animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both",
              transformOrigin: "bottom left",
            }}
          >
            <span
              aria-hidden
              className="pointer-events-none absolute inset-x-1 rounded-[6px] bg-hover"
              style={{
                top: modelBox?.top ?? 0,
                height: modelBox?.height ?? 0,
                opacity: modelBox && modelHovered !== null ? 1 : 0,
                transition:
                  "top 200ms cubic-bezier(0.23,1,0.32,1), height 200ms cubic-bezier(0.23,1,0.32,1), opacity 140ms ease",
              }}
            />
            {availableModels.length === 0 ? (
              <button
                type="button"
                onClick={() => {
                  setModelOpen(false);
                  onOpenSettings();
                }}
                className="relative z-10 flex h-8 w-full items-center gap-2 rounded-[6px] px-2 text-left text-[12px] font-medium text-accent-ink hover:bg-hover"
              >
                {locale === "zh" ? "前往设置配置 API 网关…" : "Configure AI models…"}
              </button>
            ) : (
              availableModels.map((m, i) => {
                const isSelected = m.modelID === selectedModelID || m.title === selectedModelTitle;
                return (
                  <button
                    key={m.id}
                    type="button"
                    ref={(el) => {
                      modelRowRefs.current[i] = el;
                    }}
                    onMouseDown={(event) => event.preventDefault()}
                    onMouseEnter={() => setModelHovered(i)}
                    onClick={() => {
                      onSelectModel(m);
                      setModelOpen(false);
                      if (m.isFlagship) celebrate();
                      inputRef.current?.focus();
                    }}
                    className="relative z-10 flex h-7.5 w-full items-center gap-2 rounded-[6px] px-2 text-left"
                  >
                    <span className="min-w-0 flex-1 truncate text-[12px] font-medium text-ink">{m.title}</span>
                    {m.tag && <span className="shrink-0 text-[10.5px] text-ink-3">{m.tag}</span>}
                    <span className={`shrink-0 text-ink ${isSelected ? "" : "invisible"}`}>
                      <Icon size={12} strokeWidth={2.5}>
                        <path d="M20 6L9 17l-5-5" />
                      </Icon>
                    </span>
                  </button>
                );
              })
            )}
          </div>
        )}

        {/* ── composer shell ─────────────────────────────── */}
        <div
          className={`relative isolate flex flex-col overflow-hidden border border-line bg-surface shadow-card transition-[border-color] duration-150 focus-within:border-line-strong ${
            tall ? "gap-2 rounded-[18px] px-3 pt-2.5 pb-2" : "gap-1.5 rounded-[14px] px-2.5 pt-2 pb-1.5"
          }`}
        >
          <canvas
            ref={glimmRef}
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 -z-10 h-full w-full"
            style={{ borderRadius: "inherit" }}
          />

          {/* Quoted excerpt / selection attachment chip */}
          {quotedExcerpt && (
            <div
              className="flex items-start gap-2 rounded-[8px] bg-inset px-2.5 py-1.5 text-[11.5px] text-ink-2 shadow-hairline"
              style={{ animation: "pop-in 180ms cubic-bezier(0.23,1,0.32,1) both" }}
            >
              <span className="mt-0.5 shrink-0 text-accent">
                <Icon size={12} strokeWidth={2.2}>
                  <path d="M9 10l-5 5 5 5M20 4v7a4 4 0 0 1-4 4H4" />
                </Icon>
              </span>
              <span className="line-clamp-2 min-w-0 flex-1 select-text leading-snug">{quotedExcerpt}</span>
              {onClearQuote && (
                <button
                  type="button"
                  aria-label="Remove quote"
                  onClick={onClearQuote}
                  className="flex size-5 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink"
                >
                  <Icon size={10} strokeWidth={2.4}>
                    <path d="M18 6L6 18M6 6l12 12" />
                  </Icon>
                </button>
              )}
            </div>
          )}

          <textarea
            ref={inputRef}
            rows={1}
            value={draft}
            onChange={(event) => {
              setDraft(event.target.value);
              setDismissed(false);
              setPlusOpen(false);
            }}
            onKeyDown={(event) => {
              if (menu && rows.length > 0) {
                if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                  event.preventDefault();
                  setEngaged(true);
                  setActive((cur) => (cur + (event.key === "ArrowDown" ? 1 : rows.length - 1)) % rows.length);
                  return;
                }
                if ((event.key === "Enter" && !event.shiftKey) || event.key === "Tab") {
                  event.preventDefault();
                  pickRow(rows[active]);
                  return;
                }
              }
              if (event.key === "Escape") {
                if (menu || modelOpen) {
                  event.preventDefault();
                  setDismissed(true);
                  closeMenus();
                }
                return;
              }
              if (
                event.key === "Enter" &&
                !event.shiftKey &&
                !event.nativeEvent.isComposing &&
                event.keyCode !== 229
              ) {
                event.preventDefault();
                submit();
              }
            }}
            placeholder={placeholder}
            aria-label="Prompt"
            className="min-w-0 w-full resize-none bg-transparent px-1 py-0.5 text-[13.5px] leading-[1.5] text-ink outline-none [overflow-wrap:anywhere] placeholder:text-ink-3 select-text"
          />

          <div className="flex items-center gap-1">
            {/* + attach / @ context */}
            <button
              type="button"
              aria-label="Add context"
              aria-expanded={plusOpen}
              onClick={() => {
                setModelOpen(false);
                setPlusOpen((cur) => !cur);
                inputRef.current?.focus();
              }}
              className={`flex size-7 shrink-0 items-center justify-center rounded-[8px] text-ink-3 transition-[background-color,color,transform] duration-150 hover:bg-hover hover:text-ink active:scale-[0.94] ${
                plusOpen ? "bg-hover text-ink" : ""
              }`}
            >
              <Icon size={15} strokeWidth={2}>
                <path d="M12 5v14M5 12h14" />
              </Icon>
            </button>

            {/* model selector */}
            <button
              ref={modelRef}
              type="button"
              aria-expanded={modelOpen}
              aria-label="Choose model"
              onClick={() => {
                setPlusOpen(false);
                setModelOpen((cur) => !cur);
              }}
              className="flex h-7 max-w-[180px] shrink-0 items-center gap-1 rounded-[8px] px-2 text-[12px] font-medium text-ink-2 transition-colors duration-150 hover:bg-hover hover:text-ink"
            >
              <span className="truncate">{selectedModelTitle || "Model"}</span>
              <span className="shrink-0 text-ink-3">
                <Icon size={11} strokeWidth={2.4}>
                  <path d="M6 9l6 6 6-6" />
                </Icon>
              </span>
            </button>

            {/* reasoning effort cycle button (News mode) */}
            {showEffort && onSelectEffort && (
              <button
                type="button"
                onClick={cycleEffort}
                title={locale === "zh" ? "切换推理深度（快速 / 均衡 / 深度）" : "Cycle reasoning effort"}
                className={`flex h-7 shrink-0 items-center gap-1 rounded-[8px] px-2 text-[11.5px] font-medium transition-colors duration-150 ${
                  effort === "deep"
                    ? "bg-accent-tint text-accent-ink"
                    : "text-ink-3 hover:bg-hover hover:text-ink"
                }`}
              >
                <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                  <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
                </svg>
                {effortLabel}
              </button>
            )}

            <div className="flex-1" />

            {/* Stop or Send button */}
            {isStreaming ? (
              <button
                type="button"
                aria-label="Stop"
                onClick={onAbort}
                className="flex size-7 shrink-0 items-center justify-center rounded-[8px] bg-ink text-surface transition-[transform,opacity] duration-150 hover:opacity-90 active:scale-[0.94]"
                title={locale === "zh" ? "停止生成" : "Stop"}
              >
                <span className="size-2.5 rounded-[2px] bg-current" />
              </button>
            ) : (
              <button
                type="button"
                aria-label="Send"
                disabled={!canSend}
                onClick={submit}
                className="flex size-7 shrink-0 items-center justify-center rounded-[8px] transition-[background-color,color,transform] duration-150 enabled:active:scale-[0.94]"
                style={{
                  background: canSend ? "var(--ink)" : "var(--line-strong)",
                  color: canSend ? "var(--surface)" : "var(--ink-2)",
                }}
              >
                <Icon size={15} strokeWidth={2.4}>
                  <path d="M12 19V5M5 12l7-7 7 7" />
                </Icon>
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
});

export default PromptBar;
