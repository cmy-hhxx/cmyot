import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { copyTextWithFallback, postToNative } from "./bridge";
import LoadingState from "./primitives/LoadingState";
import MarkdownProse from "./primitives/MarkdownProse";
import PromptBar, { type PromptBarHandle } from "./primitives/PromptBar";
import SidebarNav from "./primitives/SidebarNav";
import ThinkingState from "./primitives/ThinkingState";
import ToolChips from "./primitives/ToolChips";
import type { AgentMessage, HostState, QuickSuggestion, StreamPatch } from "./types";

/* ─────────────────────────────────────────────────────────
 * COT BEAUTIFUL AGENT HARNESS
 * Built directly from beautifului.dev primitives & IceCreamHarness:
 *   · Borderless assistant prose directly on --page (zero clunky bubble boxes)
 *   · Floating PromptBar with soft bottom dissolve gradient
 *   · Live Pi ThinkingState + ToolChips + LoadingState pixel grid
 *   · Quiet icon action bar (Copy / Retry / Insert / New Note) + Follow-ups
 *   · Blur-to-crisp Home reveal empty state with contextual quick actions
 *   · Dual mode: "butler" (SidebarNav + Harness) & "news" (Editorial Companion)
 * ───────────────────────────────────────────────────────── */

const DEFAULT_STATE: HostState = {
  mode: "butler",
  isDark: false,
  locale: "zh",
  botName: "总管",
  botNickname: "总管",
  piAvailable: true,
  sessions: [],
  activeSessionID: "",
  messages: [],
  isStreaming: false,
  placeholder: "直接问行情、查资讯、读文档，输入 @ 带入上下文或 / 使用指令…",
  availableModels: [],
  selectedModelID: "",
  selectedModelTitle: "",
  suggestions: [],
  contextSources: [],
  slashCommands: [],
};

function SuggestionGlyph({ kind }: { kind?: QuickSuggestion["icon"] }) {
  const paths: Record<string, ReactNode> = {
    stock: <path d="M4 20V11M10 20V4M16 20v-7M22 20H2" />,
    news: (
      <g>
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <path d="M7 9h10M7 13h6" />
      </g>
    ),
    doc: (
      <g>
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <path d="M14 2v6h6M8 13h8M8 17h5" />
      </g>
    ),
    search: (
      <g>
        <circle cx="11" cy="11" r="7" />
        <path d="M21 21l-4.3-4.3" />
      </g>
    ),
    note: (
      <g>
        <path d="M12 20h9" />
        <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" />
      </g>
    ),
    code: <path d="M8 6l-5 6 5 6M16 6l5 6-5 6" />,
    memory: <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />,
    spark: <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />,
  };
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {paths[kind ?? "spark"] ?? paths.spark}
    </svg>
  );
}

function homeRevealStyle(visible: boolean): CSSProperties {
  return {
    opacity: visible ? 1 : 0,
    transform: visible ? "translate3d(0, 0, 0)" : "translate3d(0, 14px, 0)",
    filter: visible ? "blur(0px)" : "blur(10px)",
    transition:
      "opacity 520ms cubic-bezier(0.16, 1, 0.3, 1), transform 520ms cubic-bezier(0.16, 1, 0.3, 1), filter 520ms cubic-bezier(0.16, 1, 0.3, 1)",
  };
}

function UserBubble({ text, quoteContext }: { text: string; quoteContext?: string }) {
  return (
    <div
      className="flex flex-col items-end gap-1.5 pl-10"
      style={{ animation: "fade-up 240ms cubic-bezier(0.23,1,0.32,1) both" }}
    >
      {quoteContext && (
        <div className="max-w-[85%] rounded-[9px] bg-inset px-2.5 py-1.5 text-[11.5px] leading-snug text-ink-2 shadow-hairline">
          <span className="line-clamp-2">{quoteContext}</span>
        </div>
      )}
      <div className="max-w-[92%] select-text whitespace-pre-wrap break-words rounded-[13px] bg-field px-3.5 py-2 text-[13.5px] leading-relaxed text-ink shadow-hairline">
        {text}
      </div>
    </div>
  );
}

