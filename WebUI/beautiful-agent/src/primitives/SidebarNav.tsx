import { useEffect, useMemo, useRef, useState } from "react";
import GlideMenu from "./GlideMenu";
import type { SessionSummary, WorkspaceOption } from "../types";

/* ─────────────────────────────────────────────────────────
 * SIDEBAR NAV — Workspace-Grouped Session Rail
 *   · Sessions organized by bound workspace folder + General
 *   · One-click New Session (in current workspace) & New Workspace Session
 *   · Inline search, double-click rename, pin, delete
 *   · Zero tiny text: all copy ≥ 13px for crisp readability
 * ───────────────────────────────────────────────────────── */

type SidebarNavProps = {
  botName: string;
  botAvatarDataURL?: string | null;
  sessions: SessionSummary[];
  activeSessionID: string;
  availableWorkspaces: WorkspaceOption[];
  collapsed: boolean;
  locale: "zh" | "en";
  onToggleCollapse: () => void;
  onNewChat: (workspacePath?: string | null) => void;
  onChooseNewWorkspaceSession: () => void;
  onSelectSession: (id: string) => void;
  onDeleteSession: (id: string) => void;
  onRenameSession: (id: string, title: string) => void;
  onTogglePinSession: (id: string) => void;
  onOpenSettings: () => void;
};

type SessionGroup = {
  key: string;
  workspacePath: string | null;
  label: string;
  sessions: SessionSummary[];
};

