import { memo, useEffect, useMemo, useRef, useState } from "react";
import type { MeetingRoomParticipant } from "../types";

type MeetingMembersDrawerProps = {
  open: boolean;
  locale: "zh" | "en";
  participants: MeetingRoomParticipant[];
  isOwner?: boolean;
  onClose: () => void;
  onMentionBot: (label: string) => void;
  onOpenBotConfig: (botId: string) => void;
  onToggleParticipant?: (botId: string) => void;
  onOpenCreateBot?: () => void;
  onDissolveSession?: () => void;
};

const DrawerAvatar = memo(function DrawerAvatar({
  url,
  name,
  accentHex,
}: {
  url?: string | null;
  name: string;
  accentHex?: string | null;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setFailed(false);
  }, [url]);
  const bg = accentHex || "var(--accent)";
  return (
    <span
      className="flex size-[34px] shrink-0 items-center justify-center overflow-hidden rounded-[8px] border border-line bg-surface"
      style={!url || failed ? { backgroundColor: `${bg}20`, color: bg } : undefined}
    >
      {url && !failed ? (
        <img
          src={url}
          alt={name}
          onError={() => setFailed(true)}
          className="size-full object-cover"
        />
      ) : (
        <span className="text-[13.5px] font-semibold">{name.slice(0, 1)}</span>
      )}
    </span>
  );
});