function AssistantMessageBlock({
  message,
  locale,
  statusLabel,
  onRetry,
  onInsert,
  onOpenNote,
  onFollowUp,
}: {
  message: AgentMessage;
  locale: "zh" | "en";
  statusLabel?: string;
  onRetry?: () => void;
  onInsert: (text: string) => void;
  onOpenNote: (text: string) => void;
  onFollowUp: (prompt: string) => void;
}) {
  const [copied, setCopied] = useState(false);
  const hasText = message.text.trim().length > 0;
  const hasThinking = Boolean(message.thinking && message.thinking.trim().length > 0);
  const hasSteps = Boolean(message.steps && message.steps.length > 0);
  const isWaitingForFirstOutput = Boolean(message.isStreaming) && !hasText && !hasThinking && !hasSteps;
  const isTraceWorking =
    Boolean(message.isStreaming) &&
    (!hasText || Boolean(message.steps?.some((s) => s.status === "running")));

  const handleCopy = () => {
    copyTextWithFallback(message.text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <article className="min-w-0" style={{ animation: "fade-up 320ms cubic-bezier(0.23,1,0.32,1) both" }}>
      {isWaitingForFirstOutput ? (
        <div className="flex min-h-6 items-center">
          <LoadingState
            label={statusLabel || (locale === "zh" ? "正在思考" : "Thinking")}
            variant="Dots"
          />
        </div>
      ) : (
        <>
          {(hasThinking || hasSteps) && (
            <ThinkingState
              thinking={message.thinking}
              steps={message.steps}
              isWorking={isTraceWorking}
              durationMs={message.thinkingDurationMs}
              locale={locale}
              activeLabel={statusLabel}
            />
          )}

          {hasText ? (
            <div className={message.isError ? "rounded-card bg-red-tint px-3 py-2 text-[13px] text-red" : ""}>
              <MarkdownProse
                markdown={message.text}
                isStreaming={Boolean(message.isStreaming)}
                locale={locale}
                onInsertCode={onInsert}
              />
            </div>
          ) : (
            message.isStreaming && (
              <div className="mt-1 flex min-h-6 items-center">
                <LoadingState
                  label={statusLabel || (locale === "zh" ? "正在整理回复" : "Drafting reply")}
                  variant="Drive"
                />
              </div>
            )
          )}

          {message.toolChips && message.toolChips.length > 0 && <ToolChips items={message.toolChips} />}

          {/* Quiet Beautiful UI action icons row (StreamingText style) */}
          {!message.isStreaming && hasText && !message.isError && (
            <div
              className="mt-2 flex items-center gap-0.5 text-ink-3"
              style={{ animation: "fade-in 240ms ease-out both" }}
            >
              <button
                type="button"
                onClick={handleCopy}
                title={copied ? (locale === "zh" ? "已复制" : "Copied") : locale === "zh" ? "复制全文" : "Copy"}
                className={`flex h-6 items-center gap-1 rounded-[6px] px-1.5 text-[11.5px] transition-colors duration-100 hover:bg-hover-2 ${
                  copied ? "text-green" : "text-ink-3 hover:text-ink-2"
                }`}
              >
                {copied ? (
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                ) : (
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="9" y="9" width="12" height="12" rx="2.5" />
                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                  </svg>
                )}
                {copied && <span>{locale === "zh" ? "已复制" : "Copied"}</span>}
              </button>

              {onRetry && (
                <button
                  type="button"
                  onClick={onRetry}
                  title={locale === "zh" ? "重新生成" : "Retry"}
                  className="flex size-6 items-center justify-center rounded-[6px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 12a9 9 0 1 1-2.64-6.36M21 3v6h-6" />
                  </svg>
                </button>
              )}

              <button
                type="button"
                onClick={() => onInsert(message.text)}
                title={locale === "zh" ? "插入到当前编辑器光标处" : "Insert at editor cursor"}
                className="flex h-6 items-center gap-1 rounded-[6px] px-1.5 text-[11.5px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
              >
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 5v14M5 12l7 7 7-7" />
                </svg>
                <span>{locale === "zh" ? "插入" : "Insert"}</span>
              </button>

              <button
                type="button"
                onClick={() => onOpenNote(message.text)}
                title={locale === "zh" ? "存为新文档标签页" : "Save as new note tab"}
                className="flex h-6 items-center gap-1 rounded-[6px] px-1.5 text-[11.5px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
              >
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                  <path d="M14 2v6h6M12 18v-6M9 15h6" />
                </svg>
                <span>{locale === "zh" ? "存笔记" : "Note"}</span>
              </button>
            </div>
          )}

          {/* Contextual clickable follow-up prompts (StreamingText style) */}
          {!message.isStreaming && message.followUps && message.followUps.length > 0 && (
            <div className="mt-3" style={{ animation: "fade-in 300ms ease-out both" }}>
              <p className="mb-1 text-[11.5px] font-medium text-ink-3">
                {locale === "zh" ? "继续追问" : "Follow-ups"}
              </p>
              <div className="flex flex-col">
                {message.followUps.map((prompt, i) => (
                  <button
                    key={prompt}
                    type="button"
                    onClick={() => onFollowUp(prompt)}
                    className="-mx-1.5 flex items-center gap-2 rounded-[7px] border-b border-line px-1.5 py-1.5 text-left text-[12.5px] text-ink transition-colors duration-100 last:border-b-0 hover:bg-hover-2"
                    style={{ animation: `fade-up 300ms cubic-bezier(0.23,1,0.32,1) ${i * 70}ms both` }}
                  >
                    <svg
                      width="11"
                      height="11"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="var(--ink-3)"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="shrink-0"
                    >
                      <path d="M9 10l-5 5 5 5" />
                      <path d="M20 4v7a4 4 0 0 1-4 4H4" />
                    </svg>
                    <span className="min-w-0 truncate">{prompt}</span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </article>
  );
}

declare global {
  interface Window {
    CotAgentBridge?: {
      setState: (next: HostState) => void;
      setTheme: (isDark: boolean) => void;
      patchStreaming: (patch: StreamPatch) => void;
      injectDraft: (text: string, quote?: string | null) => void;
      focusComposer: () => void;
    };
  }
}

export default function App() {
  const [state, setState] = useState<HostState>(DEFAULT_STATE);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [localQuote, setLocalQuote] = useState<string | null>(null);
  const [revealStage, setRevealStage] = useState(4);
  const [composerH, setComposerH] = useState(112);

  const scrollRef = useRef<HTMLDivElement>(null);
  const composerRef = useRef<HTMLDivElement>(null);
  const promptBarRef = useRef<PromptBarHandle>(null);

  const effectiveQuote = localQuote ?? state.quotedExcerpt ?? null;
  const hasMessages = state.messages.length > 0;

  // Apply light/dark class instantly with .theme-switching freeze (beautifului.dev technique)
  const applyThemeClass = useCallback((isDark: boolean) => {
    const root = document.documentElement;
    if (root.classList.contains("dark") === isDark) return;
    root.classList.add("theme-switching");
    root.classList.toggle("dark", isDark);
    requestAnimationFrame(() => {
      root.classList.remove("theme-switching");
    });
  }, []);

  useEffect(() => {
    applyThemeClass(state.isDark);
  }, [state.isDark, applyThemeClass]);

  // Register global bridge for Swift WKWebView host
  useEffect(() => {
    window.CotAgentBridge = {
      setState: (next: HostState) => {
        applyThemeClass(next.isDark);
        setState(next);
        if (next.quotedExcerpt !== undefined && next.quotedExcerpt !== null) {
          setLocalQuote(next.quotedExcerpt);
        }
      },
      setTheme: (isDark: boolean) => {
        applyThemeClass(isDark);
        setState((prev) => (prev.isDark === isDark ? prev : { ...prev, isDark }));
      },
      patchStreaming: (patch: StreamPatch) => {
        setState((prev) => {
          const idx = prev.messages.findIndex((m) => m.id === patch.messageId);
          if (idx === -1) {
            return {
              ...prev,
              isStreaming: true,
              streamingStatusLabel: patch.statusLabel ?? prev.streamingStatusLabel,
              messages: [
                ...prev.messages,
                {
                  id: patch.messageId,
                  role: "assistant",
                  text: patch.text ?? "",
                  thinking: patch.thinking ?? "",
                  thinkingDurationMs: patch.thinkingDurationMs,
                  steps: patch.steps ?? [],
                  isStreaming: true,
                },
              ],
            };
          }
          const nextMsgs = prev.messages.slice();
          const cur = nextMsgs[idx];
          nextMsgs[idx] = {
            ...cur,
            text: patch.text !== undefined ? patch.text : cur.text,
            thinking: patch.thinking !== undefined ? patch.thinking : cur.thinking,
            thinkingDurationMs:
              patch.thinkingDurationMs !== undefined ? patch.thinkingDurationMs : cur.thinkingDurationMs,
            steps: patch.steps !== undefined ? patch.steps : cur.steps,
            isStreaming: true,
          };
          return {
            ...prev,
            isStreaming: true,
            streamingStatusLabel: patch.statusLabel ?? prev.streamingStatusLabel,
            messages: nextMsgs,
          };
        });
      },
      injectDraft: (text: string, quote?: string | null) => {
        if (quote !== undefined) setLocalQuote(quote);
        if (text) promptBarRef.current?.setDraft(text);
        else promptBarRef.current?.focus();
      },
      focusComposer: () => {
        promptBarRef.current?.focus();
      },
    };

    postToNative("ready");
    return () => {
      delete window.CotAgentBridge;
    };
  }, [applyThemeClass]);

  // Empty state staggered reveal animation (beautifului.dev HOME_REVEAL)
  useEffect(() => {
    if (hasMessages) return;
    setRevealStage(0);
    const timers = [
      setTimeout(() => setRevealStage(1), 60),
      setTimeout(() => setRevealStage(2), 160),
      setTimeout(() => setRevealStage(3), 240),
      setTimeout(() => setRevealStage(4), 330),
    ];
    return () => timers.forEach(clearTimeout);
  }, [hasMessages, state.activeSessionID, state.articleTitle]);

  // Measure floating composer height so last message rests flush above it
  useEffect(() => {
    const el = composerRef.current;
    if (!el) return;
    const measure = () => setComposerH(el.offsetHeight);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [hasMessages, effectiveQuote, state.mode]);

  // Sticky-bottom auto-scroll (IceCreamHarness ResizeObserver + MutationObserver)
  useEffect(() => {
    if (!hasMessages) return;
    const el = scrollRef.current;
    const content = el?.firstElementChild;
    if (!el || !content) return;

    let stick = true;
    let raf = 0;
    const onScroll = () => {
      stick = el.scrollHeight - el.scrollTop - el.clientHeight < 110;
    };
    const pin = () => {
      if (!stick) return;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        el.scrollTop = el.scrollHeight;
      });
    };

    el.addEventListener("scroll", onScroll, { passive: true });
    const resize = new ResizeObserver(pin);
    resize.observe(content);
    const mutate = new MutationObserver(pin);
    mutate.observe(content, { childList: true, subtree: true, characterData: true });
    pin();

    return () => {
      el.removeEventListener("scroll", onScroll);
      resize.disconnect();
      mutate.disconnect();
      cancelAnimationFrame(raf);
    };
  }, [hasMessages, state.activeSessionID]);

  const handleSend = (text: string) => {
    const quote = effectiveQuote;
    setLocalQuote(null);
    postToNative("send", { text, quote: quote ?? "" });
  };

  const isNews = state.mode === "news";
  const showSidebar = !isNews && state.showSidebar !== false;
  const activeSession = state.sessions.find((s) => s.id === state.activeSessionID);

  return (
    <main className={`flex h-full w-full overflow-hidden text-ink ${showSidebar ? "bg-canvas" : "bg-page"}`}>
      {showSidebar && (
        <SidebarNav
          botName={state.botName}
          botNickname={state.botNickname}
          botAvatarDataURL={state.botAvatarDataURL}
          sessions={state.sessions}
          activeSessionID={state.activeSessionID}
          collapsed={sidebarCollapsed}
          locale={state.locale}
          onToggleCollapse={() => setSidebarCollapsed((v) => !v)}
          onNewChat={() => postToNative("newSession")}
          onSelectSession={(id) => postToNative("selectSession", { id })}
          onDeleteSession={(id) => postToNative("deleteSession", { id })}
          onRenameSession={(id, title) => postToNative("renameSession", { id, title })}
          onTogglePinSession={(id) => postToNative("togglePinSession", { id })}
          onOpenSettings={() => postToNative("openSettings", { target: "bot" })}
        />
      )}

      {/* Main chat surface */}
      <section
        className={`relative flex min-w-0 flex-1 flex-col overflow-hidden bg-page ${
          showSidebar ? "my-1.5 mr-1.5 rounded-[14px] border border-line shadow-hairline" : ""
        }`}
      >
        {/* Minimal clean top header bar */}
        <header className="flex h-11 shrink-0 items-center justify-between gap-2 border-b border-line px-3.5">
          <div className="flex min-w-0 items-center gap-2">
            {isNews ? (
              <>
                <span className="flex size-5 shrink-0 items-center justify-center rounded-[6px] bg-accent-tint text-accent-ink">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                    <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
                  </svg>
                </span>
                <span className="truncate text-[13px] font-semibold text-ink">
                  {state.locale === "zh" ? "AI 精读与追问" : "AI Companion"}
                </span>
              </>
            ) : (
              <>
                <span className="truncate text-[13px] font-semibold text-ink">
                  {activeSession?.title || state.botName}
                </span>
                {state.piAvailable && (
                  <span
                    className="inline-flex h-5 shrink-0 items-center gap-1.5 rounded-full bg-inset px-2 text-[10.5px] font-medium text-ink-2 shadow-hairline"
                    title={state.piStatusLabel || "Pi Kernel Active"}
                  >
                    <span className="size-1.5 rounded-full bg-green" />
                    Pi
                  </span>
                )}
              </>
            )}
          </div>

          <div className="flex shrink-0 items-center gap-1">
            {isNews && hasMessages && !state.isStreaming && (
              <>
                <button
                  type="button"
                  onClick={() => postToNative("quickAction", { action: "saveThreadAsNote" })}
                  title={state.locale === "zh" ? "把当前讨论整理存入编辑器新标签" : "Save thread to editor note"}
                  className="flex h-7 items-center gap-1 rounded-[7px] px-2 text-[11.5px] font-medium text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                    <path d="M14 2v6h6M12 18v-6M9 15h6" />
                  </svg>
                  {state.locale === "zh" ? "存笔记" : "Save"}
                </button>
                <button
                  type="button"
                  onClick={() => postToNative("clearChat")}
                  title={state.locale === "zh" ? "清空当前对话" : "Clear chat"}
                  className="flex h-7 items-center rounded-[7px] px-2 text-[11.5px] font-medium text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  {state.locale === "zh" ? "清空" : "Clear"}
                </button>
              </>
            )}

            {!isNews && !state.isDockedPane && (
              <>
                <button
                  type="button"
                  onClick={() => postToNative("togglePinPanel")}
                  title={
                    state.isPinnedPanel
                      ? state.locale === "zh"
                        ? "已固定窗口（点击取消固定）"
                        : "Pinned (click to unpin)"
                      : state.locale === "zh"
                        ? "固定悬浮窗（切换窗口时不自动关闭）"
                        : "Pin panel open"
                  }
                  className={`flex size-7 items-center justify-center rounded-[7px] transition-colors duration-100 ${
                    state.isPinnedPanel
                      ? "bg-accent-tint text-accent-ink"
                      : "text-ink-3 hover:bg-hover hover:text-ink"
                  }`}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill={state.isPinnedPanel ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 17v5M5 9l7-7 7 7-3 3v4H8v-4z" />
                  </svg>
                </button>
                <button
                  type="button"
                  onClick={() => postToNative("dockToPane")}
                  title={state.locale === "zh" ? "在编辑器分屏中打开" : "Open in split pane"}
                  className="flex h-7 items-center gap-1 rounded-[7px] px-2 text-[11.5px] font-medium text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="3" y="4" width="18" height="16" rx="2.5" />
                    <path d="M14 4v16" />
                  </svg>
                  <span>{state.locale === "zh" ? "分屏" : "Dock"}</span>
                </button>
              </>
            )}

            <button
              type="button"
              onClick={() => postToNative("openSettings", { target: isNews ? "newsBot" : "bot" })}
              title={state.locale === "zh" ? "设置" : "Settings"}
              className="flex size-7 items-center justify-center rounded-[7px] text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="3" />
                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
              </svg>
            </button>
          </div>
        </header>

        {/* Thread or Empty State */}
        {!hasMessages ? (
          <div className="bui-scroll flex min-h-0 flex-1 flex-col justify-center overflow-y-auto px-5 py-6">
            <div className="mx-auto flex w-full max-w-[620px] flex-col">
              <div className="mb-5">
                <p
                  className="text-[19px] font-normal tracking-[-0.02em] text-ink-3"
                  style={homeRevealStyle(revealStage >= 1)}
                >
                  {state.greetingName || (isNews ? (state.locale === "zh" ? "围绕这篇文章" : "About this article") : `Hello`)}
                </p>
                <h1
                  className="text-[20px] font-medium tracking-[-0.02em] text-ink"
                  style={homeRevealStyle(revealStage >= 2)}
                >
                  {state.greetingSubtitle ||
                    (isNews
                      ? state.locale === "zh"
                        ? "想从哪个角度拆解？"
                        : "What would you like to explore?"
                      : state.locale === "zh"
                        ? "查行情、读文档、搜资讯，直接说就行"
                        : "What can I help you with?")}
                </h1>
              </div>

              <div style={homeRevealStyle(revealStage >= 3)}>
                <PromptBar
                  ref={promptBarRef}
                  tall
                  placeholder={state.placeholder}
                  locale={state.locale}
                  isStreaming={state.isStreaming}
                  availableModels={state.availableModels}
                  selectedModelID={state.selectedModelID}
                  selectedModelTitle={state.selectedModelTitle}
                  contextSources={state.contextSources}
                  slashCommands={state.slashCommands}
                  quotedExcerpt={effectiveQuote}
                  effort={state.effort}
                  showEffort={isNews}
                  onClearQuote={() => {
                    setLocalQuote(null);
                    postToNative("clearQuote");
                  }}
                  onSelectModel={(m) => postToNative("selectModel", { model: m })}
                  onSelectEffort={(e) => postToNative("selectEffort", { effort: e })}
                  onOpenSettings={() => postToNative("openSettings", { target: "gateway" })}
                  onSend={handleSend}
                  onAbort={() => postToNative("abort")}
                />
              </div>

              {state.suggestions.length > 0 && (
                <div className="mt-4 flex flex-col" style={homeRevealStyle(revealStage >= 4)}>
                  {state.suggestions.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => handleSend(item.prompt)}
                      className="-mx-2 flex items-center gap-2.5 rounded-control px-2 py-2 text-left text-[13px] text-ink transition-colors duration-120 hover:bg-hover"
                    >
                      <span className="shrink-0 text-ink-3">
                        <SuggestionGlyph kind={item.icon} />
                      </span>
                      <span className="min-w-0 truncate">{item.label}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="relative flex min-h-0 flex-1 flex-col">
            <div ref={scrollRef} className="bui-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain">
              <div
                className="mx-auto flex w-full max-w-[680px] flex-col gap-6 px-4 pt-5"
                style={{ paddingBottom: composerH + 22 }}
              >
                {state.messages.map((msg, idx) => {
                  const isLastAssistant =
                    msg.role === "assistant" && idx === state.messages.length - 1;
                  return msg.role === "user" ? (
                    <UserBubble key={msg.id} text={msg.text} quoteContext={msg.quoteContext} />
                  ) : (
                    <AssistantMessageBlock
                      key={msg.id}
                      message={msg}
                      locale={state.locale}
                      statusLabel={isLastAssistant ? state.streamingStatusLabel : undefined}
                      onRetry={
                        isLastAssistant && !state.isStreaming
                          ? () => postToNative("retry")
                          : undefined
                      }
                      onInsert={(text) => postToNative("insertToEditor", { text })}
                      onOpenNote={(text) => postToNative("openNewDocument", { text })}
                      onFollowUp={(prompt) => handleSend(prompt)}
                    />
                  );
                })}

                {state.errorMessage && (
                  <div
                    className="flex items-center gap-2.5 rounded-[10px] bg-surface px-3 py-2.5 text-[12px] text-ink-2 shadow-card"
                    style={{ animation: "fade-up 200ms ease-out both" }}
                  >
                    <span className="size-1.5 shrink-0 rounded-full bg-orange" />
                    <span className="min-w-0 flex-1 break-words">{state.errorMessage}</span>
                    <button
                      type="button"
                      onClick={() => postToNative("openSettings", { target: "gateway" })}
                      className="shrink-0 font-medium text-accent-ink hover:underline"
                    >
                      {state.locale === "zh" ? "去设置" : "Settings"}
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* Soft gradient fade into floating PromptBar (IceCreamHarness style) */}
            <div
              className="pointer-events-none absolute inset-x-0 bottom-0"
              style={{
                height: composerH + 26,
                background: "linear-gradient(to top, var(--page) 68%, transparent)",
              }}
            />

            {/* Floating PromptBar */}
            <div ref={composerRef} className="absolute inset-x-0 bottom-0 px-3.5 pb-3.5">
              <div className="mx-auto max-w-[680px]">
                <PromptBar
                  ref={promptBarRef}
                  placeholder={state.placeholder}
                  locale={state.locale}
                  isStreaming={state.isStreaming}
                  availableModels={state.availableModels}
                  selectedModelID={state.selectedModelID}
                  selectedModelTitle={state.selectedModelTitle}
                  contextSources={state.contextSources}
                  slashCommands={state.slashCommands}
                  quotedExcerpt={effectiveQuote}
                  effort={state.effort}
                  showEffort={isNews}
                  onClearQuote={() => {
                    setLocalQuote(null);
                    postToNative("clearQuote");
                  }}
                  onSelectModel={(m) => postToNative("selectModel", { model: m })}
                  onSelectEffort={(e) => postToNative("selectEffort", { effort: e })}
                  onOpenSettings={() => postToNative("openSettings", { target: "gateway" })}
                  onSend={handleSend}
                  onAbort={() => postToNative("abort")}
                />
              </div>
            </div>
          </div>
        )}
      </section>
    </main>
  );
}