export default function SidebarNav({
  botName,
  botAvatarDataURL,
  sessions,
  activeSessionID,
  availableWorkspaces,
  collapsed,
  locale,
  onToggleCollapse,
  onNewChat,
  onChooseNewWorkspaceSession,
  onSelectSession,
  onDeleteSession,
  onRenameSession,
  onTogglePinSession,
  onOpenSettings,
}: SidebarNavProps) {
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [renamingID, setRenamingID] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);

  useEffect(() => {
    if (collapsed) {
      setSearchOpen(false);
      setQuery("");
    }
  }, [collapsed]);

  const activeSession = sessions.find((s) => s.id === activeSessionID);

  const visibleSessions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sessions;
    return sessions.filter(
      (s) =>
        s.title.toLowerCase().includes(q) ||
        (s.workspaceName && s.workspaceName.toLowerCase().includes(q)),
    );
  }, [sessions, query]);

  const groupedSessions = useMemo<SessionGroup[]>(() => {
    const workspaceMap = new Map<string, SessionGroup>();
    const general: SessionSummary[] = [];

    for (const s of visibleSessions) {
      const wp = s.workspacePath?.trim();
      if (wp) {
        const existing = workspaceMap.get(wp);
        if (existing) {
          existing.sessions.push(s);
        } else {
          workspaceMap.set(wp, {
            key: `ws:${wp}`,
            workspacePath: wp,
            label: s.workspaceName || wp.split("/").filter(Boolean).pop() || wp,
            sessions: [s],
          });
        }
      } else {
        general.push(s);
      }
    }

    const groups: SessionGroup[] = Array.from(workspaceMap.values());
    if (general.length > 0) {
      groups.push({
        key: "general",
        workspacePath: null,
        label: locale === "zh" ? "通用会话" : "General",
        sessions: general,
      });
    }
    return groups;
  }, [visibleSessions, locale]);

  const hasAnyWorkspaceGroup = groupedSessions.some((g) => g.workspacePath !== null);

  const commitRename = (id: string) => {
    const clean = renameDraft.trim();
    if (clean) onRenameSession(id, clean);
    setRenamingID(null);
  };

  const renderSessionRow = (session: SessionSummary) => {
    const active = session.id === activeSessionID;
    const isRenaming = renamingID === session.id;
    return (
      <div
        key={session.id}
        data-row
        className={`group/item sidebar-row relative z-10 mx-2 flex h-8.5 items-center gap-1.5 rounded-[8px] px-2 transition-[width,background-color] duration-100 ${
          active ? "bg-hover-2 group-hover/glide:bg-transparent" : ""
        }`}
      >
        {session.isPinned && (
          <span className="sidebar-copy size-1.5 shrink-0 rounded-full bg-accent" />
        )}

        {isRenaming ? (
          <input
            autoFocus
            value={renameDraft}
            onChange={(e) => setRenameDraft(e.target.value)}
            onBlur={() => commitRename(session.id)}
            onKeyDown={(e) => {
              if (e.key === "Enter") commitRename(session.id);
              if (e.key === "Escape") setRenamingID(null);
            }}
            className="min-w-0 flex-1 bg-transparent text-[13px] font-medium text-ink outline-none select-text"
          />
        ) : (
          <button
            type="button"
            title={session.workspaceName ? `${session.title} · ${session.workspaceName}` : session.title}
            onClick={() => onSelectSession(session.id)}
            onDoubleClick={() => {
              setRenameDraft(session.title);
              setRenamingID(session.id);
            }}
            className="min-w-0 flex-1 text-left"
          >
            <span
              className={`sidebar-copy block truncate text-[13px] ${
                active ? "font-medium text-ink" : "text-ink-2"
              }`}
            >
              {session.title}
            </span>
          </button>
        )}

        {!isRenaming && !collapsed && (
          <div className="sidebar-copy flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity duration-100 group-hover/item:opacity-100">
            <button
              type="button"
              aria-label={session.isPinned ? "Unpin" : "Pin"}
              onClick={(e) => {
                e.stopPropagation();
                onTogglePinSession(session.id);
              }}
              className="flex size-6 items-center justify-center rounded-[5px] text-ink-3 hover:bg-hover hover:text-ink"
              title={session.isPinned ? (locale === "zh" ? "取消置顶" : "Unpin") : locale === "zh" ? "置顶" : "Pin"}
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill={session.isPinned ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2">
                <path d="M12 17v5M5 9l7-7 7 7-3 3v4H8v-4z" />
              </svg>
            </button>
            <button
              type="button"
              aria-label="Delete"
              onClick={(e) => {
                e.stopPropagation();
                onDeleteSession(session.id);
              }}
              className="flex size-6 items-center justify-center rounded-[5px] text-ink-3 hover:bg-hover hover:text-red"
              title={locale === "zh" ? "删除" : "Delete"}
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                <path d="M18 6L6 18M6 6l12 12" />
              </svg>
            </button>
          </div>
        )}
      </div>
    );
  };

  return (
    <aside
      data-sidebar-collapsed={collapsed}
      aria-label="Sessions navigation"
      className="relative flex h-full shrink-0 overflow-hidden bg-canvas transition-[width]"
      style={{
        width: collapsed ? 50 : 232,
        transitionDuration: "240ms",
        transitionTimingFunction: "cubic-bezier(0.16, 1, 0.3, 1)",
      }}
    >
      <div className="flex min-h-0 w-[232px] shrink-0 flex-col py-2">
        {/* Top identity + collapse toggle */}
        <div className="relative mb-2 flex h-9 shrink-0 items-center px-2">
          <div
            className={`flex min-w-0 flex-1 items-center gap-2 rounded-[8px] px-1.5 py-1 transition-opacity duration-150 ${
              collapsed ? "pointer-events-none opacity-0" : "opacity-100"
            }`}
          >
            {botAvatarDataURL ? (
              <img
                src={botAvatarDataURL}
                alt={botName}
                className="size-6 shrink-0 rounded-[7px] object-cover shadow-hairline"
              />
            ) : (
              <span className="flex size-6 shrink-0 items-center justify-center rounded-[7px] bg-ink text-[13px] font-semibold text-surface">
                {botName.slice(0, 1)}
              </span>
            )}
            <span className="truncate text-[14px] font-semibold text-ink">{botName}</span>
          </div>

          <button
            type="button"
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            onClick={onToggleCollapse}
            className={`flex size-8 shrink-0 items-center justify-center rounded-[8px] text-ink-3 transition-colors duration-150 hover:bg-hover-2 hover:text-ink ${
              collapsed ? "absolute left-2" : ""
            }`}
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.9"
              strokeLinecap="round"
              strokeLinejoin="round"
              className={`transition-transform duration-200 ${collapsed ? "rotate-180" : ""}`}
            >
              <rect x="3" y="4" width="18" height="16" rx="2.5" />
              <path d="M9 4v16" />
            </svg>
          </button>
        </div>

        {/* Primary actions: New Session + New Workspace Session */}
        <GlideMenu
          rowSelector="[data-row]"
          highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2"
          className="flex flex-col gap-0.5"
        >
          <button
            data-row
            type="button"
            onClick={() => onNewChat(activeSession?.workspacePath ?? null)}
            title={locale === "zh" ? "新建会话" : "New session"}
            className="sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-[width,transform] duration-150 active:scale-[0.98]"
          >
            <span className="flex size-4.5 shrink-0 items-center justify-center text-ink-2">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 20h9" />
                <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" />
              </svg>
            </span>
            <span className="sidebar-copy ml-2 truncate text-[13.5px] font-medium text-ink">
              {locale === "zh" ? "新建会话" : "New session"}
            </span>
          </button>

          <button
            data-row
            type="button"
            onClick={onChooseNewWorkspaceSession}
            title={locale === "zh" ? "选择工作区目录开启会话" : "New workspace session"}
            className="sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-[width,transform] duration-150 active:scale-[0.98]"
          >
            <span className="flex size-4.5 shrink-0 items-center justify-center text-ink-2">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                <path d="M12 11v6M9 14h6" />
              </svg>
            </span>
            <span className="sidebar-copy ml-2 truncate text-[13.5px] font-medium text-ink-2">
              {locale === "zh" ? "工作区会话" : "Workspace session"}
            </span>
          </button>
        </GlideMenu>

        {/* Searchable workspace-grouped session history */}
        <div className="bui-scroll mt-3 min-h-0 flex-1 overflow-y-auto">
          <div className="sidebar-copy relative mx-2 mb-1.5 h-8">
            <div
              aria-hidden={searchOpen}
              className={`absolute inset-0 flex items-center gap-1 px-2 text-[13px] font-medium text-ink-3 transition-[opacity,transform] duration-180 ${
                searchOpen ? "pointer-events-none -translate-x-1 opacity-0" : "translate-x-0 opacity-100"
              }`}
            >
              <span>{locale === "zh" ? "会话列表" : "Sessions"}</span>
            </div>

            <button
              type="button"
              aria-label="Search sessions"
              onClick={() => setSearchOpen(true)}
              className={`absolute right-0 top-0 z-10 flex size-8 items-center justify-center rounded-[7px] text-ink-3 transition-[opacity,background-color,color] duration-150 hover:bg-hover-2 hover:text-ink ${
                searchOpen ? "pointer-events-none opacity-0" : "opacity-100"
              }`}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <circle cx="11" cy="11" r="7" />
                <path d="M21 21l-4.3-4.3" />
              </svg>
            </button>

            <div
              className={`absolute right-0 top-0 z-20 flex h-8 items-center overflow-hidden rounded-[8px] bg-surface text-ink-3 shadow-hairline transition-[width,opacity] duration-180 ${
                searchOpen ? "pointer-events-auto opacity-100" : "pointer-events-none opacity-0"
              }`}
              style={{ width: searchOpen ? "100%" : 32 }}
            >
              <span className="ml-2 flex shrink-0 items-center justify-center">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <circle cx="11" cy="11" r="7" />
                  <path d="M21 21l-4.3-4.3" />
                </svg>
              </span>
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
                placeholder={locale === "zh" ? "搜索会话或工作区" : "Search sessions"}
                className="ml-1.5 min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none placeholder:text-ink-3 select-text"
              />
              <button
                type="button"
                aria-label="Close search"
                onClick={() => {
                  setSearchOpen(false);
                  setQuery("");
                }}
                className="flex size-7 shrink-0 items-center justify-center text-ink-3 hover:text-ink"
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                  <path d="M18 6L6 18M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>

          <GlideMenu
            rowSelector="[data-row]"
            highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2"
            className="group/glide flex flex-col gap-0.5"
          >
            {hasAnyWorkspaceGroup
              ? groupedSessions.map((group) => (
                  <div key={group.key} className="mb-2 last:mb-0">
                    <div className="sidebar-copy mx-2 mb-0.5 flex h-7.5 items-center justify-between gap-1.5 px-2">
                      <span
                        className="flex min-w-0 items-center gap-1.5 text-[13px] font-medium text-ink-2"
                        title={group.workspacePath ?? group.label}
                      >
                        {group.workspacePath ? (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-accent-ink">
                            <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                          </svg>
                        ) : (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 text-ink-3">
                            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                          </svg>
                        )}
                        <span className="truncate">{group.label}</span>
                      </span>
                      <button
                        type="button"
                        onClick={() => onNewChat(group.workspacePath)}
                        title={
                          group.workspacePath
                            ? locale === "zh"
                              ? `在「${group.label}」新建会话`
                              : `New session in ${group.label}`
                            : locale === "zh"
                              ? "新建通用会话"
                              : "New general session"
                        }
                        className="flex size-6 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink"
                      >
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                          <path d="M12 5v14M5 12h14" />
                        </svg>
                      </button>
                    </div>
                    {group.sessions.map(renderSessionRow)}
                  </div>
                ))
              : visibleSessions.map(renderSessionRow)}

            {/* Quick shortcut for currently open editor folders that don't have a session yet */}
            {!query &&
              !collapsed &&
              availableWorkspaces
                .filter((w) => w.isOpenInEditor && !sessions.some((s) => s.workspacePath === w.path))
                .slice(0, 3)
                .map((ws) => (
                  <button
                    key={ws.path}
                    data-row
                    type="button"
                    onClick={() => onNewChat(ws.path)}
                    title={ws.subtitle}
                    className="sidebar-row relative z-10 mx-2 mt-1 flex h-8.5 items-center gap-2 rounded-[8px] px-2 text-left text-ink-3 transition-colors duration-100 hover:text-ink"
                  >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                    </svg>
                    <span className="sidebar-copy min-w-0 flex-1 truncate text-[13px]">
                      {ws.name}
                    </span>
                    <span className="sidebar-copy shrink-0 text-[12.5px] text-ink-3">+</span>
                  </button>
                ))}

            {query && visibleSessions.length === 0 && (
              <div className="sidebar-copy mx-2 px-2 py-2 text-[13px] text-ink-3">
                {locale === "zh" ? "未找到匹配会话" : "No sessions found"}
              </div>
            )}
          </GlideMenu>
        </div>

        {/* Footer settings CTA */}
        <div className="sidebar-copy mx-2 mt-2 border-t border-line pt-2">
          <button
            type="button"
            onClick={onOpenSettings}
            className="flex h-8.5 w-full items-center justify-center gap-1.5 rounded-control bg-hover-2 text-[13px] font-medium text-ink transition-[background-color,transform] duration-150 hover:bg-line-strong active:scale-[0.98]"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l-.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
            {locale === "zh" ? "助手设置" : "Agent Settings"}
          </button>
        </div>
      </div>
    </aside>
  );
}