const MeetingMembersDrawer = memo(function MeetingMembersDrawer({
  open,
  locale,
  participants,
  isOwner = true,
  onClose,
  onMentionBot,
  onOpenBotConfig,
  onToggleParticipant,
  onOpenCreateBot,
  onDissolveSession,
}: MeetingMembersDrawerProps) {
  const [query, setQuery] = useState("");
  const [confirmDissolve, setConfirmDissolve] = useState(false);
  const drawerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) {
      setQuery("");
      setConfirmDissolve(false);
      return;
    }
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.closest("[data-members-toggle]")) return;
      if (drawerRef.current && !drawerRef.current.contains(target)) {
        onClose();
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open, onClose]);

  const activeCount = useMemo(
    () => participants.filter((p) => p.isSelected !== false).length,
    [participants],
  );

  const visible = useMemo(() => {
    const clean = query.trim().toLowerCase();
    if (!clean) return participants;
    return participants.filter(
      (bot) =>
        bot.name.toLowerCase().includes(clean) ||
        bot.nickname.toLowerCase().includes(clean) ||
        bot.roleLabel.toLowerCase().includes(clean),
    );
  }, [participants, query]);

  if (!open) return null;

  return (
    <div
      ref={drawerRef}
      className="absolute top-2 right-3 z-30 flex max-h-[calc(100%-24px)] w-[276px] flex-col overflow-hidden rounded-[12px] border border-line bg-surface shadow-raised"
      style={{ animation: "pop-in 150ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "top right" }}
    >
      <div className="flex h-10 shrink-0 items-center justify-between border-b border-line px-3">
        <div className="flex items-center gap-1.5">
          <span className="text-[13px] font-semibold text-ink">
            {locale === "zh" ? "群成员" : "Members"}
          </span>
          <span className="rounded-full bg-inset px-1.5 py-0.5 text-[12px] font-medium text-ink-3 tabular-nums">
            {activeCount}
          </span>
          {isOwner && (
            <span className="rounded-[5px] bg-inset px-1.5 py-0.5 text-[10.5px] font-medium text-ink-3">
              {locale === "zh" ? "群主：我" : "Owner"}
            </span>
          )}
        </div>
        <button
          type="button"
          aria-label="Close members"
          onClick={onClose}
          className="flex size-6 items-center justify-center rounded-[6px] text-ink-3 transition-colors hover:bg-hover hover:text-ink"
        >
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>
      </div>

      {participants.length > 6 && (
        <div className="border-b border-line px-2.5 py-2">
          <div className="flex h-7.5 items-center gap-1.5 rounded-[7px] bg-inset px-2">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-ink-3">
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.3-4.3" />
            </svg>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={locale === "zh" ? "搜索" : "Search"}
              className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3 select-text"
            />
          </div>
        </div>
      )}

      <div className="bui-scroll flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto p-1.5">
        {visible.map((bot) => {
          const isSelected = bot.isSelected !== false;
          return (
            <div
              key={bot.id}
              className={`group flex items-center gap-2 rounded-[8px] px-2 py-1.5 transition-colors hover:bg-hover-2 ${
                isSelected ? "" : "opacity-55"
              }`}
            >
              <button
                type="button"
                onClick={() => onOpenBotConfig(bot.id)}
                title={locale === "zh" ? `配置 ${bot.name}` : `Configure ${bot.name}`}
                className="shrink-0 cursor-pointer rounded-[8px] transition-opacity hover:opacity-85"
              >
                <DrawerAvatar url={bot.avatarURL} name={bot.name} accentHex={bot.accentHex} />
              </button>

              <button
                type="button"
                onClick={() => {
                  onMentionBot(bot.nickname || bot.name);
                  onClose();
                }}
                className="min-w-0 flex-1 text-left"
              >
                <div className="flex items-center gap-1.5">
                  <span className="truncate text-[13px] font-medium text-ink">{bot.name}</span>
                  {(bot.status === "thinking" || bot.status === "speaking") && (
                    <span
                      className="size-1.5 shrink-0 rounded-full"
                      style={{
                        backgroundColor: bot.accentHex || "var(--accent)",
                        animation: "pixel-on 900ms ease-in-out infinite",
                      }}
                    />
                  )}
                </div>
                {bot.roleLabel && (
                  <div className="truncate text-[12px] text-ink-3">
                    {bot.roleLabel}
                  </div>
                )}
              </button>

              <button
                type="button"
                aria-label={locale === "zh" ? `配置 ${bot.name}` : `Configure ${bot.name}`}
                onClick={() => onOpenBotConfig(bot.id)}
                title={locale === "zh" ? "配置头像与名称" : "Configure Bot"}
                className="flex size-6 shrink-0 items-center justify-center rounded-[6px] text-ink-3 opacity-0 transition-opacity group-hover:opacity-100 hover:bg-hover hover:text-ink"
              >
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="3" />
                  <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
                </svg>
              </button>

              {onToggleParticipant && bot.id !== "butler" && (
                <input
                  type="checkbox"
                  checked={isSelected}
                  onChange={() => onToggleParticipant(bot.id)}
                  className="size-3.5 shrink-0 accent-accent"
                  aria-label={bot.name}
                />
              )}
            </div>
          );
        })}
      </div>

      {(onOpenCreateBot || onDissolveSession) && (
        <div className="flex flex-col gap-1.5 border-t border-line p-2">
          {onOpenCreateBot && (
            <button
              type="button"
              onClick={() => {
                onClose();
                onOpenCreateBot();
              }}
              className="flex h-8 w-full items-center justify-center gap-1 rounded-[8px] bg-inset text-[12.5px] font-medium text-ink transition-colors hover:bg-hover-2"
            >
              <span>+ {locale === "zh" ? "新建 Bot" : "New Bot"}</span>
            </button>
          )}
          {onDissolveSession && (
            confirmDissolve ? (
              <button
                type="button"
                onClick={() => {
                  setConfirmDissolve(false);
                  onClose();
                  onDissolveSession();
                }}
                onMouseLeave={() => setConfirmDissolve(false)}
                className="flex h-8 w-full items-center justify-center rounded-[8px] bg-red text-[12.5px] font-medium text-white transition-opacity hover:opacity-90"
              >
                {locale === "zh" ? "确认解散此群聊" : "Confirm Dissolve"}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => setConfirmDissolve(true)}
                className="flex h-8 w-full items-center justify-center rounded-[8px] text-[12.5px] font-medium text-red transition-colors hover:bg-red-tint"
              >
                {locale === "zh" ? "解散群聊" : "Dissolve Group"}
              </button>
            )
          )}
        </div>
      )}
    </div>
  );
});

export default MeetingMembersDrawer;
