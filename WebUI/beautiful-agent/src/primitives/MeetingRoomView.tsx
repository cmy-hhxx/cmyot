import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { copyTextWithFallback } from "../bridge";
import MarkdownProse from "./MarkdownProse";
import MeetingMembersDrawer from "./MeetingMembersDrawer";
import { renderTextWithMentions } from "./MentionText";
import PromptBar, { type PromptBarHandle } from "./PromptBar";
import type {
  BotMentionItem,
  MeetingRoomMessage,
  MeetingRoomParticipant,
  ModelOption,
  StickerItem,
} from "../types";

type MeetingRoomViewProps = {
  locale: "zh" | "en";
  messages: MeetingRoomMessage[];
  participants: MeetingRoomParticipant[];
  isConvening: boolean;
  availableModels: ModelOption[];
  selectedModelID: string;
  selectedModelTitle: string;
  stickers?: StickerItem[];
  userAvatarURL?: string | null;
  membersDrawerOpen: boolean;
  onCloseMembersDrawer: () => void;
  onSend: (text: string, botId?: string | null, stickerId?: string | null) => void;
  onAbort: () => void;
  onSelectModel: (model: ModelOption) => void;
  onOpenSettings: () => void;
  onOpenBotConfig: (botId: string) => void;
  onToggleParticipant?: (botId: string) => void;
  onOpenCreateBot?: () => void;
  onUploadSticker?: () => void;
  onRefreshStickers?: () => void;
  onToggleFavoriteSticker?: (id: string) => void;
  onSearchOnlineStickers?: (query: string) => void;
};

const AvatarTile = memo(function AvatarTile({
  url,
  name,
  accentHex,
  title,
  onClick,
}: {
  url?: string | null;
  name: string;
  accentHex?: string | null;
  title?: string;
  onClick?: () => void;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setFailed(false);
  }, [url]);
  const bg = accentHex || "var(--accent)";
  const content =
    url && !failed ? (
      <img
        src={url}
        alt={name}
        onError={() => setFailed(true)}
        className="size-full object-cover"
      />
    ) : (
      <span className="text-[13.5px] font-semibold">{name.slice(0, 1)}</span>
    );

  const baseClass =
    "flex size-[36px] shrink-0 items-center justify-center overflow-hidden rounded-[8px] border border-line bg-surface shadow-hairline";

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        title={title}
        className={`${baseClass} cursor-pointer transition-opacity hover:border-line-strong hover:opacity-90`}
        style={!url || failed ? { backgroundColor: `${bg}20`, color: bg } : undefined}
      >
        {content}
      </button>
    );
  }

  return (
    <div
      className={baseClass}
      style={!url || failed ? { backgroundColor: `${bg}20`, color: bg } : undefined}
    >
      {content}
    </div>
  );
});

const StickerAttachmentBlock = memo(function StickerAttachmentBlock({
  url,
  caption,
  stickerID,
  isFavorite,
  alignRight,
  onPreview,
  onToggleFavorite,
}: {
  url: string;
  caption?: string | null;
  stickerID?: string | null;
  isFavorite?: boolean;
  alignRight?: boolean;
  onPreview: (url: string, caption?: string | null) => void;
  onToggleFavorite?: (id: string) => void;
}) {
  return (
    <div className={`group/stk relative inline-flex ${alignRight ? "justify-end" : "justify-start"}`}>
      <button
        type="button"
        onClick={() => onPreview(url, caption)}
        className="overflow-hidden rounded-[10px] transition-opacity hover:opacity-95"
      >
        <img
          src={url}
          alt={caption || "Sticker"}
          className="max-h-[144px] max-w-[144px] rounded-[10px] object-contain"
        />
      </button>
      {stickerID && onToggleFavorite && (
        <button
          type="button"
          aria-label="Favorite sticker"
          onClick={() => onToggleFavorite(stickerID)}
          className={`absolute top-1.5 right-1.5 flex size-6 items-center justify-center rounded-full border border-line bg-surface/95 text-[12px] shadow-hairline transition-opacity ${
            isFavorite ? "opacity-100 text-orange" : "opacity-0 text-ink-3 group-hover/stk:opacity-100 hover:text-ink"
          }`}
        >
          {isFavorite ? "★" : "☆"}
        </button>
      )}
    </div>
  );
});

