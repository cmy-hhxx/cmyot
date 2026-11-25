import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react";
import { copyTextWithFallback, postToNative } from "./bridge";
import LoadingState from "./primitives/LoadingState";
import MarkdownProse from "./primitives/MarkdownProse";
import PromptBar, { type PromptBarHandle } from "./primitives/PromptBar";
import SidebarNav from "./primitives/SidebarNav";
import ThinkingState from "./primitives/ThinkingState";
import ToolChips from "./primitives/ToolChips";
import type {
  AgentMessage,
  AttachedDocumentRef,
  HostState,
  StreamPatch,
  WorkspaceOption,
} from "./types";

/* ─────────────────────────────────────────────────────────
 * COT BEAUTIFUL AGENT HARNESS
 *   · Workspace-scoped sessions with folder binding
 *   · Clean, distraction-free New Session empty state (no tiny text, no kernel jargon, no hook prompts)
 *   · @Document + @Bot multi-agent delegation
 *   · Borderless assistant prose directly on --page (14px base, ≥12.5px floor everywhere)
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
  placeholder: "输入问题，输入 @ 引用文档或指派助手…",
  availableModels: [],
  selectedModelID: "",
  selectedModelTitle: "",
  suggestions: [],
  contextSources: [],
  slashCommands: [],
  availableWorkspaces: [],
  availableDocuments: [],
  availableBots: [],
};

function homeRevealStyle(visible: boolean): CSSProperties {
  return {
    opacity: visible ? 1 : 0,
    transform: visible ? "translate3d(0, 0, 0)" : "translate3d(0, 12px, 0)",
    filter: visible ? "blur(0px)" : "blur(8px)",
    transition:
      "opacity 460ms cubic-bezier(0.16, 1, 0.3, 1), transform 460ms cubic-bezier(0.16, 1, 0.3, 1), filter 460ms cubic-bezier(0.16, 1, 0.3, 1)",
  };
}

function UserBubble({
  text,
  quoteContext,
  attachedDocuments,
  delegatedBotName,
}: {
  text: string;
  quoteContext?: string;
  attachedDocuments?: string[];
  delegatedBotName?: string;
}) {
  const hasAttachments = Boolean((attachedDocuments && attachedDocuments.length > 0) || delegatedBotName);
  return (
    <div
      className="flex flex-col items-end gap-1.5 pl-10"
      style={{ animation: "fade-up 240ms cubic-bezier(0.23,1,0.32,1) both" }}
    >
      {hasAttachments && (
        <div className="flex max-w-[92%] flex-wrap justify-end gap-1.5">
          {attachedDocuments?.map((title, idx) => (
            <span
              key={`${title}-${idx}`}
              className="inline-flex h-7 max-w-[240px] items-center gap-1.5 rounded-[8px] bg-inset px-2.5 text-[13px] font-medium text-ink-2 shadow-hairline"
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6M8 13h8M8 17h5" />
              </svg>
              <span className="truncate">{title}</span>
            </span>
          ))}
          {delegatedBotName && (
            <span className="inline-flex h-7 items-center gap-1.5 rounded-[8px] bg-accent-tint px-2.5 text-[13px] font-medium text-accent-ink">
              <span>@{delegatedBotName}</span>
            </span>
          )}
        </div>
      )}
      {quoteContext && (
        <div className="max-w-[85%] rounded-[9px] bg-inset px-3 py-1.5 text-[13px] leading-snug text-ink-2 shadow-hairline">
          <span className="line-clamp-2">{quoteContext}</span>
        </div>
      )}
      <div className="max-w-[92%] select-text whitespace-pre-wrap break-words rounded-[13px] bg-field px-3.5 py-2.5 text-[14px] leading-relaxed text-ink shadow-hairline">
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
  onInsert?: (text: string) => void;
  onOpenNote?: (text: string) => void;
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
      {message.delegatedBotName && (
        <div className="mb-1.5 flex items-center gap-2 text-[13px]">
          <span className="inline-flex h-6.5 items-center gap-1.5 rounded-[7px] bg-accent-tint px-2.5 font-medium text-accent-ink">
            <span className="size-1.5 rounded-full bg-accent" />
            {message.delegatedBotName}
          </span>
          {message.delegatedModel && (
            <span className="truncate text-[13px] text-ink-3">{message.delegatedModel}</span>
          )}
        </div>
      )}

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
              startedAtMs={message.createdAt}
              locale={locale}
              activeLabel={statusLabel}
            />
          )}

          {hasText ? (
            <div className={message.isError ? "rounded-card bg-red-tint px-3.5 py-2.5 text-[13.5px] text-red" : ""}>
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

          {/* Quiet Beautiful UI action row */}
          {!message.isStreaming && hasText && !message.isError && (
            <div
              className="mt-2.5 flex items-center gap-1 text-ink-3"
              style={{ animation: "fade-in 240ms ease-out both" }}
            >
              <button
                type="button"
                onClick={handleCopy}
                title={copied ? (locale === "zh" ? "已复制" : "Copied") : locale === "zh" ? "复制全文" : "Copy"}
                className={`flex h-7 items-center gap-1.5 rounded-[7px] px-2 text-[13px] transition-colors duration-100 hover:bg-hover-2 ${
                  copied ? "text-green" : "text-ink-3 hover:text-ink-2"
                }`}
              >
                {copied ? (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                ) : (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="9" y="9" width="12" height="12" rx="2.5" />
                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                  </svg>
                )}
                <span>{copied ? (locale === "zh" ? "已复制" : "Copied") : locale === "zh" ? "复制" : "Copy"}</span>
              </button>

              {onRetry && (
                <button
                  type="button"
                  onClick={onRetry}
                  title={locale === "zh" ? "重新生成" : "Retry"}
                  className="flex size-7 items-center justify-center rounded-[7px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 12a9 9 0 1 1-2.64-6.36M21 3v6h-6" />
                  </svg>
                </button>
              )}

              {onInsert && (
                <button
                  type="button"
                  onClick={() => onInsert(message.text)}
                  title={locale === "zh" ? "插入到当前编辑器光标处" : "Insert at editor cursor"}
                  className="flex h-7 items-center gap-1.5 rounded-[7px] px-2 text-[13px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 5v14M5 12l7 7 7-7" />
                  </svg>
                  <span>{locale === "zh" ? "插入" : "Insert"}</span>
                </button>
              )}

              {onOpenNote && (
                <button
                  type="button"
                  onClick={() => onOpenNote(message.text)}
                  title={locale === "zh" ? "存为新文档标签页" : "Save as new note tab"}
                  className="flex h-7 items-center gap-1.5 rounded-[7px] px-2 text-[13px] transition-colors duration-100 hover:bg-hover-2 hover:text-ink-2"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                    <path d="M14 2v6h6M12 18v-6M9 15h6" />
                  </svg>
                  <span>{locale === "zh" ? "存笔记" : "Note"}</span>
                </button>
              )}
            </div>
          )}

          {/* Contextual clickable follow-up prompts */}
          {!message.isStreaming && message.followUps && message.followUps.length > 0 && (
            <div className="mt-3.5" style={{ animation: "fade-in 300ms ease-out both" }}>
              <p className="mb-1 text-[13px] font-medium text-ink-3">
                {locale === "zh" ? "继续追问" : "Follow-ups"}
              </p>
              <div className="flex flex-col">
                {message.followUps.map((prompt, i) => (
                  <button
                    key={prompt}
                    type="button"
                    onClick={() => onFollowUp(prompt)}
                    className="-mx-1.5 flex items-center gap-2 rounded-[7px] border-b border-line px-1.5 py-2 text-left text-[13.5px] text-ink transition-colors duration-100 last:border-b-0 hover:bg-hover-2"
                    style={{ animation: `fade-up 300ms cubic-bezier(0.23,1,0.32,1) ${i * 70}ms both` }}
                  >
                    <svg
                      width="13"
                      height="13"
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

function WorkspacePickerMenu({
  activeWorkspaceID,
  activeWorkspaceName,
  activeWorkspacePath,
  availableWorkspaces,
  locale,
  onSelectWorkspace,
  onCreateWorkspace,
  onChooseFolder,
  onLinkWorkspaceFolder,
  onUnlinkWorkspaceFolder,
}: {
  activeWorkspaceID?: string | null;
  activeWorkspaceName?: string | null;
  activeWorkspacePath?: string | null;
  availableWorkspaces: WorkspaceOption[];
  locale: "zh" | "en";
  onSelectWorkspace: (workspaceID: string | null) => void;
  onCreateWorkspace: (name: string) => void;
  onChooseFolder: () => void;
  onLinkWorkspaceFolder: (workspaceID: string) => void;
  onUnlinkWorkspaceFolder: (workspaceID: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [draftName, setDraftName] = useState("");
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) {
      setCreating(false);
      setDraftName("");
      return;
    }
    const onDown = (e: PointerEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [open]);

  const activeWS = availableWorkspaces.find((w) => w.id === activeWorkspaceID);
  const isBound = Boolean(activeWorkspaceID && activeWorkspaceName);
  const isFolderBacked = Boolean(activeWS?.isFolderBacked || activeWorkspacePath);

  const submitNew = () => {
    const clean = draftName.trim();
    if (clean) {
      onCreateWorkspace(clean);
      setOpen(false);
    }
    setCreating(false);
    setDraftName("");
  };

  return (
    <div ref={wrapRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        title={activeWorkspacePath || activeWorkspaceName || (locale === "zh" ? "设置会话所属工作区" : "Select workspace")}
        className={`inline-flex h-7.5 max-w-[200px] items-center gap-1.5 rounded-[8px] px-2.5 text-[13px] font-medium transition-colors duration-120 ${
          isBound
            ? "bg-accent-tint text-accent-ink hover:opacity-90"
            : "bg-inset text-ink-2 shadow-hairline hover:bg-hover hover:text-ink"
        }`}
      >
        {isFolderBacked ? (
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
            <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
          </svg>
        ) : (
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
            <rect x="3" y="3" width="7" height="7" rx="1.5" />
            <rect x="14" y="3" width="7" height="7" rx="1.5" />
            <rect x="3" y="14" width="7" height="7" rx="1.5" />
            <rect x="14" y="14" width="7" height="7" rx="1.5" />
          </svg>
        )}
        <span className="truncate">
          {isBound ? activeWorkspaceName : locale === "zh" ? "工作区" : "Workspace"}
        </span>
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 opacity-70">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      {open && (
        <div
          className="absolute left-0 top-full z-30 mt-1.5 w-76 overflow-hidden rounded-[12px] bg-surface p-1.5 shadow-raised"
          style={{ animation: "pop-in 150ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "top left" }}
        >
          {availableWorkspaces.length > 0 && (
            <div className="bui-scroll max-h-56 overflow-y-auto">
              {availableWorkspaces.map((ws) => {
                const selected = ws.id === activeWorkspaceID;
                return (
                  <button
                    key={ws.id}
                    type="button"
                    onClick={() => {
                      onSelectWorkspace(ws.id);
                      setOpen(false);
                    }}
                    className={`flex w-full items-center gap-2.5 rounded-[8px] px-2.5 py-2 text-left transition-colors duration-100 hover:bg-hover ${
                      selected ? "bg-hover" : ""
                    }`}
                  >
                    {ws.isFolderBacked ? (
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${selected ? "text-accent-ink" : "text-ink-2"}`}>
                        <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                      </svg>
                    ) : (
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${selected ? "text-accent-ink" : "text-ink-2"}`}>
                        <rect x="3" y="3" width="7" height="7" rx="1.5" />
                        <rect x="14" y="3" width="7" height="7" rx="1.5" />
                        <rect x="3" y="14" width="7" height="7" rx="1.5" />
                        <rect x="14" y="14" width="7" height="7" rx="1.5" />
                      </svg>
                    )}
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <span className="truncate text-[13.5px] font-medium text-ink">{ws.name}</span>
                      </div>
                      <div className="truncate text-[12.5px] text-ink-3">{ws.subtitle}</div>
                    </div>
                    {selected && (
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-accent-ink">
                        <path d="M20 6L9 17l-5-5" />
                      </svg>
                    )}
                  </button>
                );
              })}
              <div className="my-1 border-t border-line" />
            </div>
          )}

          {creating ? (
            <div className="flex items-center gap-1.5 rounded-[8px] bg-inset px-2.5 py-1.5 shadow-hairline">
              <input
                autoFocus
                value={draftName}
                onChange={(e) => setDraftName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") submitNew();
                  if (e.key === "Escape") {
                    setCreating(false);
                    setDraftName("");
                  }
                }}
                placeholder={locale === "zh" ? "输入工作区名称，回车创建…" : "Workspace name…"}
                className="min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none placeholder:text-ink-3 select-text"
              />
              <button
                type="button"
                onClick={submitNew}
                className="shrink-0 rounded-[6px] bg-accent-tint px-2 py-0.5 text-[12.5px] font-medium text-accent-ink"
              >
                {locale === "zh" ? "创建" : "Create"}
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setCreating(true)}
              className="flex h-9 w-full items-center gap-2 rounded-[8px] px-2.5 text-left text-[13.5px] font-medium text-ink transition-colors duration-100 hover:bg-hover"
            >
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-ink-2">
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span>{locale === "zh" ? "新建工作区…" : "New workspace…"}</span>
            </button>
          )}

          {isBound && activeWorkspaceID ? (
            <>
              <button
                type="button"
                onClick={() => {
                  setOpen(false);
                  onLinkWorkspaceFolder(activeWorkspaceID);
                }}
                className="flex h-9 w-full items-center gap-2 rounded-[8px] px-2.5 text-left text-[13.5px] text-ink transition-colors duration-100 hover:bg-hover"
              >
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-ink-2">
                  <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                </svg>
                <span>
                  {isFolderBacked
                    ? locale === "zh"
                      ? "更换关联文件夹…"
                      : "Change folder…"
                    : locale === "zh"
                      ? "关联本地文件夹…"
                      : "Link local folder…"}
                </span>
              </button>

              {isFolderBacked && (
                <button
                  type="button"
                  onClick={() => {
                    onUnlinkWorkspaceFolder(activeWorkspaceID);
                    setOpen(false);
                  }}
                  className="flex h-9 w-full items-center gap-2 rounded-[8px] px-2.5 text-left text-[13.5px] text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-ink-3">
                    <path d="M18 6L6 18M6 6l12 12" />
                  </svg>
                  <span>{locale === "zh" ? "取消文件夹关联" : "Unlink folder"}</span>
                </button>
              )}

              <button
                type="button"
                onClick={() => {
                  onSelectWorkspace(null);
                  setOpen(false);
                }}
                className="flex h-9 w-full items-center gap-2 rounded-[8px] px-2.5 text-left text-[13.5px] text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
              >
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-ink-3">
                  <path d="M9 14l-4-4 4-4M5 10h11a4 4 0 0 1 0 8h-1" />
                </svg>
                <span>{locale === "zh" ? "移至通用会话" : "Move to General"}</span>
              </button>
            </>
          ) : (
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                onChooseFolder();
              }}
              className="flex h-9 w-full items-center gap-2 rounded-[8px] px-2.5 text-left text-[13.5px] text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
            >
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-ink-3">
                <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
              </svg>
              <span>{locale === "zh" ? "关联本地文件夹…" : "Link local folder…"}</span>
            </button>
          )}
        </div>
      )}
    </div>
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
  const [composerH, setComposerH] = useState(118);

  const scrollRef = useRef<HTMLDivElement>(null);
  const composerRef = useRef<HTMLDivElement>(null);
  const promptBarRef = useRef<PromptBarHandle>(null);
  const pendingPatchRef = useRef<StreamPatch | null>(null);
  const patchRafRef = useRef<number | null>(null);

  const effectiveQuote = localQuote ?? state.quotedExcerpt ?? null;
  const hasMessages = state.messages.length > 0;

  const applyThemeClass = useCallback((isDark: boolean, pageHex?: string | null, canvasHex?: string | null) => {
    const root = document.documentElement;
    const themeChanged = root.classList.contains("dark") !== isDark;
    if (themeChanged) {
      root.classList.add("theme-switching");
      root.classList.toggle("dark", isDark);
    }
    if (pageHex) root.style.setProperty("--page", pageHex);
    else root.style.removeProperty("--page");
    if (canvasHex) root.style.setProperty("--canvas", canvasHex);
    else root.style.removeProperty("--canvas");
    if (themeChanged) {
      requestAnimationFrame(() => {
        root.classList.remove("theme-switching");
      });
    }
  }, []);

  useEffect(() => {
    applyThemeClass(state.isDark, state.themePageHex, state.themeCanvasHex);
  }, [state.isDark, state.themePageHex, state.themeCanvasHex, applyThemeClass]);

  useEffect(() => {
    const flushPendingPatch = () => {
      patchRafRef.current = null;
      const patch = pendingPatchRef.current;
      if (!patch) return;
      pendingPatchRef.current = null;
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
                createdAt: Date.now(),
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
    };

    window.CotAgentBridge = {
      setState: (next: HostState) => {
        pendingPatchRef.current = null;
        if (patchRafRef.current !== null) {
          cancelAnimationFrame(patchRafRef.current);
          patchRafRef.current = null;
        }
        applyThemeClass(next.isDark, next.themePageHex, next.themeCanvasHex);
        setState(next);
        if (next.quotedExcerpt !== undefined && next.quotedExcerpt !== null) {
          setLocalQuote(next.quotedExcerpt);
        }
      },
      setTheme: (isDark: boolean) => {
        applyThemeClass(isDark, state.themePageHex, state.themeCanvasHex);
        setState((prev) => (prev.isDark === isDark ? prev : { ...prev, isDark }));
      },
      patchStreaming: (patch: StreamPatch) => {
        const prevPending = pendingPatchRef.current;
        if (prevPending && prevPending.messageId === patch.messageId) {
          pendingPatchRef.current = {
            messageId: patch.messageId,
            text: patch.text !== undefined ? patch.text : prevPending.text,
            thinking: patch.thinking !== undefined ? patch.thinking : prevPending.thinking,
            thinkingDurationMs:
              patch.thinkingDurationMs !== undefined ? patch.thinkingDurationMs : prevPending.thinkingDurationMs,
            steps: patch.steps !== undefined ? patch.steps : prevPending.steps,
            statusLabel: patch.statusLabel !== undefined ? patch.statusLabel : prevPending.statusLabel,
          };
        } else {
          pendingPatchRef.current = patch;
        }
        if (patchRafRef.current === null) {
          patchRafRef.current = requestAnimationFrame(flushPendingPatch);
        }
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
      if (patchRafRef.current !== null) {
        cancelAnimationFrame(patchRafRef.current);
        patchRafRef.current = null;
      }
      pendingPatchRef.current = null;
      delete window.CotAgentBridge;
    };
  }, [applyThemeClass]);

  useEffect(() => {
    if (hasMessages) return;
    setRevealStage(0);
    const timers = [
      setTimeout(() => setRevealStage(1), 45),
      setTimeout(() => setRevealStage(2), 130),
      setTimeout(() => setRevealStage(3), 210),
      setTimeout(() => setRevealStage(4), 290),
    ];
    return () => timers.forEach(clearTimeout);
  }, [hasMessages, state.activeSessionID, state.articleTitle]);

  useEffect(() => {
    const el = composerRef.current;
    if (!el) return;
    const measure = () => setComposerH(el.offsetHeight);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [hasMessages, effectiveQuote, state.mode]);

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

  const handleSend = (text: string, documents: AttachedDocumentRef[] = [], botId: string | null = null) => {
    const quote = effectiveQuote;
    setLocalQuote(null);
    postToNative("send", {
      text,
      quote: quote ?? "",
      documents,
      botId: botId ?? "",
    });
  };

  const isNews = state.mode === "news";
  const showSidebar = !isNews && state.showSidebar !== false;
  const activeSession = state.sessions.find((s) => s.id === state.activeSessionID);
  const availableWorkspaces = state.availableWorkspaces ?? [];
  const availableDocuments = state.availableDocuments ?? [];
  const availableBots = state.availableBots ?? [];

  const butlerEmptyHeading = activeSession?.workspaceName
    ? state.locale === "zh"
      ? `在「${activeSession.workspaceName}」中提问`
      : `Ask in ${activeSession.workspaceName}`
    : state.greetingName
      ? state.locale === "zh"
        ? `你好，${state.greetingName}`
        : `Hello, ${state.greetingName}`
      : state.botName;

  return (
    <main className="flex h-full w-full overflow-hidden bg-page text-ink">
      {showSidebar && (
        <SidebarNav
          botName={state.botName}
          botAvatarDataURL={state.botAvatarDataURL}
          sessions={state.sessions}
          activeSessionID={state.activeSessionID}
          availableWorkspaces={availableWorkspaces}
          collapsed={sidebarCollapsed}
          locale={state.locale}
          onToggleCollapse={() => setSidebarCollapsed((v) => !v)}
          onNewChat={(workspaceID, workspacePath) =>
            postToNative("newSession", {
              workspaceId: workspaceID ?? "",
              workspacePath: workspacePath ?? "",
            })
          }
          onCreateWorkspace={(name) =>
            postToNative("createWorkspace", { name, startSession: true })
          }
          onRenameWorkspace={(id, name) => postToNative("renameWorkspace", { id, name })}
          onDeleteWorkspace={(id) => postToNative("deleteWorkspace", { id })}
          onChooseWorkspaceFolder={(workspaceId) =>
            postToNative("chooseWorkspaceFolderForWorkspace", { workspaceId })
          }
          onUnlinkWorkspaceFolder={(id) =>
            postToNative("updateWorkspaceFolder", { id, folderPath: "" })
          }
          onReorderWorkspaces={(orderedIds) =>
            postToNative("reorderWorkspaces", { orderedIds })
          }
          onMoveSession={(sessionId, targetWorkspaceId, orderedSessionIds, isPinned) =>
            postToNative("moveSession", {
              sessionId,
              targetWorkspaceId: targetWorkspaceId ?? "",
              orderedSessionIds,
              ...(isPinned !== undefined ? { isPinned } : {}),
            })
          }
          onSelectSession={(id) => postToNative("selectSession", { id })}
          onDeleteSession={(id) => postToNative("deleteSession", { id })}
          onRenameSession={(id, title) => postToNative("renameSession", { id, title })}
          onTogglePinSession={(id) => postToNative("togglePinSession", { id })}
          onOpenSettings={() => postToNative("openSettings", { target: "bot" })}
        />
      )}

      {/* Main chat surface */}
      <section className="relative flex min-w-0 flex-1 flex-col overflow-hidden bg-page">
        {/* Clean top header bar */}
        <header className="flex h-12 shrink-0 items-center justify-between gap-2 border-b border-line px-4">
          <div className="flex min-w-0 items-center gap-2.5">
            {isNews ? (
              <span className="truncate text-[14px] font-semibold text-ink">
                {state.locale === "zh" ? "AI 精读与追问" : "AI Companion"}
              </span>
            ) : (
              <>
                <span className="truncate text-[14px] font-semibold text-ink">
                  {activeSession?.title || state.botName}
                </span>
                <WorkspacePickerMenu
                  activeWorkspaceID={activeSession?.workspaceID}
                  activeWorkspaceName={activeSession?.workspaceName}
                  activeWorkspacePath={activeSession?.workspacePath}
                  availableWorkspaces={availableWorkspaces}
                  locale={state.locale}
                  onSelectWorkspace={(wsID) =>
                    postToNative("setSessionWorkspace", {
                      sessionId: state.activeSessionID,
                      workspaceId: wsID ?? "",
                    })
                  }
                  onCreateWorkspace={(name) =>
                    postToNative("createWorkspace", {
                      name,
                      startSession: false,
                      assignSessionId: state.activeSessionID,
                    })
                  }
                  onChooseFolder={() =>
                    postToNative("chooseWorkspaceFolder", {
                      sessionId: state.activeSessionID,
                      createNew: false,
                    })
                  }
                  onLinkWorkspaceFolder={(workspaceId) =>
                    postToNative("chooseWorkspaceFolderForWorkspace", { workspaceId })
                  }
                  onUnlinkWorkspaceFolder={(id) =>
                    postToNative("updateWorkspaceFolder", { id, folderPath: "" })
                  }
                />
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
                  className="flex h-7.5 items-center gap-1.5 rounded-[7px] px-2.5 text-[13px] font-medium text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                    <path d="M14 2v6h6M12 18v-6M9 15h6" />
                  </svg>
                  {state.locale === "zh" ? "存笔记" : "Save"}
                </button>
                <button
                  type="button"
                  onClick={() => postToNative("clearChat")}
                  title={state.locale === "zh" ? "清空当前对话" : "Clear chat"}
                  className="flex h-7.5 items-center rounded-[7px] px-2.5 text-[13px] font-medium text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
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
                  className={`flex size-7.5 items-center justify-center rounded-[7px] transition-colors duration-100 ${
                    state.isPinnedPanel
                      ? "bg-accent-tint text-accent-ink"
                      : "text-ink-3 hover:bg-hover hover:text-ink"
                  }`}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill={state.isPinnedPanel ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 17v5M5 9l7-7 7 7-3 3v4H8v-4z" />
                  </svg>
                </button>
                <button
                  type="button"
                  onClick={() => postToNative("dockToPane")}
                  title={state.locale === "zh" ? "在编辑器分屏中打开" : "Open in split pane"}
                  className="flex h-7.5 items-center gap-1.5 rounded-[7px] px-2.5 text-[13px] font-medium text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
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
              className="flex size-7.5 items-center justify-center rounded-[7px] text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
            >
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="3" />
                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
              </svg>
            </button>
          </div>
        </header>

        {/* Background Worker Watchdog Strip (DeepSeek Super-Agent Visibility) */}
        {!isNews && state.backgroundWorkers && state.backgroundWorkers.length > 0 && (
          <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-line bg-surface/65 px-4 py-1.5">
            {state.backgroundWorkers.map((worker) => (
              <div
                key={worker.id}
                className="flex max-w-full items-center gap-2 rounded-full border border-line bg-page px-2.5 py-1 text-[12px] text-ink-2"
              >
                <span
                  className={`size-1.5 shrink-0 rounded-full ${
                    worker.status === "running"
                      ? "animate-pulse bg-accent"
                      : worker.status === "done"
                        ? "bg-green"
                        : "bg-red"
                  }`}
                />
                <span className="max-w-[240px] truncate font-medium text-ink">{worker.title}</span>
                {worker.detail && (
                  <span className="hidden max-w-[200px] truncate text-[11px] text-ink-3 sm:inline">
                    {worker.detail}
                  </span>
                )}
                {worker.status === "done" && worker.actionBoard && (
                  <button
                    type="button"
                    onClick={() =>
                      postToNative("openWorkerAction", {
                        board: worker.actionBoard,
                        query: worker.actionQuery || "",
                      })
                    }
                    className="shrink-0 rounded-full bg-accent-tint px-2 py-0.5 text-[11px] font-medium text-accent-ink transition-colors hover:opacity-85"
                  >
                    {state.locale === "zh" ? "去查看" : "Open"}
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => postToNative("dismissWorker", { id: worker.id })}
                  className="shrink-0 text-ink-3 hover:text-ink"
                  aria-label="Dismiss worker"
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}

        {/* Thread or Empty State */}
        {!hasMessages ? (
          <div className="bui-scroll flex min-h-0 flex-1 flex-col justify-center overflow-y-auto px-6 py-8">
            <div className="mx-auto flex w-full max-w-[640px] flex-col">
              <div className="mb-5" style={homeRevealStyle(revealStage >= 1)}>
                <h1 className="text-[22px] font-semibold tracking-[-0.02em] text-ink">
                  {isNews
                    ? state.greetingName || (state.locale === "zh" ? "围绕这篇文章" : "About this article")
                    : butlerEmptyHeading}
                </h1>
              </div>

              <div style={homeRevealStyle(revealStage >= 2)}>
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
                  availableDocuments={availableDocuments}
                  availableBots={availableBots}
                  quotedExcerpt={effectiveQuote}
                  effort={state.effort}
                  showEffort={false}
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

              {!isNews && state.proactiveCards && state.proactiveCards.length > 0 && (
                <div
                  className="mt-4 grid grid-cols-1 gap-2.5 sm:grid-cols-3"
                  style={homeRevealStyle(revealStage >= 3)}
                >
                  {state.proactiveCards.map((card) => (
                    <div
                      key={card.id}
                      onClick={() => handleSend(card.prompt)}
                      role="button"
                      tabIndex={0}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          handleSend(card.prompt);
                        }
                      }}
                      className="group relative flex cursor-pointer flex-col justify-between rounded-[11px] border border-line bg-surface/80 p-3 text-left transition-all duration-150 hover:border-line-strong hover:bg-hover"
                    >
                      <div className="mb-1.5 flex items-center justify-between gap-2">
                        <span className="rounded-full bg-accent-tint px-2 py-0.5 text-[10.5px] font-semibold text-accent-ink">
                          {card.badge}
                        </span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            postToNative("dismissProactiveCard", { id: card.id });
                          }}
                          className="rounded p-0.5 text-[12px] leading-none text-ink-3 opacity-0 transition-opacity group-hover:opacity-100 hover:text-ink"
                          aria-label="Dismiss card"
                        >
                          ×
                        </button>
                      </div>
                      <div className="line-clamp-2 text-[12.5px] font-semibold leading-snug text-ink">
                        {card.title}
                      </div>
                      <div className="mt-1 line-clamp-1 text-[11px] text-ink-3">
                        {card.subtitle}
                      </div>
                    </div>
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
                style={{ paddingBottom: composerH + 24 }}
              >
                {state.messages.map((msg, idx) => {
                  const isLastAssistant =
                    msg.role === "assistant" && idx === state.messages.length - 1;
                  return msg.role === "user" ? (
                    <UserBubble
                      key={msg.id}
                      text={msg.text}
                      quoteContext={msg.quoteContext}
                      attachedDocuments={msg.attachedDocuments}
                      delegatedBotName={msg.delegatedBotName}
                    />
                  ) : (
                    <AssistantMessageBlock
                      key={msg.id}
                      message={msg}
                      locale={state.locale}
                      statusLabel={isLastAssistant ? state.streamingStatusLabel : undefined}
                      onRetry={
                        isNews && isLastAssistant && !state.isStreaming
                          ? () => postToNative("retry")
                          : undefined
                      }
                      onInsert={isNews ? (text) => postToNative("insertToEditor", { text }) : undefined}
                      onOpenNote={isNews ? (text) => postToNative("openNewDocument", { text }) : undefined}
                      onFollowUp={(prompt) => handleSend(prompt)}
                    />
                  );
                })}

                {state.errorMessage && (
                  <div
                    className="flex items-center gap-2.5 rounded-[10px] bg-surface px-3.5 py-2.5 text-[13px] text-ink-2 shadow-card"
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

            {/* Soft gradient fade into floating PromptBar */}
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
                  availableDocuments={availableDocuments}
                  availableBots={availableBots}
                  quotedExcerpt={effectiveQuote}
                  effort={state.effort}
                  showEffort={false}
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
