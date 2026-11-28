import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import GlideMenu from "./GlideMenu";
import type { ContactSummary, MeetingRoomSessionSummary } from "../types";

const COLLAPSED_GROUPS_STORAGE_KEY = "cot.sidebar.collapsedGroups.v1";
const ACTIVE_TAB_STORAGE_KEY = "cot.sidebar.activeTab.v1";

type SidebarTab = "messages" | "contacts";

function loadCollapsedGroups(): Record<string, boolean> {
  try {
    const raw = window.localStorage.getItem(COLLAPSED_GROUPS_STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function saveCollapsedGroups(next: Record<string, boolean>) {
  try {
    window.localStorage.setItem(COLLAPSED_GROUPS_STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Ignore storage quota errors
  }
}

function loadActiveTab(): SidebarTab {
  try {
    return window.localStorage.getItem(ACTIVE_TAB_STORAGE_KEY) === "contacts" ? "contacts" : "messages";
  } catch {
    return "messages";
  }
}

function saveActiveTab(tab: SidebarTab) {
  try {
    window.localStorage.setItem(ACTIVE_TAB_STORAGE_KEY, tab);
  } catch {
    // Ignore storage quota errors
  }
}

function formatRelativeTime(timestampMs?: number | null, locale: "zh" | "en" = "zh"): string {
  if (!timestampMs || timestampMs <= 0) return "";
  const diffMin = Math.max(0, Math.floor((Date.now() - timestampMs) / 60_000));
  if (diffMin < 1) return locale === "zh" ? "刚刚" : "now";
  if (diffMin < 60) return `${diffMin}m`;
  const diffHour = Math.floor(diffMin / 60);
  if (diffHour < 24) return `${diffHour}h`;
  const diffDay = Math.floor(diffHour / 24);
  if (diffDay < 7) return `${diffDay}d`;
  const d = new Date(timestampMs);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

function ContactAvatar({
  name,
  avatarURL,
  accentHex,
  sizeClass = "size-7",
  roundedClass = "rounded-[7px]",
}: {
  name: string;
  avatarURL?: string | null;
  accentHex?: string;
  sizeClass?: string;
  roundedClass?: string;
}) {
  const [imgFailed, setImgFailed] = useState(false);
  useEffect(() => {
    setImgFailed(false);
  }, [avatarURL]);

  return (
    <span
      className={`relative flex ${sizeClass} shrink-0 items-center justify-center overflow-hidden ${roundedClass} bg-surface shadow-hairline`}
      style={!avatarURL || imgFailed ? { backgroundColor: `${accentHex || "#6B7280"}1f`, color: accentHex || "var(--ink)" } : undefined}
    >
      {avatarURL && !imgFailed ? (
        <img
          src={avatarURL}
          alt={name}
          onError={() => setImgFailed(true)}
          className="size-full object-cover"
        />
      ) : (
        <span className="text-[12px] font-semibold">{name.slice(0, 1) || "B"}</span>
      )}
    </span>
  );
}

type UnifiedMessageItem =
  | {
      kind: "dm";
      id: string;
      botID: string;
      name: string;
      preview: string;
      avatarURL?: string | null;
      accentHex: string;
      unreadCount: number;
      updatedAt: number;
      isPinned: boolean;
    }
  | {
      kind: "group";
      id: string;
      sessionID: string;
      name: string;
      preview: string;
      participantCount: number;
      updatedAt: number;
      isPinned: boolean;
    };

export type IMSidebarProps = {
  contacts: ContactSummary[];
  activeBotID: string;
  totalUnread: number;
  collapsed: boolean;
  locale: "zh" | "en";
  meetingRoomActive?: boolean;
  meetingRoomIsConvening?: boolean;
  meetingRoomSessions?: MeetingRoomSessionSummary[];
  activeMeetingSessionID?: string;
  onToggleCollapse: () => void;
  onOpenDirectChat: (botID: string) => void;
  onNewGroup: () => void;
  onSelectMeetingSession: (id: string) => void;
  onOpenCreateBotSheet?: () => void;
  onOpenSettings: () => void;
};

const IMSidebar = memo(function IMSidebar({
  contacts,
  activeBotID,
  totalUnread,
  collapsed,
  locale,
  meetingRoomActive = false,
  meetingRoomIsConvening = false,
  meetingRoomSessions = [],
  activeMeetingSessionID = "",
  onToggleCollapse,
  onOpenDirectChat,
  onNewGroup,
  onSelectMeetingSession,
  onOpenCreateBotSheet,
  onOpenSettings,
}: IMSidebarProps) {
  const [activeTab, setActiveTab] = useState<SidebarTab>(() => loadActiveTab());
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [collapsedGroupMap, setCollapsedGroupMap] = useState<Record<string, boolean>>(() => loadCollapsedGroups());
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);

  useEffect(() => {
    if (collapsed && searchOpen) {
      setSearchOpen(false);
      setQuery("");
    }
  }, [collapsed, searchOpen]);

  const switchTab = useCallback((next: SidebarTab) => {
    setActiveTab(next);
    saveActiveTab(next);
  }, []);

  const toggleGroupCollapsed = useCallback((groupKey: string) => {
    setCollapsedGroupMap((prev) => {
      const next = { ...prev, [groupKey]: !prev[groupKey] };
      saveCollapsedGroups(next);
      return next;
    });
  }, []);

  const cleanQuery = query.trim().toLowerCase();

  const messageItems = useMemo<UnifiedMessageItem[]>(() => {
    const dmItems: UnifiedMessageItem[] = contacts
      .filter((c) => Boolean(c.sessionID))
      .map((c) => ({
        kind: "dm" as const,
        id: `dm:${c.id}`,
        botID: c.id,
        name: c.name,
        preview: c.lastMessagePreview || c.tagline || "",
        avatarURL: c.avatarURL,
        accentHex: c.accentHex,
        unreadCount: c.unreadCount,
        updatedAt: c.updatedAt ?? 0,
        isPinned: c.isPinned,
      }));

    const groupItems: UnifiedMessageItem[] = meetingRoomSessions.map((g) => ({
      kind: "group" as const,
      id: `grp:${g.id}`,
      sessionID: g.id,
      name: g.title,
      preview: locale === "zh" ? `${g.participantIDs.length} 位群成员` : `${g.participantIDs.length} members`,
      participantCount: g.participantIDs.length,
      updatedAt: g.updatedAt ?? 0,
      isPinned: g.isPinned,
    }));

    const merged = [...dmItems, ...groupItems].sort((a, b) => {
      if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt - a.updatedAt;
    });

    if (!cleanQuery) return merged;
    return merged.filter(
      (item) => item.name.toLowerCase().includes(cleanQuery) || item.preview.toLowerCase().includes(cleanQuery),
    );
  }, [contacts, meetingRoomSessions, cleanQuery, locale]);

  const contactBuckets = useMemo(() => {
    const filtered = !cleanQuery
      ? contacts
      : contacts.filter(
          (c) =>
            c.name.toLowerCase().includes(cleanQuery) ||
            c.nickname.toLowerCase().includes(cleanQuery) ||
            c.handle.toLowerCase().includes(cleanQuery),
        );
    return {
      butler: filtered.filter((c) => c.isButler),
      builtIn: filtered.filter((c) => !c.isButler && !c.isCustom),
      custom: filtered.filter((c) => c.isCustom),
    };
  }, [contacts, cleanQuery]);

  const railContacts = useMemo(() => {
    const withUnreadOrButler = [...contacts].sort((a, b) => {
      if ((a.unreadCount > 0) !== (b.unreadCount > 0)) return a.unreadCount > 0 ? -1 : 1;
      if (a.isButler !== b.isButler) return a.isButler ? -1 : 1;
      return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
    });
    return withUnreadOrButler.slice(0, 7);
  }, [contacts]);

  return (
    <aside
      data-sidebar-collapsed={collapsed}
      aria-label="Sessions navigation"
      className="relative flex h-full shrink-0 overflow-hidden border-r border-line bg-canvas transition-[width]"
      style={{
        width: collapsed ? 50 : 232,
        transitionDuration: "220ms",
        transitionTimingFunction: "cubic-bezier(0.32, 0.72, 0, 1)",
        willChange: "width",
      }}
    >
      {/* Collapsed rail quick contacts */}
      {collapsed && (
        <div className="absolute inset-0 z-10 flex flex-col items-center py-2">
          <button
            type="button"
            onClick={onToggleCollapse}
            title={locale === "zh" ? "展开侧栏" : "Expand sidebar"}
            className="flex size-8 items-center justify-center rounded-[7px] text-ink-3 transition-colors hover:bg-hover-2 hover:text-ink"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round">
              <rect x="3" y="4" width="18" height="16" rx="2.5" />
              <path d="M9 4v16" />
            </svg>
          </button>

          <div className="mt-3 flex flex-1 flex-col items-center gap-2 overflow-y-auto px-1">
            {railContacts.map((c) => {
              const isSelected = !meetingRoomActive && activeBotID === c.id;
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => onOpenDirectChat(c.id)}
                  title={c.name}
                  className={`relative rounded-[8px] p-0.5 transition-colors ${
                    isSelected ? "bg-surface shadow-hairline" : "hover:bg-hover"
                  }`}
                >
                  <ContactAvatar name={c.name} avatarURL={c.avatarURL} accentHex={c.accentHex} sizeClass="size-7" />
                  {c.unreadCount > 0 && (
                    <span className="absolute -right-0.5 -top-0.5 size-2 rounded-full bg-ink ring-[1.5px] ring-canvas" />
                  )}
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Full expanded sidebar */}
      <div className={`flex min-h-0 w-[232px] shrink-0 flex-col py-2 transition-opacity duration-150 ${collapsed ? "pointer-events-none opacity-0" : "opacity-100"}`}>
        {/* Header: collapse + segmented tabs + search */}
        <div className="mx-2.5 flex items-center gap-1.5">
          <button
            type="button"
            onClick={onToggleCollapse}
            title={locale === "zh" ? "收起侧栏" : "Collapse sidebar"}
            className="flex size-7 shrink-0 items-center justify-center rounded-[7px] text-ink-3 transition-colors hover:bg-hover-2 hover:text-ink"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round">
              <rect x="3" y="4" width="18" height="16" rx="2.5" />
              <path d="M9 4v16" />
            </svg>
          </button>

          <div className="flex min-w-0 flex-1 items-center rounded-[8px] bg-inset p-0.5 shadow-hairline">
            <button
              type="button"
              onClick={() => switchTab("messages")}
              className={`flex h-6 flex-1 items-center justify-center gap-1 rounded-[6px] px-1.5 text-[12px] font-medium transition-colors ${
                activeTab === "messages" ? "bg-surface text-ink shadow-hairline" : "text-ink-3 hover:text-ink"
              }`}
            >
              <span>{locale === "zh" ? "消息" : "Chats"}</span>
              {totalUnread > 0 && (
                <span className="inline-flex min-w-[15px] items-center justify-center rounded-full bg-ink/85 px-1 text-[10px] font-semibold tabular-nums text-page">
                  {totalUnread > 99 ? "99+" : totalUnread}
                </span>
              )}
            </button>
            <button
              type="button"
              onClick={() => switchTab("contacts")}
              className={`flex h-6 flex-1 items-center justify-center rounded-[6px] px-1.5 text-[12px] font-medium transition-colors ${
                activeTab === "contacts" ? "bg-surface text-ink shadow-hairline" : "text-ink-3 hover:text-ink"
              }`}
            >
              <span>{locale === "zh" ? "联系人" : "Contacts"}</span>
            </button>
          </div>

          <button
            type="button"
            aria-label="Search"
            onClick={() => setSearchOpen((v) => !v)}
            className={`flex size-7 shrink-0 items-center justify-center rounded-[7px] transition-colors ${
              searchOpen ? "bg-hover-2 text-ink" : "text-ink-3 hover:bg-hover-2 hover:text-ink"
            }`}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.3-4.3" />
            </svg>
          </button>
        </div>

        {/* Inline search input */}
        {searchOpen && (
          <div className="mx-2.5 mt-2 flex h-7.5 items-center rounded-[8px] bg-surface px-2 shadow-hairline">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-ink-3">
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.3-4.3" />
            </svg>
            <input
              ref={searchRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  setSearchOpen(false);
                  setQuery("");
                }
              }}
              placeholder={locale === "zh" ? "搜索" : "Search"}
              className="ml-1.5 min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3 select-text"
            />
            {query && (
              <button
                type="button"
                aria-label="Clear search"
                onClick={() => setQuery("")}
                className="flex size-5 items-center justify-center text-ink-3 hover:text-ink"
              >
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                  <path d="M18 6L6 18M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>
        )}

        {/* Scrollable body */}
        <div className="bui-scroll mt-2.5 min-h-0 flex-1 overflow-y-auto px-1.5">
          {activeTab === "messages" ? (
            <>
              <div className="mx-1.5 mb-1.5 flex items-center justify-between">
                <button
                  type="button"
                  onClick={() => toggleGroupCollapsed("messages_list")}
                  className="flex items-center gap-1 text-[11.5px] font-medium text-ink-3 hover:text-ink"
                >
                  <svg
                    width="10"
                    height="10"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    className={`transition-transform duration-150 ${collapsedGroupMap.messages_list ? "" : "rotate-90"}`}
                  >
                    <path d="M9 6l6 6-6 6" />
                  </svg>
                  <span>{locale === "zh" ? "最近对话" : "Recent"}</span>
                </button>
                <button
                  type="button"
                  onClick={onNewGroup}
                  className="flex h-6 items-center gap-1 rounded-[6px] px-1.5 text-[11.5px] font-medium text-ink-2 transition-colors hover:bg-hover-2 hover:text-ink"
                >
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                  <span>{locale === "zh" ? "新建群聊" : "New Group"}</span>
                </button>
              </div>

              {!collapsedGroupMap.messages_list && (
                <GlideMenu rowSelector="[data-row]" highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2" className="flex flex-col gap-0.5">
                  {messageItems.map((item) => {
                    if (item.kind === "dm") {
                      const isActive = !meetingRoomActive && activeBotID === item.botID;
                      const relTime = formatRelativeTime(item.updatedAt, locale);
                      return (
                        <button
                          key={item.id}
                          type="button"
                          data-row
                          onClick={() => onOpenDirectChat(item.botID)}
                          className={`relative z-10 flex w-full items-center gap-2 rounded-[8px] px-2 py-1.5 text-left transition-colors ${
                            isActive ? "bg-surface text-ink shadow-hairline" : "text-ink-2 hover:text-ink"
                          }`}
                        >
                          <ContactAvatar name={item.name} avatarURL={item.avatarURL} accentHex={item.accentHex} sizeClass="size-7" />
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center justify-between gap-1.5">
                              <span className="truncate text-[13px] font-medium text-ink">{item.name}</span>
                              {relTime && (
                                <span className="shrink-0 text-[11px] tabular-nums text-ink-3">{relTime}</span>
                              )}
                            </div>
                            <div className="mt-0.5 flex items-center justify-between gap-1.5">
                              <span className="truncate text-[12px] text-ink-3">{item.preview || " "}</span>
                              {item.unreadCount > 0 && (
                                <span className="inline-flex h-[17px] min-w-[17px] shrink-0 items-center justify-center rounded-full bg-ink/85 px-1 text-[10.5px] font-semibold tabular-nums text-page">
                                  {item.unreadCount > 99 ? "99+" : item.unreadCount}
                                </span>
                              )}
                            </div>
                          </div>
                        </button>
                      );
                    }

                    const isActive = meetingRoomActive && activeMeetingSessionID === item.sessionID;
                    const relTime = formatRelativeTime(item.updatedAt, locale);
                    return (
                      <button
                        key={item.id}
                        type="button"
                        data-row
                        onClick={() => onSelectMeetingSession(item.sessionID)}
                        className={`relative z-10 flex w-full items-center gap-2 rounded-[8px] px-2 py-1.5 text-left transition-colors ${
                          isActive ? "bg-surface text-ink shadow-hairline" : "text-ink-2 hover:text-ink"
                        }`}
                      >
                        <span className="flex size-7 shrink-0 items-center justify-center rounded-[7px] bg-inset text-ink-2 shadow-hairline">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                            <circle cx="9" cy="8.5" r="2.8" />
                            <circle cx="16.5" cy="9.5" r="2.2" />
                            <path d="M3.5 19a5.5 5.5 0 0 1 11 0" />
                            <path d="M14.5 18.5a4 4 0 0 1 5.5 0" />
                          </svg>
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-1.5">
                            <span className="flex min-w-0 items-center gap-1 truncate text-[13px] font-medium text-ink">
                              <span className="truncate">{item.name}</span>
                              {meetingRoomIsConvening && isActive && (
                                <span className="size-1.5 shrink-0 rounded-full bg-ink/65" />
                              )}
                            </span>
                            {relTime && (
                              <span className="shrink-0 text-[11px] tabular-nums text-ink-3">{relTime}</span>
                            )}
                          </div>
                          <div className="mt-0.5 truncate text-[12px] text-ink-3">{item.preview}</div>
                        </div>
                      </button>
                    );
                  })}

                  {messageItems.length === 0 && (
                    <div className="px-2 py-4 text-center text-[12.5px] text-ink-3">
                      {locale === "zh" ? "暂无匹配对话" : "No conversations"}
                    </div>
                  )}
                </GlideMenu>
              )}
            </>
          ) : (
            <GlideMenu rowSelector="[data-row]" highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2" className="flex flex-col gap-2">
              {[
                { key: "butler", label: locale === "zh" ? "总管" : "Butler", items: contactBuckets.butler, showAdd: false },
                { key: "builtin", label: locale === "zh" ? "内置" : "Built-in", items: contactBuckets.builtIn, showAdd: false },
                { key: "custom", label: locale === "zh" ? "自定义" : "Custom", items: contactBuckets.custom, showAdd: Boolean(onOpenCreateBotSheet) },
              ].map((section) => {
                if (section.items.length === 0 && !section.showAdd) return null;
                const isCollapsedSection = Boolean(collapsedGroupMap[`contacts_${section.key}`]) && !cleanQuery;
                return (
                  <div key={section.key} className="flex flex-col gap-0.5">
                    <div className="mx-1.5 flex h-6 items-center justify-between">
                      <button
                        type="button"
                        onClick={() => toggleGroupCollapsed(`contacts_${section.key}`)}
                        className="flex items-center gap-1 text-[11.5px] font-medium text-ink-3 hover:text-ink"
                      >
                        <svg
                          width="10"
                          height="10"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.2"
                          strokeLinecap="round"
                          className={`transition-transform duration-150 ${isCollapsedSection ? "" : "rotate-90"}`}
                        >
                          <path d="M9 6l6 6-6 6" />
                        </svg>
                        <span>{section.label}</span>
                      </button>
                      {section.showAdd && onOpenCreateBotSheet && (
                        <button
                          type="button"
                          onClick={onOpenCreateBotSheet}
                          title={locale === "zh" ? "新建 Bot" : "New Bot"}
                          className="flex size-5.5 items-center justify-center rounded-[5px] text-ink-3 transition-colors hover:bg-hover-2 hover:text-ink"
                        >
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                            <path d="M12 5v14M5 12h14" />
                          </svg>
                        </button>
                      )}
                    </div>
                    {!isCollapsedSection &&
                      section.items.map((c) => {
                        const isActive = !meetingRoomActive && activeBotID === c.id;
                        return (
                          <button
                            key={c.id}
                            type="button"
                            data-row
                            onClick={() => onOpenDirectChat(c.id)}
                            className={`relative z-10 flex w-full items-center gap-2 rounded-[8px] px-2 py-1.5 text-left transition-colors ${
                              isActive ? "bg-surface text-ink shadow-hairline" : "text-ink-2 hover:text-ink"
                            }`}
                          >
                            <ContactAvatar name={c.name} avatarURL={c.avatarURL} accentHex={c.accentHex} sizeClass="size-7" />
                            <div className="min-w-0 flex-1">
                              <div className="flex items-center justify-between gap-1.5">
                                <span className="truncate text-[13px] font-medium text-ink">{c.name}</span>
                                {c.unreadCount > 0 ? (
                                  <span className="inline-flex h-[17px] min-w-[17px] shrink-0 items-center justify-center rounded-full bg-ink/85 px-1 text-[10.5px] font-semibold tabular-nums text-page">
                                    {c.unreadCount > 99 ? "99+" : c.unreadCount}
                                  </span>
                                ) : (
                                  <span className="shrink-0 text-[11.5px] text-ink-3">{c.nickname}</span>
                                )}
                              </div>
                            </div>
                          </button>
                        );
                      })}
                  </div>
                );
              })}
            </GlideMenu>
          )}
        </div>

        {/* Footer: Bots Settings */}
        <div className="mx-2.5 mt-2 border-t border-line pt-2">
          <button
            type="button"
            onClick={onOpenSettings}
            className="flex h-8.5 w-full items-center justify-center gap-1.5 rounded-control bg-hover-2 text-[13px] font-medium text-ink transition-colors duration-150 hover:bg-line-strong active:scale-[0.98]"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
            {locale === "zh" ? "Bots 设置" : "Bots Settings"}
          </button>
        </div>
      </div>
    </aside>
  );
});

export default IMSidebar;
