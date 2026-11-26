import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { copyTextWithFallback } from "../bridge";
import LoadingState from "./LoadingState";
import MarkdownProse from "./MarkdownProse";
import PromptBar, { type PromptBarHandle } from "./PromptBar";
import type {
  BotMentionItem,
  MeetingRoomMessage,
  MeetingRoomParticipant,
  ModelOption,
} from "../types";

type MeetingRoomViewProps = {
  locale: "zh" | "en";
  messages: MeetingRoomMessage[];
  participants: MeetingRoomParticipant[];
  isConvening: boolean;
  availableModels: ModelOption[];
  selectedModelID: string;
  selectedModelTitle: string;
  onSend: (text: string, botId?: string | null) => void;
  onAbort: () => void;
  onSelectModel: (model: ModelOption) => void;
  onOpenSettings: () => void;
};

const BotSpeakerTurn = memo(function BotSpeakerTurn({
  message,
  locale,
}: {
  message: MeetingRoomMessage;
  locale: "zh" | "en";
}) {
  const [copied, setCopied] = useState(false);
  const accentColor = message.botAccentHex || "var(--accent)";
  const isButler = message.botID === "butler";
  const isSpeaking = message.status === "speaking";

  const handleCopy = () => {
    copyTextWithFallback(message.text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };

  return (
    <article
      className={`min-w-0 rounded-[12px] border border-line px-4 py-3 ${
        isButler ? "bg-surface shadow-hairline" : "bg-canvas/55"
      }`}
    >
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <span
          className="size-2 shrink-0 rounded-full"
          style={{ backgroundColor: accentColor }}
        />
        <span className="text-[13.5px] font-semibold text-ink">
          {message.botName || message.botID || "Bot"}
        </span>
        {message.botRoleLabel && (
          <span className="rounded-[6px] bg-inset px-2 py-0.5 text-[12px] font-medium text-ink-2">
            {message.botRoleLabel}
          </span>
        )}
        {message.delegatedFromButler && (
          <span className="rounded-[6px] bg-accent-tint px-2 py-0.5 text-[12px] font-medium text-accent-ink">
            {locale === "zh" ? "总管调度" : "Dispatched"}
          </span>
        )}
        <div className="ml-auto flex items-center gap-1.5">
          {!isSpeaking && message.text.trim().length > 0 && (
            <button
              type="button"
              onClick={handleCopy}
              className="rounded-[6px] px-2 py-0.5 text-[12.5px] text-ink-3 transition-colors hover:bg-hover hover:text-ink"
            >
              {copied ? (locale === "zh" ? "已复制" : "Copied") : locale === "zh" ? "复制" : "Copy"}
            </button>
          )}
        </div>
      </div>

      {message.receipts && message.receipts.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-1.5">
          {message.receipts.map((receipt, idx) => (
            <span
              key={`${message.id}-r-${idx}`}
              className="rounded-[6px] bg-inset px-2 py-0.5 text-[12px] text-ink-2 shadow-hairline"
            >
              {receipt}
            </span>
          ))}
        </div>
      )}

      {isSpeaking && !message.text.trim() ? (
        <div className="py-1">
          <LoadingState
            label={locale === "zh" ? "正在整理汇报" : "Preparing report"}
            variant="Dots"
          />
        </div>
      ) : (
        <MarkdownProse markdown={message.text} isStreaming={isSpeaking} locale={locale} />
      )}
    </article>
  );
});