const ChatMessageBubbleRow = memo(function ChatMessageBubbleRow({
  message,
  locale,
  userAvatarURL,
  favoriteStickerIDs,
  onOpenBotConfig,
  onPreviewSticker,
  onToggleFavoriteSticker,
}: {
  message: MeetingRoomMessage;
  locale: "zh" | "en";
  userAvatarURL?: string | null;
  favoriteStickerIDs: Set<string>;
  onOpenBotConfig: (botId: string) => void;
  onPreviewSticker: (url: string, caption?: string | null) => void;
  onToggleFavoriteSticker?: (id: string) => void;
}) {
  const [copied, setCopied] = useState(false);
  const isUser = message.role === "user";
  const isSpeaking = message.status === "speaking";
  const hasText = message.text.trim().length > 0;
  const hasSticker = Boolean(message.stickerURL);
  const displayName = isUser ? (locale === "zh" ? "我" : "Me") : (message.botName || message.botID || "Bot");
  const configTitle = isUser
    ? locale === "zh"
      ? "配置个人头像与名称"
      : "Configure profile"
    : locale === "zh"
      ? `配置 ${displayName}`
      : `Configure ${displayName}`;

  const handleCopy = () => {
    copyTextWithFallback(message.text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };

  if (isUser) {
    return (
      <div className="flex flex-col gap-2.5">
        {hasText && (
          <div className="flex items-start justify-end gap-2.5 pl-10">
            <div className="max-w-[78%] select-text whitespace-pre-wrap break-words rounded-[12px] rounded-tr-[4px] bg-accent px-3.5 py-2 text-[14px] leading-relaxed text-white shadow-hairline">
              {renderTextWithMentions(message.text, "accent")}
            </div>
            <AvatarTile
              url={userAvatarURL}
              name={displayName}
              accentHex="#3B82F6"
              title={configTitle}
              onClick={() => onOpenBotConfig("user")}
            />
          </div>
        )}
        {hasSticker && message.stickerURL && (
          <div className="flex items-start justify-end gap-2.5 pl-10">
            <StickerAttachmentBlock
              url={message.stickerURL}
              caption={message.stickerCaption}
              stickerID={message.stickerID}
              isFavorite={message.stickerID ? favoriteStickerIDs.has(message.stickerID) : false}
              alignRight
              onPreview={onPreviewSticker}
              onToggleFavorite={onToggleFavoriteSticker}
            />
            <AvatarTile
              url={userAvatarURL}
              name={displayName}
              accentHex="#3B82F6"
              title={configTitle}
              onClick={() => onOpenBotConfig("user")}
            />
          </div>
        )}
      </div>
    );
  }

  const avatarAction = message.botID ? () => onOpenBotConfig(message.botID as string) : undefined;
  const showPrimaryRow = hasText;
  if (!hasText && !hasSticker) {
    return null;
  }

  return (
    <div className="flex flex-col gap-2.5">
      {showPrimaryRow && (
        <div className="group/msg flex items-start gap-2.5 pr-6">
          <AvatarTile
            url={message.botAvatarURL}
            name={displayName}
            accentHex={message.botAccentHex}
            title={configTitle}
            onClick={avatarAction}
          />

          <div className="flex min-w-0 max-w-[78%] flex-col items-start gap-1">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-[12.5px] font-semibold text-ink-2">{displayName}</span>
              {message.delegatedFromButler && (
                <span className="rounded-[5px] bg-accent-tint px-1.5 py-0.5 text-[12px] text-accent-ink">
                  {locale === "zh" ? "总管调度" : "Dispatched"}
                </span>
              )}
              {!isSpeaking && hasText && (
                <button
                  type="button"
                  onClick={handleCopy}
                  className="rounded-[5px] px-1.5 py-0.5 text-[12px] text-ink-3 opacity-0 transition-opacity group-hover/msg:opacity-100 hover:bg-hover hover:text-ink"
                >
                  {copied ? (locale === "zh" ? "已复制" : "Copied") : locale === "zh" ? "复制" : "Copy"}
                </button>
              )}
            </div>

            {message.receipts && message.receipts.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
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

            <div className="w-fit max-w-full rounded-[12px] rounded-tl-[4px] border border-line bg-surface px-3.5 py-2 shadow-hairline">
              <MarkdownProse markdown={message.text} isStreaming={isSpeaking} locale={locale} />
            </div>
          </div>
        </div>
      )}

      {hasSticker && message.stickerURL && (
        <div className="flex items-start gap-2.5 pr-6">
          <AvatarTile
            url={message.botAvatarURL}
            name={displayName}
            accentHex={message.botAccentHex}
            title={configTitle}
            onClick={avatarAction}
          />

          <div className="flex min-w-0 max-w-[78%] flex-col items-start gap-1">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-[12.5px] font-semibold text-ink-2">{displayName}</span>
            </div>
            <StickerAttachmentBlock
              url={message.stickerURL}
              caption={message.stickerCaption}
              stickerID={message.stickerID}
              isFavorite={message.stickerID ? favoriteStickerIDs.has(message.stickerID) : false}
              onPreview={onPreviewSticker}
              onToggleFavorite={onToggleFavoriteSticker}
            />
          </div>
        </div>
      )}
    </div>
  );
});

const MeetingTypingBubble = memo(function MeetingTypingBubble({
  speakingBots,
}: {
  speakingBots: MeetingRoomParticipant[];
}) {
  return (
    <div className="flex items-center justify-start" style={{ animation: "fade-in 160ms ease-out both" }}>
      <div className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1.5 shadow-hairline">
        {speakingBots.length > 0 && (
          <div className="flex items-center gap-1.5">
            {speakingBots.slice(0, 3).map((bot) => (
              <span key={bot.id} className="inline-flex items-center gap-1">
                {bot.avatarURL ? (
                  <img
                    src={bot.avatarURL}
                    alt={bot.name}
                    className="size-[18px] shrink-0 rounded-[5px] border border-line object-cover"
                  />
                ) : (
                  <span
                    className="flex size-[18px] shrink-0 items-center justify-center rounded-[5px] text-[10px] font-semibold"
                    style={{
                      backgroundColor: `${bot.accentHex || "var(--accent)"}20`,
                      color: bot.accentHex || "var(--accent)",
                    }}
                  >
                    {bot.name.slice(0, 1)}
                  </span>
                )}
                <span className="text-[12px] font-medium text-ink-2">{bot.name}</span>
              </span>
            ))}
          </div>
        )}
        <span aria-hidden className="flex items-center gap-1">
          {[0, 160, 320].map((delay) => (
            <span
              key={delay}
              className="size-[5px] rounded-full bg-ink-3"
              style={{ animation: `pixel-on 900ms ease-in-out ${delay}ms infinite` }}
            />
          ))}
        </span>
      </div>
    </div>
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
  stickers = [],
  userAvatarURL,
  membersDrawerOpen,
  onCloseMembersDrawer,
  onSend,
  onAbort,
  onSelectModel,
  onOpenSettings,
  onOpenBotConfig,
  onToggleParticipant,
  onOpenCreateBot,
  onUploadSticker,
  onRefreshStickers,
  onToggleFavoriteSticker,
  onSearchOnlineStickers,
}: MeetingRoomViewProps) {
  const promptBarRef = useRef<PromptBarHandle>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const composerRef = useRef<HTMLDivElement>(null);
  const [composerH, setComposerH] = useState(112);
  const [previewSticker, setPreviewSticker] = useState<{ url: string; caption?: string | null } | null>(null);

  const hasMessages = messages.length > 0;
  const hasActiveTextStream = useMemo(
    () => messages.some((m) => m.role === "bot" && m.status === "speaking" && m.text.trim().length > 0),
    [messages],
  );
  const activeSpeakingBots = useMemo(
    () => participants.filter((p) => p.status === "speaking"),
    [participants],
  );
  const showTypingBubble = isConvening && !hasActiveTextStream;
  const favoriteStickerIDs = useMemo(
    () => new Set(stickers.filter((s) => s.isFavorite).map((s) => s.id)),
    [stickers],
  );

  const mentionBots = useMemo<BotMentionItem[]>(() => {
    const ordered = participants.slice().sort((a, b) => Number(Boolean(b.isCustom)) - Number(Boolean(a.isCustom)));
    return ordered.map((p) => ({
      id: p.id,
      name: p.name,
      nickname: p.nickname,
      handle: p.handle,
      tagline: p.roleLabel,
      accentHex: p.accentHex,
      avatarURL: p.avatarURL,
      isCustom: p.isCustom,
    }));
  }, [participants]);

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

  return (
    <div className="relative flex min-h-0 flex-1 overflow-hidden">
      {/* Main Group Chat Feed (full-width WeChat / Teams proportions) */}
      <div className="relative flex min-w-0 flex-1 flex-col overflow-hidden">
        {!hasMessages ? (
          <div className="bui-scroll flex min-h-0 flex-1 flex-col justify-center overflow-y-auto px-5 py-6">
            <div className="mx-auto flex w-full max-w-[660px] flex-col gap-5">
              <h1 className="text-[21px] font-semibold tracking-[-0.02em] text-ink">
                {locale === "zh" ? "会议室" : "Meeting Room"}
              </h1>

              <PromptBar
                ref={promptBarRef}
                tall
                inlineBotMentions
                placeholder={locale === "zh" ? "输入议题或 @ 指定 Bots" : "Ask all bots or @mention one"}
                locale={locale}
                isStreaming={isConvening}
                availableModels={availableModels}
                selectedModelID={selectedModelID}
                selectedModelTitle={selectedModelTitle}
                contextSources={[]}
                slashCommands={[]}
                availableDocuments={[]}
                availableBots={mentionBots}
                stickers={stickers}
                showEffort={false}
                onSelectModel={onSelectModel}
                onSelectEffort={() => {}}
                onOpenSettings={onOpenSettings}
                onUploadSticker={onUploadSticker}
                onRefreshStickers={onRefreshStickers}
                onToggleFavoriteSticker={onToggleFavoriteSticker}
                onSearchOnlineStickers={onSearchOnlineStickers}
                onSend={(text, _docs, botId, stickerId) => onSend(text, botId, stickerId)}
                onAbort={onAbort}
              />
            </div>
          </div>
        ) : (
          <>
            <div ref={scrollRef} className="bui-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain">
              <div
                className="mx-auto flex w-full max-w-[760px] flex-col gap-4 px-4 pt-5"
                style={{ paddingBottom: composerH + 24 }}
              >
                {messages.map((msg) => (
                  <ChatMessageBubbleRow
                    key={msg.id}
                    message={msg}
                    locale={locale}
                    userAvatarURL={userAvatarURL}
                    favoriteStickerIDs={favoriteStickerIDs}
                    onOpenBotConfig={onOpenBotConfig}
                    onPreviewSticker={(url, caption) => setPreviewSticker({ url, caption })}
                    onToggleFavoriteSticker={onToggleFavoriteSticker}
                  />
                ))}
                {showTypingBubble && <MeetingTypingBubble speakingBots={activeSpeakingBots} />}
              </div>
            </div>

            <div
              className="pointer-events-none absolute inset-x-0 bottom-0"
              style={{ height: composerH + 26, background: "linear-gradient(to top, var(--page) 68%, transparent)" }}
            />

            <div ref={composerRef} className="absolute inset-x-0 bottom-0 px-3.5 pb-3.5">
              <div className="mx-auto max-w-[760px]">
                <PromptBar
                  ref={promptBarRef}
                  inlineBotMentions
                  placeholder={locale === "zh" ? "发言，或 @ 指定成员" : "Reply or @mention"}
                  locale={locale}
                  isStreaming={isConvening}
                  availableModels={availableModels}
                  selectedModelID={selectedModelID}
                  selectedModelTitle={selectedModelTitle}
                  contextSources={[]}
                  slashCommands={[]}
                  availableDocuments={[]}
                  availableBots={mentionBots}
                  stickers={stickers}
                  showEffort={false}
                  onSelectModel={onSelectModel}
                  onSelectEffort={() => {}}
                  onOpenSettings={onOpenSettings}
                  onUploadSticker={onUploadSticker}
                  onRefreshStickers={onRefreshStickers}
                  onToggleFavoriteSticker={onToggleFavoriteSticker}
                  onSearchOnlineStickers={onSearchOnlineStickers}
                  onSend={(text, _docs, botId, stickerId) => onSend(text, botId, stickerId)}
                  onAbort={onAbort}
                />
              </div>
            </div>
          </>
        )}
      </div>

      {/* Dismissible WeChat/Teams-style Members Drawer */}
      <MeetingMembersDrawer
        open={membersDrawerOpen}
        locale={locale}
        participants={participants}
        onClose={onCloseMembersDrawer}
        onMentionBot={insertBotMention}
        onOpenBotConfig={onOpenBotConfig}
        onToggleParticipant={onToggleParticipant}
        onOpenCreateBot={onOpenCreateBot}
      />

      {/* Lightbox preview */}
      {previewSticker && (
        <div
          onClick={() => setPreviewSticker(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-6"
        >
          <div className="flex max-w-[360px] flex-col items-center gap-2 rounded-[14px] bg-surface p-3 shadow-overlay">
            <img src={previewSticker.url} alt={previewSticker.caption || "Sticker"} className="max-h-[300px] max-w-[320px] rounded-[10px] object-contain" />
            {previewSticker.caption && (
              <span className="text-[12.5px] text-ink-2">{previewSticker.caption}</span>
            )}
          </div>
        </div>
      )}
    </div>
  );
});

export default MeetingRoomView;
