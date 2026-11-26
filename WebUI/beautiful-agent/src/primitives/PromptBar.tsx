import {
  useEffect,
  useImperativeHandle,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  forwardRef,
  type ReactNode,
} from "react";
import { createShader, playSweep, accentChain, ACCENTS } from "glimm";
import StickerPickerPopover from "./StickerPickerPopover";
import type {
  AttachedDocumentRef,
  BotMentionItem,
  ContextSourceItem,
  DocumentMentionItem,
  EffortLevel,
  ModelOption,
  SlashCommandItem,
  StickerItem,
} from "../types";

/* ─────────────────────────────────────────────────────────
 * PROMPT BAR — Composer with @Document + @Bot Delegation
 *   · @ Documents (open tabs, workspace files, library docs, reports)
 *   · @ Bots (delegate execution to any specialized Bot with its own model & prompt)
 *   · @ Context sources + / slash commands
 *   · Removable structured attachment pills above the input
 *   · Zero tiny text: all typography ≥ 13px
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
      <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
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

type MentionTab = "all" | "docs" | "bots" | "context";

type MentionRow =
  | { kind: "doc"; key: string; doc: DocumentMentionItem }
  | { kind: "bot"; key: string; bot: BotMentionItem }
  | { kind: "context"; key: string; source: ContextSourceItem }
  | { kind: "slash"; key: string; command: SlashCommandItem };

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
  availableDocuments?: DocumentMentionItem[];
  availableBots?: BotMentionItem[];
  stickers?: StickerItem[];
  quotedExcerpt?: string | null;
  effort?: EffortLevel;
  showEffort?: boolean;
  inlineBotMentions?: boolean;
  onClearQuote?: () => void;
  onSelectModel: (model: ModelOption) => void;
  onSelectEffort?: (effort: EffortLevel) => void;
  onOpenSettings: () => void;
  onUploadSticker?: () => void;
  onRefreshStickers?: () => void;
  onToggleFavoriteSticker?: (id: string) => void;
  onSearchOnlineStickers?: (query: string) => void;
  onSend: (text: string, documents: AttachedDocumentRef[], botId: string | null, stickerId?: string | null) => void;
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
    availableDocuments = [],
    availableBots = [],
    stickers = [],
    quotedExcerpt,
    effort = "balanced",
    showEffort = false,
    inlineBotMentions = false,
    onClearQuote,
    onSelectModel,
    onSelectEffort,
    onOpenSettings,
    onUploadSticker,
    onRefreshStickers,
    onToggleFavoriteSticker,
    onSearchOnlineStickers,
    onSend,
    onAbort,
  },
  ref,
) {
  const [draft, setDraft] = useState("");
  const [attachedDocs, setAttachedDocs] = useState<AttachedDocumentRef[]>([]);
  const [selectedBot, setSelectedBot] = useState<BotMentionItem | null>(null);
  const [selectedSticker, setSelectedSticker] = useState<StickerItem | null>(null);
  const [stickerOpen, setStickerOpen] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [manualAtTab, setManualAtTab] = useState<MentionTab | null>(null);
  const [activeTab, setActiveTab] = useState<MentionTab>("all");
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
  const menu: "at" | "slash" | null = manualAtTab !== null ? "at" : token?.kind ?? null;
  const query = manualAtTab !== null ? "" : token?.query ?? "";
  const effectiveTab: MentionTab = manualAtTab ?? activeTab;

  const hasRichMentions = availableDocuments.length > 0 || availableBots.length > 0;

  const rows = useMemo<MentionRow[]>(() => {
    if (menu === "slash") {
      return slashCommands
        .filter((c) => c.name.slice(1).toLowerCase().includes(query) || c.desc.toLowerCase().includes(query))
        .map((command) => ({ kind: "slash", key: `slash:${command.key}`, command }));
    }
    if (menu !== "at") return [];

    const out: MentionRow[] = [];
    const wantDocs = effectiveTab === "all" || effectiveTab === "docs";
    const wantBots = effectiveTab === "all" || effectiveTab === "bots";
    const wantContext = effectiveTab === "all" || effectiveTab === "context";

    if (wantDocs && availableDocuments.length > 0) {
      const matchedDocs = availableDocuments.filter(
        (d) =>
          !query ||
          d.title.toLowerCase().includes(query) ||
          d.desc.toLowerCase().includes(query) ||
          (d.filePath && d.filePath.toLowerCase().includes(query)),
      );
      const limit = effectiveTab === "all" && !query ? 6 : 16;
      for (const doc of matchedDocs.slice(0, limit)) {
        out.push({ kind: "doc", key: `doc:${doc.id}`, doc });
      }
    }

    if (wantBots && availableBots.length > 0) {
      const matchedBots = availableBots.filter(
        (b) =>
          !query ||
          b.name.toLowerCase().includes(query) ||
          b.nickname.toLowerCase().includes(query) ||
          b.handle.toLowerCase().includes(query) ||
          b.tagline.toLowerCase().includes(query) ||
          b.id.toLowerCase().includes(query),
      );
      const limit = effectiveTab === "all" && !query ? 10 : 60;
      for (const bot of matchedBots.slice(0, limit)) {
        out.push({ kind: "bot", key: `bot:${bot.id}`, bot });
      }
    }

    if (wantContext && contextSources.length > 0) {
      const matchedSources = contextSources.filter(
        (s) =>
          !query ||
          s.name.toLowerCase().includes(query) ||
          s.desc.toLowerCase().includes(query) ||
          s.key.includes(query),
      );
      for (const source of matchedSources) {
        out.push({ kind: "context", key: `ctx:${source.key}`, source });
      }
    }

    return out;
  }, [menu, query, effectiveTab, availableDocuments, availableBots, contextSources, slashCommands]);

  useEffect(() => {
    setActive(0);
    setEngaged(false);
  }, [menu, query, effectiveTab]);

  useLayoutEffect(() => {
    const target = rowRefs.current[active];
    if (target) setRowBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [menu, query, active, rows.length, effectiveTab]);

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
    setModelMenuLeft(Math.max(0, Math.min(triggerRect.left - anchorRect.left, Math.max(0, anchorRect.width - 230))));
    setModelMenuBottom(anchorRect.bottom - triggerRect.top + 8);
  }, [modelOpen, selectedModelTitle]);

  useEffect(() => {
    if (!modelOpen) setModelHovered(null);
  }, [modelOpen]);

  useEffect(() => {
    if (selectedSticker && !stickers.some((s) => s.id === selectedSticker.id)) {
      setSelectedSticker(null);
    }
  }, [stickers, selectedSticker]);

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
    const minH = tall ? 48 : 28;
    const maxH = 136;
    input.style.height = "0px";
    const h = input.scrollHeight;
    input.style.height = `${Math.min(Math.max(h, minH), maxH)}px`;
    input.style.overflowY = h > maxH ? "auto" : "hidden";
  }, [draft, tall]);

  useEffect(() => {
    if (!modelOpen && manualAtTab === null && !stickerOpen) return;
    const close = (event: PointerEvent) => {
      if (!(event.target as Element).closest("[data-promptbar]")) {
        setModelOpen(false);
        setManualAtTab(null);
        setStickerOpen(false);
      }
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [modelOpen, manualAtTab, stickerOpen]);

  const closeMenus = () => {
    setManualAtTab(null);
    setModelOpen(false);
    setStickerOpen(false);
  };

  const pickRow = (row: MentionRow) => {
    const prefix = token ? draft.slice(0, token.start) : draft;
    if (row.kind === "doc") {
      const refDoc: AttachedDocumentRef = {
        id: row.doc.id,
        title: row.doc.title,
        sourceKind: row.doc.sourceKind,
        filePath: row.doc.filePath ?? null,
      };
      setAttachedDocs((prev) => (prev.some((d) => d.id === refDoc.id) ? prev : [...prev, refDoc]));
      setDraft(prefix);
      setManualAtTab(null);
      setDismissed(true);
      inputRef.current?.focus();
      return;
    }
    if (row.kind === "bot") {
      if (inlineBotMentions) {
        const cleanPrefix = prefix.length > 0 && !/\s$/.test(prefix) ? `${prefix} ` : prefix;
        setDraft(`${cleanPrefix}@${row.bot.name} `);
      } else {
        setSelectedBot(row.bot);
        setDraft(prefix);
      }
      setManualAtTab(null);
      setDismissed(true);
      inputRef.current?.focus();
      return;
    }
    if (row.kind === "context") {
      setDraft(`${prefix}${row.source.insertText}`);
      setManualAtTab(null);
      setDismissed(true);
      inputRef.current?.focus();
      return;
    }
    if (row.kind === "slash") {
      setDraft(`${prefix}${row.command.insertText}`);
      setManualAtTab(null);
      setDismissed(true);
      inputRef.current?.focus();
    }
  };

  const canSend = !isStreaming && (draft.trim().length > 0 || attachedDocs.length > 0 || selectedBot !== null || selectedSticker !== null);
  const submit = () => {
    if (!canSend) return;
    const text = draft.trim();
    const docsSnapshot = attachedDocs.slice();
    const botSnapshot = selectedBot?.id ?? null;
    const stickerSnapshot = selectedSticker?.id ?? null;
    setDraft("");
    setAttachedDocs([]);
    setSelectedBot(null);
    setSelectedSticker(null);
    closeMenus();
    onSend(text, docsSnapshot, botSnapshot, stickerSnapshot);
  };

  const handleSelectSticker = (stk: StickerItem) => {
    setStickerOpen(false);
    if (!draft.trim() && attachedDocs.length === 0 && !isStreaming) {
      const botSnapshot = selectedBot?.id ?? null;
      setSelectedBot(null);
      onSend("", [], botSnapshot, stk.id);
      return;
    }
    setSelectedSticker(stk);
    inputRef.current?.focus();
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

  const openAtPicker = (tab: MentionTab) => {
    setModelOpen(false);
    setActiveTab(tab);
    setManualAtTab((cur) => (cur === tab ? null : tab));
    inputRef.current?.focus();
  };

  return (
    <div data-promptbar className="w-full">
      <div ref={composerAnchorRef} className="relative">
        {/* ── @ / slash mention menu ─────────────────────── */}
        {menu && (
          <div
            onMouseLeave={() => setEngaged(false)}
            className="absolute inset-x-0 bottom-full z-20 mb-2 overflow-hidden rounded-[12px] bg-surface shadow-raised"
            style={{ animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "bottom center" }}
          >
            {menu === "at" && hasRichMentions && (
              <div className="flex items-center gap-1 border-b border-line px-2 py-1.5">
                {(
                  [
                    ["all", locale === "zh" ? "全部" : "All"],
                    ["docs", locale === "zh" ? "文档" : "Docs"],
                    ["bots", "Bots"],
                    ["context", locale === "zh" ? "上下文" : "Context"],
                  ] as [MentionTab, string][]
                ).map(([tabKey, tabLabel]) => {
                  const isTabActive = effectiveTab === tabKey;
                  return (
                    <button
                      key={tabKey}
                      type="button"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => {
                        setActiveTab(tabKey);
                        if (manualAtTab !== null) setManualAtTab(tabKey);
                      }}
                      className={`h-7 rounded-[7px] px-2.5 text-[13px] font-medium transition-colors duration-100 ${
                        isTabActive ? "bg-hover-2 text-ink" : "text-ink-3 hover:bg-hover hover:text-ink"
                      }`}
                    >
                      {tabLabel}
                    </button>
                  );
                })}
              </div>
            )}

            <div className="bui-scroll relative max-h-68 overflow-y-auto p-1">
              <span
                aria-hidden
                className="pointer-events-none absolute inset-x-1 rounded-[7px] bg-hover"
                style={{
                  top: rowBox?.top ?? 0,
                  height: rowBox?.height ?? 0,
                  opacity: rowBox && engaged && rows.length > 0 ? 1 : 0,
                  transition:
                    "top 200ms cubic-bezier(0.23,1,0.32,1), height 200ms cubic-bezier(0.23,1,0.32,1), opacity 140ms ease",
                }}
              />
              {rows.map((row, i) => {
                if (row.kind === "doc") {
                  const alreadyAttached = attachedDocs.some((d) => d.id === row.doc.id);
                  return (
                    <button
                      key={row.key}
                      type="button"
                      ref={(el) => {
                        rowRefs.current[i] = el;
                      }}
                      onMouseDown={(e) => e.preventDefault()}
                      onMouseEnter={() => {
                        setActive(i);
                        setEngaged(true);
                      }}
                      onClick={() => pickRow(row)}
                      className="relative z-10 flex h-9.5 w-full items-center gap-2.5 rounded-[7px] px-2.5 text-left"
                    >
                      <span className="flex size-5 shrink-0 items-center justify-center text-ink-2">
                        <Icon size={15}>{SOURCE_GLYPHS.doc}</Icon>
                      </span>
                      <span className="max-w-[55%] shrink-0 truncate text-[13.5px] font-medium text-ink">
                        {row.doc.title}
                      </span>
                      <span className="min-w-0 flex-1 truncate text-[13px] text-ink-3">{row.doc.desc}</span>
                      {alreadyAttached && (
                        <span className="shrink-0 text-[12.5px] font-medium text-accent-ink">
                          {locale === "zh" ? "已选" : "Added"}
                        </span>
                      )}
                    </button>
                  );
                }

                if (row.kind === "bot") {
                  const isChosen = selectedBot?.id === row.bot.id;
                  return (
                    <button
                      key={row.key}
                      type="button"
                      ref={(el) => {
                        rowRefs.current[i] = el;
                      }}
                      onMouseDown={(e) => e.preventDefault()}
                      onMouseEnter={() => {
                        setActive(i);
                        setEngaged(true);
                      }}
                      onClick={() => pickRow(row)}
                      className="relative z-10 flex h-9.5 w-full items-center gap-2.5 rounded-[7px] px-2.5 text-left"
                    >
                      {row.bot.avatarURL ? (
                        <img
                          src={row.bot.avatarURL}
                          alt={row.bot.name}
                          className="size-5 shrink-0 rounded-[5px] border border-line object-cover"
                        />
                      ) : (
                        <span
                          className="size-2.5 shrink-0 rounded-full"
                          style={{ backgroundColor: row.bot.accentHex || "var(--accent)" }}
                        />
                      )}
                      <span className="shrink-0 text-[13.5px] font-medium text-ink">@{row.bot.name}</span>
                      <span className="min-w-0 flex-1 truncate text-[13px] text-ink-3">{row.bot.tagline}</span>
                      {isChosen && (
                        <span className="shrink-0 text-[12.5px] font-medium text-accent-ink">
                          {locale === "zh" ? "已指派" : "Selected"}
                        </span>
                      )}
                    </button>
                  );
                }

                if (row.kind === "context") {
                  return (
                    <button
                      key={row.key}
                      type="button"
                      ref={(el) => {
                        rowRefs.current[i] = el;
                      }}
                      onMouseDown={(e) => e.preventDefault()}
                      onMouseEnter={() => {
                        setActive(i);
                        setEngaged(true);
                      }}
                      onClick={() => pickRow(row)}
                      className="relative z-10 flex h-9.5 w-full items-center gap-2.5 rounded-[7px] px-2.5 text-left"
                    >
                      <span className="flex size-5 shrink-0 items-center justify-center text-ink-2">
                        <Icon size={15}>{SOURCE_GLYPHS[row.source.glyph] ?? SOURCE_GLYPHS.doc}</Icon>
                      </span>
                      <span className="shrink-0 text-[13.5px] font-medium text-ink">{row.source.name}</span>
                      <span className="min-w-0 flex-1 truncate text-[13px] text-ink-3">{row.source.desc}</span>
                    </button>
                  );
                }

                return (
                  <button
                    key={row.key}
                    type="button"
                    ref={(el) => {
                      rowRefs.current[i] = el;
                    }}
                    onMouseDown={(e) => e.preventDefault()}
                    onMouseEnter={() => {
                      setActive(i);
                      setEngaged(true);
                    }}
                    onClick={() => pickRow(row)}
                    className="relative z-10 flex h-9.5 w-full items-center gap-2.5 rounded-[7px] px-2.5 text-left"
                  >
                    <span className="shrink-0 font-mono text-[13.5px] font-medium text-ink">{row.command.name}</span>
                    <span className="min-w-0 flex-1 truncate text-[13px] text-ink-3">{row.command.desc}</span>
                  </button>
                );
              })}

              {rows.length === 0 && (
                <div className="flex h-9 items-center px-2.5 text-[13px] text-ink-3">
                  {locale === "zh" ? `没有匹配“${query}”` : `No matches for "${query}"`}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── model menu ─────────────────────────────────── */}
        {modelOpen && (
          <div
            onMouseLeave={() => setModelHovered(null)}
            className="bui-scroll absolute z-20 max-h-64 w-60 overflow-y-auto rounded-[12px] bg-surface p-1 shadow-raised"
            style={{
              left: modelMenuLeft,
              bottom: modelMenuBottom,
              animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both",
              transformOrigin: "bottom left",
            }}
          >
            <span
              aria-hidden
              className="pointer-events-none absolute inset-x-1 rounded-[7px] bg-hover"
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
                className="relative z-10 flex h-9 w-full items-center gap-2 rounded-[7px] px-2.5 text-left text-[13px] font-medium text-accent-ink hover:bg-hover"
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
                    className="relative z-10 flex h-8.5 w-full items-center gap-2 rounded-[7px] px-2.5 text-left"
                  >
                    <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-ink">{m.title}</span>
                    {m.tag && <span className="shrink-0 text-[12.5px] text-ink-3">{m.tag}</span>}
                    <span className={`shrink-0 text-ink ${isSelected ? "" : "invisible"}`}>
                      <Icon size={13} strokeWidth={2.5}>
                        <path d="M20 6L9 17l-5-5" />
                      </Icon>
                    </span>
                  </button>
                );
              })
            )}
          </div>
        )}

        {stickerOpen && (
          <StickerPickerPopover
            locale={locale}
            stickers={stickers}
            onSelectSticker={handleSelectSticker}
            onToggleFavorite={(id) => onToggleFavoriteSticker?.(id)}
            onUploadSticker={() => onUploadSticker?.()}
            onSearchOnline={(q) => onSearchOnlineStickers?.(q)}
            onClose={() => setStickerOpen(false)}
          />
        )}

        {/* ── composer shell ─────────────────────────────── */}
        <div
          className={`relative isolate flex flex-col overflow-hidden border border-line bg-surface shadow-card transition-[border-color] duration-150 focus-within:border-line-strong ${
            tall ? "gap-2 rounded-[18px] px-3.5 pt-3 pb-2.5" : "gap-2 rounded-[14px] px-3 pt-2.5 pb-2"
          }`}
        >
          <canvas
            ref={glimmRef}
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 -z-10 h-full w-full"
            style={{ borderRadius: "inherit" }}
          />

          {/* Attached @Documents + @Bot delegation + Sticker chips */}
          {(attachedDocs.length > 0 || selectedBot || selectedSticker) && (
            <div className="flex flex-wrap items-center gap-1.5">
              {selectedSticker && (
                <div className="relative inline-flex items-center gap-1.5 rounded-[8px] bg-inset p-1 pr-2 shadow-hairline">
                  <img src={selectedSticker.url} alt={selectedSticker.meaning || "Sticker"} className="size-8 rounded-[5px] object-contain" />
                  <button
                    type="button"
                    aria-label="Remove sticker"
                    onClick={() => setSelectedSticker(null)}
                    className="flex size-5 items-center justify-center rounded-[5px] text-ink-3 hover:bg-hover-2 hover:text-ink"
                  >
                    <Icon size={11} strokeWidth={2.4}>
                      <path d="M18 6L6 18M6 6l12 12" />
                    </Icon>
                  </button>
                </div>
              )}
              {attachedDocs.map((doc) => (
                <span
                  key={doc.id}
                  className="inline-flex h-7.5 max-w-[260px] items-center gap-1.5 rounded-[8px] bg-inset px-2.5 text-[13px] font-medium text-ink shadow-hairline"
                  style={{ animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both" }}
                >
                  <span className="shrink-0 text-ink-2">
                    <Icon size={13.5}>{SOURCE_GLYPHS.doc}</Icon>
                  </span>
                  <span className="truncate">{doc.title}</span>
                  <button
                    type="button"
                    aria-label={`Remove ${doc.title}`}
                    onClick={() => setAttachedDocs((prev) => prev.filter((d) => d.id !== doc.id))}
                    className="flex size-5 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink"
                  >
                    <Icon size={11} strokeWidth={2.4}>
                      <path d="M18 6L6 18M6 6l12 12" />
                    </Icon>
                  </button>
                </span>
              ))}

              {selectedBot && (
                <span
                  className="inline-flex h-7.5 max-w-[240px] items-center gap-1.5 rounded-[8px] bg-accent-tint px-2.5 text-[13px] font-medium text-accent-ink"
                  style={{ animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both" }}
                >
                  <span
                    className="size-2 shrink-0 rounded-full"
                    style={{ backgroundColor: selectedBot.accentHex || "var(--accent)" }}
                  />
                  <span className="truncate">
                    {`@${selectedBot.name}`}
                  </span>
                  <button
                    type="button"
                    aria-label="Clear assigned bot"
                    onClick={() => setSelectedBot(null)}
                    className="flex size-5 shrink-0 items-center justify-center rounded-[5px] text-accent-ink/75 transition-colors duration-100 hover:bg-hover-2 hover:text-accent-ink"
                  >
                    <Icon size={11} strokeWidth={2.4}>
                      <path d="M18 6L6 18M6 6l12 12" />
                    </Icon>
                  </button>
                </span>
              )}
            </div>
          )}

          {/* Quoted excerpt / selection attachment chip */}
          {quotedExcerpt && (
            <div
              className="flex items-start gap-2 rounded-[8px] bg-inset px-2.5 py-1.5 text-[13px] text-ink-2 shadow-hairline"
              style={{ animation: "pop-in 180ms cubic-bezier(0.23,1,0.32,1) both" }}
            >
              <span className="mt-0.5 shrink-0 text-accent">
                <Icon size={13} strokeWidth={2.2}>
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
                  <Icon size={11} strokeWidth={2.4}>
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
              setManualAtTab(null);
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
            placeholder={
              selectedBot
                ? locale === "zh"
                  ? `给 @${selectedBot.name} 补充要求，或直接按 Enter 开始处理…`
                  : `Add instructions for @${selectedBot.name}, or press Enter…`
                : placeholder
            }
            aria-label="Prompt"
            className="min-w-0 w-full resize-none bg-transparent px-1 py-0.5 text-[14px] leading-[1.55] text-ink outline-none [overflow-wrap:anywhere] placeholder:text-ink-3 select-text"
          />

          <div className="flex items-center gap-1">
            {/* Quick @文档 & @助手 triggers when available (Butler mode), otherwise + attach when context exists */}
            {hasRichMentions ? (
              <>
                <button
                  type="button"
                  onClick={() => openAtPicker("docs")}
                  className={`flex h-7.5 shrink-0 items-center rounded-[8px] px-2 text-[13px] font-medium transition-colors duration-150 ${
                    manualAtTab === "docs"
                      ? "bg-hover-2 text-ink"
                      : "text-ink-2 hover:bg-hover hover:text-ink"
                  }`}
                >
                  {locale === "zh" ? "@文档" : "@Doc"}
                </button>
                <button
                  type="button"
                  onClick={() => openAtPicker("bots")}
                  className={`flex h-7.5 shrink-0 items-center rounded-[8px] px-2 text-[13px] font-medium transition-colors duration-150 ${
                    manualAtTab === "bots" || selectedBot
                      ? "bg-accent-tint text-accent-ink"
                      : "text-ink-2 hover:bg-hover hover:text-ink"
                  }`}
                >
                  {"@Bots"}
                </button>
              </>
            ) : contextSources.length > 0 ? (
              <button
                type="button"
                aria-label="Add context"
                aria-expanded={manualAtTab !== null}
                onClick={() => openAtPicker("all")}
                className={`flex size-7.5 shrink-0 items-center justify-center rounded-[8px] text-ink-3 transition-[background-color,color,transform] duration-150 hover:bg-hover hover:text-ink active:scale-[0.94] ${
                  manualAtTab !== null ? "bg-hover text-ink" : ""
                }`}
              >
                <Icon size={15} strokeWidth={2}>
                  <path d="M12 5v14M5 12h14" />
                </Icon>
              </button>
            ) : null}

            {onUploadSticker && (
              <button
                type="button"
                aria-label="Stickers"
                onClick={() => {
                  setModelOpen(false);
                  setManualAtTab(null);
                  setStickerOpen((v) => {
                    const next = !v;
                    if (next) onRefreshStickers?.();
                    return next;
                  });
                }}
                className={`flex size-7.5 shrink-0 items-center justify-center rounded-[8px] transition-colors duration-150 ${
                  stickerOpen ? "bg-hover-2 text-ink" : "text-ink-2 hover:bg-hover hover:text-ink"
                }`}
              >
                <Icon size={15.5} strokeWidth={1.85}>
                  <circle cx="12" cy="12" r="9.5" />
                  <path d="M9 10h.01M15 10h.01M8.5 14.5a4 4 0 0 0 7 0" />
                </Icon>
              </button>
            )}

            {/* model selector (hidden when delegated bot is active, since bot uses its own configured model) */}
            {!selectedBot && (
              <button
                ref={modelRef}
                type="button"
                aria-expanded={modelOpen}
                aria-label="Choose model"
                onClick={() => {
                  setManualAtTab(null);
                  setModelOpen((cur) => !cur);
                }}
                className="flex h-7.5 max-w-[200px] shrink-0 items-center gap-1 rounded-[8px] px-2 text-[13px] font-medium text-ink-2 transition-colors duration-150 hover:bg-hover hover:text-ink"
              >
                <span className="truncate">{selectedModelTitle || "Model"}</span>
                <span className="shrink-0 text-ink-3">
                  <Icon size={12} strokeWidth={2.4}>
                    <path d="M6 9l6 6 6-6" />
                  </Icon>
                </span>
              </button>
            )}

            {/* reasoning effort cycle button (News mode) */}
            {showEffort && onSelectEffort && (
              <button
                type="button"
                onClick={cycleEffort}
                title={locale === "zh" ? "切换推理深度（快速 / 均衡 / 深度）" : "Cycle reasoning effort"}
                className={`flex h-7.5 shrink-0 items-center rounded-[8px] px-2.5 text-[13px] font-medium transition-colors duration-150 ${
                  effort === "deep"
                    ? "bg-accent-tint text-accent-ink"
                    : "text-ink-2 hover:bg-hover hover:text-ink"
                }`}
              >
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
                className="flex size-8 shrink-0 items-center justify-center rounded-[9px] bg-ink text-surface transition-[transform,opacity] duration-150 hover:opacity-90 active:scale-[0.94]"
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
                className="flex size-8 shrink-0 items-center justify-center rounded-[9px] transition-[background-color,color,transform] duration-150 enabled:active:scale-[0.94]"
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