const MeetingRoomView = memo(function MeetingRoomView({
  locale,
  messages,
  participants,
  isConvening,
  availableModels,
  selectedModelID,
  selectedModelTitle,
  onSend,
  onAbort,
  onSelectModel,
  onOpenSettings,
}: MeetingRoomViewProps) {
  const promptBarRef = useRef<PromptBarHandle>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const composerRef = useRef<HTMLDivElement>(null);
  const [composerH, setComposerH] = useState(112);

  const hasMessages = messages.length > 0;

  const mentionBots = useMemo<BotMentionItem[]>(
    () =>
      participants.map((p) => ({
        id: p.id,
        name: p.name,
        nickname: p.nickname,
        handle: p.handle,
        tagline: p.todayBadge || p.roleLabel,
        accentHex: p.accentHex,
      })),
    [participants],
  );

  useEffect(() => {
    const el = composerRef.current;
    if (!el) return;
    let rafId = 0;
    const measure = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        const nextH = el.offsetHeight;
        setComposerH((prev) => (prev === nextH ? prev : nextH));
      });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => {
      cancelAnimationFrame(rafId);
      ro.disconnect();
    };
  }, [hasMessages]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const raf = requestAnimationFrame(() => {
      el.scrollTop = el.scrollHeight;
    });
    return () => cancelAnimationFrame(raf);
  }, [messages]);

  const insertBotMention = useCallback((label: string) => {
    const clean = label.replace(/^@+/, "").trim();
    if (!clean) return;
    promptBarRef.current?.setDraft(`@${clean} `);
    promptBarRef.current?.focus();
  }, []);

  const chief = participants.find((p) => p.id === "butler");
  const specialists = participants.filter((p) => p.id !== "butler");

  const statusLabel = (status: MeetingRoomParticipant["status"]) => {
    if (status === "speaking") return locale === "zh" ? "发言中" : "Speaking";
    if (status === "updated") return locale === "zh" ? "已更新" : "Updated";
    if (status === "done") return locale === "zh" ? "已汇报" : "Done";
    return "";
  };

  return (
    <div className="flex min-h-0 flex-1 overflow-hidden">
      {/* Main isolated Meeting Feed */}
      <div className="relative flex min-w-0 flex-1 flex-col overflow-hidden">
        {!hasMessages ? (
          <div className="bui-scroll flex min-h-0 flex-1 flex-col justify-center overflow-y-auto px-5 py-6">
            <div className="mx-auto flex w-full max-w-[620px] flex-col gap-5">
              <h1 className="text-[21px] font-semibold tracking-[-0.02em] text-ink">
                {locale === "zh" ? "复盘会议室" : "Meeting Room"}
              </h1>

              <PromptBar
                ref={promptBarRef}
                tall
                placeholder={
                  locale === "zh"
                    ? "输入议题，或 @ 指定 Bot"
                    : "Ask all bots or @mention one"
                }
                locale={locale}
                isStreaming={isConvening}
                availableModels={availableModels}
                selectedModelID={selectedModelID}
                selectedModelTitle={selectedModelTitle}
                contextSources={[]}
                slashCommands={[]}
                availableDocuments={[]}
                availableBots={mentionBots}
                showEffort={false}
                onSelectModel={onSelectModel}
                onSelectEffort={() => {}}
                onOpenSettings={onOpenSettings}
                onSend={(text, _docs, botId) => onSend(text, botId)}
                onAbort={onAbort}
              />
            </div>
          </div>
        ) : (
          <>
            <div ref={scrollRef} className="bui-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain">
              <div
                className="mx-auto flex w-full max-w-[660px] flex-col gap-4 px-4 pt-5"
                style={{ paddingBottom: composerH + 24 }}
              >
                {messages.map((msg) =>
                  msg.role === "user" ? (
                    <div key={msg.id} className="flex justify-end pl-10">
                      <div className="max-w-[92%] select-text whitespace-pre-wrap break-words rounded-[13px] bg-field px-3.5 py-2.5 text-[14px] leading-relaxed text-ink shadow-hairline">
                        {msg.text}
                      </div>
                    </div>
                  ) : (
                    <BotSpeakerTurn
                      key={msg.id}
                      message={msg}
                      locale={locale}
                    />
                  ),
                )}
              </div>
            </div>

            <div
              className="pointer-events-none absolute inset-x-0 bottom-0"
              style={{
                height: composerH + 26,
                background: "linear-gradient(to top, var(--page) 68%, transparent)",
              }}
            />

            <div ref={composerRef} className="absolute inset-x-0 bottom-0 px-3.5 pb-3.5">
              <div className="mx-auto max-w-[660px]">
                <PromptBar
                  ref={promptBarRef}
                  placeholder={
                    locale === "zh"
                      ? "输入议题，或 @总管 统筹调度"
                      : "Follow up or @Butler to sync"
                  }
                  locale={locale}
                  isStreaming={isConvening}
                  availableModels={availableModels}
                  selectedModelID={selectedModelID}
                  selectedModelTitle={selectedModelTitle}
                  contextSources={[]}
                  slashCommands={[]}
                  availableDocuments={[]}
                  availableBots={mentionBots}
                  showEffort={false}
                  onSelectModel={onSelectModel}
                  onSelectEffort={() => {}}
                  onOpenSettings={onOpenSettings}
                  onSend={(text, _docs, botId) => onSend(text, botId)}
                  onAbort={onAbort}
                />
              </div>
            </div>
          </>
        )}
      </div>

      {/* Right-side Meeting Room Participant Section Rail */}
      <aside className="hidden w-[196px] shrink-0 flex-col border-l border-line bg-canvas/70 md:flex">
        <div className="flex h-10 shrink-0 items-center justify-between border-b border-line px-3">
          <span className="text-[12.5px] font-semibold text-ink-2">
            {locale === "zh" ? "参会席位" : "Participants"}
          </span>
          <span className="text-[12px] text-ink-3 tabular-nums">{participants.length}</span>
        </div>

        <div className="bui-scroll flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto p-2">
          {chief && (
            <>
              <button
                type="button"
                onClick={() => insertBotMention(chief.nickname || chief.name)}
                className="group flex items-center gap-2 rounded-[8px] bg-surface px-2.5 py-2 text-left shadow-hairline transition-colors hover:bg-hover-2"
              >
                <span
                  className="size-2 shrink-0 rounded-full"
                  style={{ backgroundColor: chief.accentHex }}
                />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[13px] font-semibold text-ink">{chief.name}</div>
                  <div className="truncate text-[12px] text-ink-3">
                    {statusLabel(chief.status) || chief.roleLabel}
                  </div>
                </div>
              </button>
              <div className="my-1 h-px bg-line" />
            </>
          )}

          {specialists.map((bot) => {
            const st = statusLabel(bot.status);
            return (
              <button
                key={bot.id}
                type="button"
                onClick={() => insertBotMention(bot.nickname || bot.name)}
                className="group flex items-center gap-2 rounded-[8px] px-2 py-1.5 text-left transition-colors hover:bg-hover-2"
              >
                <span
                  className={`size-2 shrink-0 rounded-full ${
                    bot.status === "speaking" ? "animate-pulse" : ""
                  }`}
                  style={{ backgroundColor: bot.accentHex }}
                />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[13px] font-medium text-ink">{bot.name}</div>
                  <div className="truncate text-[12px] text-ink-3 tabular-nums">
                    {st || bot.todayBadge || bot.roleLabel}
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      </aside>
    </div>
  );
});

export default MeetingRoomView;
