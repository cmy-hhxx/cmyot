import { useEffect, useMemo, useRef, useState } from "react";
import GlideMenu from "./GlideMenu";
import type { SessionSummary, WorkspaceOption } from "../types";

/* ─────────────────────────────────────────────────────────
 * SIDEBAR NAV — Logical Workspaces & Drag-Reorderable Sessions
 *   · Arbitrary logical workspaces (optional local folder link) + General
 *   · Pointer-event drag & drop to reorder sessions & move across groups
 *   · Pointer-event drag & drop to reorder workspace groups
 *   · Inline search, double-click rename, pin, delete
 *   · Zero tiny text: all copy ≥ 13px for crisp readability
 * ───────────────────────────────────────────────────────── */

const GENERAL_GROUP_ID = "__general__";

type SidebarNavProps = {
  botName: string;
  botAvatarDataURL?: string | null;
  sessions: SessionSummary[];
  activeSessionID: string;
  availableWorkspaces: WorkspaceOption[];
  collapsed: boolean;
  locale: "zh" | "en";
  onToggleCollapse: () => void;
  onNewChat: (workspaceID?: string | null, workspacePath?: string | null) => void;
  onCreateWorkspace: (name: string) => void;
  onRenameWorkspace: (id: string, name: string) => void;
  onDeleteWorkspace: (id: string) => void;
  onChooseWorkspaceFolder: (workspaceID: string) => void;
  onUnlinkWorkspaceFolder: (workspaceID: string) => void;
  onReorderWorkspaces: (orderedIDs: string[]) => void;
  onMoveSession: (
    sessionID: string,
    targetWorkspaceID: string | null,
    orderedSessionIDs: string[],
    isPinned?: boolean,
  ) => void;
  onSelectSession: (id: string) => void;
  onDeleteSession: (id: string) => void;
  onRenameSession: (id: string, title: string) => void;
  onTogglePinSession: (id: string) => void;
  onOpenSettings: () => void;
};

type SessionGroup = {
  id: string;
  workspaceID: string | null;
  workspace: WorkspaceOption | null;
  label: string;
  sessions: SessionSummary[];
};

type SessionDragState = {
  session: SessionSummary;
  sourceGroupId: string;
  x: number;
  y: number;
};

type SessionDropTarget =
  | {
      kind: "row";
      groupId: string;
      targetSessionId: string;
      position: "before" | "after";
    }
  | {
      kind: "group";
      groupId: string;
    };

type WorkspaceDragState = {
  workspace: WorkspaceOption;
  x: number;
  y: number;
};

type WorkspaceDropTarget = {
  targetWorkspaceId: string;
  position: "before" | "after";
};

function WorkspaceGlyph({
  isFolderBacked,
  isGeneral,
  className = "",
}: {
  isFolderBacked?: boolean;
  isGeneral?: boolean;
  className?: string;
}) {
  if (isGeneral) {
    return (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
      </svg>
    );
  }
  if (isFolderBacked) {
    return (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
        <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      </svg>
    );
  }
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
      <rect x="3" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="3" y="14" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" />
    </svg>
  );
}

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
  onCreateWorkspace,
  onRenameWorkspace,
  onDeleteWorkspace,
  onChooseWorkspaceFolder,
  onUnlinkWorkspaceFolder,
  onReorderWorkspaces,
  onMoveSession,
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

  const [creatingWorkspace, setCreatingWorkspace] = useState(false);
  const [newWorkspaceDraft, setNewWorkspaceDraft] = useState("");
  const [renamingWSID, setRenamingWSID] = useState<string | null>(null);
  const [renameWSDraft, setRenameWSDraft] = useState("");
  const [openMenuWSID, setOpenMenuWSID] = useState<string | null>(null);

  const [dragSession, setDragSession] = useState<SessionDragState | null>(null);
  const [sessionDropTarget, setSessionDropTarget] = useState<SessionDropTarget | null>(null);
  const [dragWorkspace, setDragWorkspace] = useState<WorkspaceDragState | null>(null);
  const [workspaceDropTarget, setWorkspaceDropTarget] = useState<WorkspaceDropTarget | null>(null);

  const searchRef = useRef<HTMLInputElement>(null);
  const listContainerRef = useRef<HTMLDivElement>(null);
  const suppressClickRef = useRef(false);

  const pendingSessionDragRef = useRef<{
    session: SessionSummary;
    sourceGroupId: string;
    startX: number;
    startY: number;
  } | null>(null);
  const activeSessionDragRef = useRef<SessionDragState | null>(null);
  const sessionDropTargetRef = useRef<SessionDropTarget | null>(null);

  const pendingWSDragRef = useRef<{
    workspace: WorkspaceOption;
    startX: number;
    startY: number;
  } | null>(null);
  const activeWSDragRef = useRef<WorkspaceDragState | null>(null);
  const workspaceDropTargetRef = useRef<WorkspaceDropTarget | null>(null);

  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);

  useEffect(() => {
    if (collapsed) {
      setSearchOpen(false);
      setQuery("");
      setCreatingWorkspace(false);
      setOpenMenuWSID(null);
    }
  }, [collapsed]);

  useEffect(() => {
    if (!openMenuWSID) return;
    const onDown = (e: PointerEvent) => {
      const target = e.target as HTMLElement | null;
      if (!target?.closest("[data-ws-menu-wrap]")) {
        setOpenMenuWSID(null);
      }
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [openMenuWSID]);

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
    const isSearching = query.trim().length > 0;
    const byWS = new Map<string, SessionSummary[]>();
    const general: SessionSummary[] = [];

    for (const s of visibleSessions) {
      const wid = s.workspaceID?.trim();
      if (wid && availableWorkspaces.some((w) => w.id === wid)) {
        const bucket = byWS.get(wid) ?? [];
        bucket.push(s);
        byWS.set(wid, bucket);
      } else {
        general.push(s);
      }
    }

    const groups: SessionGroup[] = [];
    for (const ws of availableWorkspaces) {
      const list = byWS.get(ws.id) ?? [];
      if (isSearching && list.length === 0) continue;
      groups.push({
        id: ws.id,
        workspaceID: ws.id,
        workspace: ws,
        label: ws.name,
        sessions: list,
      });
    }

    if (!isSearching || general.length > 0) {
      groups.push({
        id: GENERAL_GROUP_ID,
        workspaceID: null,
        workspace: null,
        label: locale === "zh" ? "通用会话" : "General",
        sessions: general,
      });
    }
    return groups;
  }, [visibleSessions, availableWorkspaces, query, locale]);

  const showGroupHeaders = availableWorkspaces.length > 0 || dragSession !== null;
  const canDrag = !collapsed && query.trim().length === 0 && !renamingID && !renamingWSID;

  // Keep latest callbacks/groups in refs for window pointer listeners
  const latestRef = useRef({
    groupedSessions,
    availableWorkspaces,
    onMoveSession,
    onReorderWorkspaces,
  });
  latestRef.current = {
    groupedSessions,
    availableWorkspaces,
    onMoveSession,
    onReorderWorkspaces,
  };

  useEffect(() => {
    const computeSessionDrop = (clientX: number, clientY: number): SessionDropTarget | null => {
      const container = listContainerRef.current;
      if (!container) return null;
      const cRect = container.getBoundingClientRect();
      if (clientX < cRect.left - 28 || clientX > cRect.right + 28) return null;

      const rowEls = container.querySelectorAll<HTMLElement>("[data-session-id]");
      for (const el of rowEls) {
        const r = el.getBoundingClientRect();
        if (clientY >= r.top - 4 && clientY <= r.bottom + 4) {
          const targetSessionId = el.dataset.sessionId;
          const groupId = el.dataset.groupId;
          if (!targetSessionId || !groupId) continue;
          const position = clientY < r.top + r.height / 2 ? "before" : "after";
          return { kind: "row", groupId, targetSessionId, position };
        }
      }

      const groupEls = container.querySelectorAll<HTMLElement>("[data-group-drop-id]");
      for (const el of groupEls) {
        const r = el.getBoundingClientRect();
        if (clientY >= r.top - 2 && clientY <= r.bottom + 2) {
          const groupId = el.dataset.groupDropId;
          if (groupId) return { kind: "group", groupId };
        }
      }
      return null;
    };

    const computeWorkspaceDrop = (clientX: number, clientY: number): WorkspaceDropTarget | null => {
      const container = listContainerRef.current;
      if (!container) return null;
      const cRect = container.getBoundingClientRect();
      if (clientX < cRect.left - 28 || clientX > cRect.right + 28) return null;

      const wsEls = container.querySelectorAll<HTMLElement>("[data-workspace-group-id]");
      for (const el of wsEls) {
        const r = el.getBoundingClientRect();
        if (clientY >= r.top - 4 && clientY <= r.bottom + 4) {
          const targetWorkspaceId = el.dataset.workspaceGroupId;
          if (!targetWorkspaceId) continue;
          const position = clientY < r.top + r.height / 2 ? "before" : "after";
          return { targetWorkspaceId, position };
        }
      }
      return null;
    };

    const onPointerMove = (e: PointerEvent) => {
      const pendingSess = pendingSessionDragRef.current;
      if (pendingSess && !activeSessionDragRef.current) {
        if (Math.hypot(e.clientX - pendingSess.startX, e.clientY - pendingSess.startY) >= 5) {
          suppressClickRef.current = true;
          window.getSelection()?.removeAllRanges();
          setOpenMenuWSID(null);
          const started: SessionDragState = {
            session: pendingSess.session,
            sourceGroupId: pendingSess.sourceGroupId,
            x: e.clientX,
            y: e.clientY,
          };
          activeSessionDragRef.current = started;
          setDragSession(started);
        }
      }

      if (activeSessionDragRef.current) {
        e.preventDefault();
        const updated = { ...activeSessionDragRef.current, x: e.clientX, y: e.clientY };
        activeSessionDragRef.current = updated;
        setDragSession(updated);
        const drop = computeSessionDrop(e.clientX, e.clientY);
        sessionDropTargetRef.current = drop;
        setSessionDropTarget(drop);
        return;
      }

      const pendingWS = pendingWSDragRef.current;
      if (pendingWS && !activeWSDragRef.current) {
        if (Math.hypot(e.clientX - pendingWS.startX, e.clientY - pendingWS.startY) >= 5) {
          suppressClickRef.current = true;
          window.getSelection()?.removeAllRanges();
          setOpenMenuWSID(null);
          const started: WorkspaceDragState = {
            workspace: pendingWS.workspace,
            x: e.clientX,
            y: e.clientY,
          };
          activeWSDragRef.current = started;
          setDragWorkspace(started);
        }
      }

      if (activeWSDragRef.current) {
        e.preventDefault();
        const updated = { ...activeWSDragRef.current, x: e.clientX, y: e.clientY };
        activeWSDragRef.current = updated;
        setDragWorkspace(updated);
        const drop = computeWorkspaceDrop(e.clientX, e.clientY);
        workspaceDropTargetRef.current = drop;
        setWorkspaceDropTarget(drop);
      }
    };

    const finishDrag = () => {
      const activeSess = activeSessionDragRef.current;
      const dropSess = sessionDropTargetRef.current;
      const activeWS = activeWSDragRef.current;
      const dropWS = workspaceDropTargetRef.current;

      pendingSessionDragRef.current = null;
      activeSessionDragRef.current = null;
      sessionDropTargetRef.current = null;
      pendingWSDragRef.current = null;
      activeWSDragRef.current = null;
      workspaceDropTargetRef.current = null;

      setDragSession(null);
      setSessionDropTarget(null);
      setDragWorkspace(null);
      setWorkspaceDropTarget(null);

      if (suppressClickRef.current) {
        setTimeout(() => {
          suppressClickRef.current = false;
        }, 60);
      }

      const { groupedSessions: groups, availableWorkspaces: wss, onMoveSession: moveSess, onReorderWorkspaces: reorderWS } =
        latestRef.current;

      if (activeSess && dropSess) {
        const targetGroup = groups.find((g) => g.id === dropSess.groupId);
        if (!targetGroup) return;
        const remaining = targetGroup.sessions.filter((s) => s.id !== activeSess.session.id);

        if (dropSess.kind === "row") {
          if (
            dropSess.targetSessionId === activeSess.session.id &&
            dropSess.groupId === activeSess.sourceGroupId
          ) {
            return;
          }
          const targetIdx = remaining.findIndex((s) => s.id === dropSess.targetSessionId);
          const targetSession = targetIdx >= 0 ? remaining[targetIdx] : undefined;
          const insertAt =
            targetIdx === -1
              ? remaining.length
              : dropSess.position === "before"
                ? targetIdx
                : targetIdx + 1;

          const nextList = remaining.slice();
          nextList.splice(insertAt, 0, activeSess.session);

          let nextPinned: boolean | undefined = activeSess.session.isPinned;
          if (targetSession) {
            if (targetSession.isPinned && dropSess.position === "before") {
              nextPinned = true;
            } else if (!targetSession.isPinned && dropSess.position === "after") {
              nextPinned = false;
            } else if (targetSession.isPinned && dropSess.position === "after") {
              const nextNeighbor = remaining[targetIdx + 1];
              nextPinned = nextNeighbor?.isPinned ? true : activeSess.session.isPinned;
            } else {
              const prevNeighbor = targetIdx > 0 ? remaining[targetIdx - 1] : undefined;
              nextPinned = prevNeighbor && !prevNeighbor.isPinned ? false : activeSess.session.isPinned;
            }
          }

          moveSess(
            activeSess.session.id,
            dropSess.groupId === GENERAL_GROUP_ID ? null : dropSess.groupId,
            nextList.map((s) => s.id),
            nextPinned,
          );
        } else {
          const nextList = remaining.slice();
          if (activeSess.session.isPinned) {
            const lastPinnedIdx = nextList.reduce((acc, item, i) => (item.isPinned ? i : acc), -1);
            nextList.splice(lastPinnedIdx + 1, 0, activeSess.session);
          } else {
            nextList.push(activeSess.session);
          }
          moveSess(
            activeSess.session.id,
            dropSess.groupId === GENERAL_GROUP_ID ? null : dropSess.groupId,
            nextList.map((s) => s.id),
            activeSess.session.isPinned,
          );
        }
        return;
      }

      if (activeWS && dropWS && dropWS.targetWorkspaceId !== activeWS.workspace.id) {
        const ids = wss.map((w) => w.id).filter((id) => id !== activeWS.workspace.id);
        const idx = ids.indexOf(dropWS.targetWorkspaceId);
        if (idx === -1) return;
        const insertAt = dropWS.position === "before" ? idx : idx + 1;
        ids.splice(insertAt, 0, activeWS.workspace.id);
        reorderWS(ids);
      }
    };

    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", finishDrag);
    window.addEventListener("pointercancel", finishDrag);
    return () => {
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerup", finishDrag);
      window.removeEventListener("pointercancel", finishDrag);
    };
  }, []);

  const commitRename = (id: string) => {
    const clean = renameDraft.trim();
    if (clean) onRenameSession(id, clean);
    setRenamingID(null);
  };

  const commitWorkspaceRename = (id: string) => {
    const clean = renameWSDraft.trim();
    if (clean) onRenameWorkspace(id, clean);
    setRenamingWSID(null);
  };

  const submitNewWorkspace = () => {
    const clean = newWorkspaceDraft.trim();
    if (clean) {
      onCreateWorkspace(clean);
    }
    setCreatingWorkspace(false);
    setNewWorkspaceDraft("");
  };

  const renderSessionRow = (session: SessionSummary, groupId: string) => {
    const active = session.id === activeSessionID;
    const isRenaming = renamingID === session.id;
    const isBeingDragged = dragSession?.session.id === session.id;
    const showInsertBefore =
      sessionDropTarget?.kind === "row" &&
      sessionDropTarget.targetSessionId === session.id &&
      sessionDropTarget.position === "before" &&
      !isBeingDragged;
    const showInsertAfter =
      sessionDropTarget?.kind === "row" &&
      sessionDropTarget.targetSessionId === session.id &&
      sessionDropTarget.position === "after" &&
      !isBeingDragged;

    return (
      <div
        key={session.id}
        data-row
        data-session-id={session.id}
        data-group-id={groupId}
        role="button"
        tabIndex={0}
        title={session.workspaceName ? `${session.title} · ${session.workspaceName}` : session.title}
        onPointerDown={(e) => {
          if (!canDrag || e.button !== 0) return;
          if ((e.target as HTMLElement).closest("[data-row-action], input")) return;
          pendingSessionDragRef.current = {
            session,
            sourceGroupId: groupId,
            startX: e.clientX,
            startY: e.clientY,
          };
        }}
        onClick={() => {
          if (suppressClickRef.current || isRenaming) return;
          onSelectSession(session.id);
        }}
        onDoubleClick={() => {
          if (collapsed) return;
          setRenameDraft(session.title);
          setRenamingID(session.id);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !isRenaming) {
            onSelectSession(session.id);
          }
        }}
        className={`group/item sidebar-row relative z-10 mx-2 flex h-8.5 items-center gap-1.5 rounded-[8px] px-2 transition-[width,background-color,opacity] duration-100 select-none ${
          isBeingDragged
            ? "opacity-35"
            : active
              ? "bg-hover-2 group-hover/glide:bg-transparent"
              : ""
        } ${canDrag ? "cursor-grab active:cursor-grabbing" : "cursor-pointer"}`}
      >
        {showInsertBefore && (
          <span
            aria-hidden
            className="pointer-events-none absolute inset-x-1 -top-0.5 z-30 h-0.5 rounded-full bg-accent"
          >
            <span className="absolute -left-0.5 -top-[3px] size-2 rounded-full bg-accent" />
          </span>
        )}
        {showInsertAfter && (
          <span
            aria-hidden
            className="pointer-events-none absolute inset-x-1 -bottom-0.5 z-30 h-0.5 rounded-full bg-accent"
          >
            <span className="absolute -left-0.5 -top-[3px] size-2 rounded-full bg-accent" />
          </span>
        )}

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
              e.stopPropagation();
              if (e.key === "Enter") commitRename(session.id);
              if (e.key === "Escape") setRenamingID(null);
            }}
            className="min-w-0 flex-1 bg-transparent text-[13px] font-medium text-ink outline-none select-text"
          />
        ) : (
          <span
            className={`sidebar-copy min-w-0 flex-1 truncate text-[13px] ${
              active ? "font-medium text-ink" : "text-ink-2"
            }`}
          >
            {session.title}
          </span>
        )}

        {!isRenaming && !collapsed && !dragSession && (
          <div className="sidebar-copy flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity duration-100 group-hover/item:opacity-100">
            <button
              type="button"
              data-row-action="true"
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
              data-row-action="true"
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
      className="relative flex h-full shrink-0 overflow-hidden border-r border-line bg-canvas transition-[width]"
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

        {/* Primary actions: New Session + New Logical Workspace */}
        <GlideMenu
          rowSelector="[data-row]"
          highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2"
          className="flex flex-col gap-0.5"
        >
          <button
            data-row
            type="button"
            onClick={() => onNewChat(activeSession?.workspaceID ?? null, activeSession?.workspacePath ?? null)}
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
            onClick={() => {
              if (collapsed) onToggleCollapse();
              setCreatingWorkspace(true);
              setNewWorkspaceDraft("");
            }}
            title={locale === "zh" ? "新建逻辑工作区分区" : "New logical workspace"}
            className="sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-[width,transform] duration-150 active:scale-[0.98]"
          >
            <span className="flex size-4.5 shrink-0 items-center justify-center text-ink-2">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="3" width="7" height="7" rx="1.5" />
                <rect x="14" y="3" width="7" height="7" rx="1.5" />
                <rect x="3" y="14" width="7" height="7" rx="1.5" />
                <path d="M17.5 14v7M14 17.5h7" />
              </svg>
            </span>
            <span className="sidebar-copy ml-2 truncate text-[13.5px] font-medium text-ink-2">
              {locale === "zh" ? "新建工作区" : "New workspace"}
            </span>
          </button>
        </GlideMenu>

        {creatingWorkspace && !collapsed && (
          <div className="mx-3 mt-1.5 flex items-center gap-1 rounded-[8px] bg-surface px-2 py-1 shadow-hairline">
            <input
              autoFocus
              value={newWorkspaceDraft}
              onChange={(e) => setNewWorkspaceDraft(e.target.value)}
              onBlur={() => {
                if (newWorkspaceDraft.trim()) submitNewWorkspace();
                else setCreatingWorkspace(false);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") submitNewWorkspace();
                if (e.key === "Escape") {
                  setCreatingWorkspace(false);
                  setNewWorkspaceDraft("");
                }
              }}
              placeholder={locale === "zh" ? "工作区名称，回车创建…" : "Workspace name…"}
              className="min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none placeholder:text-ink-3 select-text"
            />
          </div>
        )}

        {/* Searchable workspace-grouped session history with pointer drag & drop */}
        <div ref={listContainerRef} className="bui-scroll mt-3 min-h-0 flex-1 overflow-y-auto">
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
            highlightClassName={`sidebar-glide-highlight rounded-[8px] bg-hover-2 ${dragSession || dragWorkspace ? "hidden" : ""}`}
            className="group/glide flex flex-col gap-0.5"
          >
            {groupedSessions.map((group) => {
              const isGroupDropHighlight =
                sessionDropTarget?.kind === "group" && sessionDropTarget.groupId === group.id;
              const ws = group.workspace;
              const isWSDragged = ws ? dragWorkspace?.workspace.id === ws.id : false;
              const showWSBefore =
                ws &&
                workspaceDropTarget?.targetWorkspaceId === ws.id &&
                workspaceDropTarget.position === "before" &&
                !isWSDragged;
              const showWSAfter =
                ws &&
                workspaceDropTarget?.targetWorkspaceId === ws.id &&
                workspaceDropTarget.position === "after" &&
                !isWSDragged;

              return (
                <div
                  key={group.id}
                  data-group-drop-id={group.id}
                  data-workspace-group-id={ws?.id}
                  className={`relative mb-2 rounded-[9px] transition-colors duration-100 last:mb-0 ${
                    isGroupDropHighlight ? "bg-accent-tint ring-1 ring-accent/40" : ""
                  } ${isWSDragged ? "opacity-40" : ""}`}
                >
                  {showWSBefore && (
                    <span
                      aria-hidden
                      className="pointer-events-none absolute inset-x-3 -top-0.5 z-30 h-0.5 rounded-full bg-accent"
                    />
                  )}
                  {showWSAfter && (
                    <span
                      aria-hidden
                      className="pointer-events-none absolute inset-x-3 -bottom-0.5 z-30 h-0.5 rounded-full bg-accent"
                    />
                  )}

                  {showGroupHeaders && (
                    <div
                      data-workspace-drag-id={ws?.id}
                      onPointerDown={(e) => {
                        if (!ws || !canDrag || e.button !== 0) return;
                        if ((e.target as HTMLElement).closest("[data-ws-action], input, button")) return;
                        pendingWSDragRef.current = {
                          workspace: ws,
                          startX: e.clientX,
                          startY: e.clientY,
                        };
                      }}
                      className={`group/ws sidebar-copy relative mx-2 mb-0.5 flex h-7.5 items-center justify-between gap-1 rounded-[7px] px-2 ${
                        ws && canDrag ? "cursor-grab active:cursor-grabbing" : ""
                      }`}
                    >
                      {ws && renamingWSID === ws.id ? (
                        <input
                          autoFocus
                          value={renameWSDraft}
                          onChange={(e) => setRenameWSDraft(e.target.value)}
                          onBlur={() => commitWorkspaceRename(ws.id)}
                          onKeyDown={(e) => {
                            e.stopPropagation();
                            if (e.key === "Enter") commitWorkspaceRename(ws.id);
                            if (e.key === "Escape") setRenamingWSID(null);
                          }}
                          className="min-w-0 flex-1 bg-transparent text-[13px] font-medium text-ink outline-none select-text"
                        />
                      ) : (
                        <span
                          onDoubleClick={() => {
                            if (!ws) return;
                            setRenameWSDraft(ws.name);
                            setRenamingWSID(ws.id);
                          }}
                          className="flex min-w-0 flex-1 items-center gap-1.5 text-[13px] font-medium text-ink-2 select-none"
                          title={ws ? `${ws.name} · ${ws.subtitle}` : group.label}
                        >
                          <WorkspaceGlyph
                            isFolderBacked={ws?.isFolderBacked}
                            isGeneral={!ws}
                            className={ws ? "text-accent-ink" : "text-ink-3"}
                          />
                          <span className="truncate">{group.label}</span>
                        </span>
                      )}

                      {!dragSession && !dragWorkspace && renamingWSID !== ws?.id && (
                        <div className="flex shrink-0 items-center gap-0.5">
                          <button
                            type="button"
                            data-ws-action="true"
                            onClick={() => onNewChat(group.workspaceID, ws?.folderPath ?? null)}
                            title={
                              ws
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

                          {ws && (
                            <div data-ws-menu-wrap className="relative">
                              <button
                                type="button"
                                data-ws-action="true"
                                aria-label="Workspace actions"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setOpenMenuWSID((cur) => (cur === ws.id ? null : ws.id));
                                }}
                                className={`flex size-6 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-opacity duration-100 hover:bg-hover-2 hover:text-ink ${
                                  openMenuWSID === ws.id ? "opacity-100" : "opacity-0 group-hover/ws:opacity-100"
                                }`}
                              >
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor">
                                  <circle cx="5" cy="12" r="1.8" />
                                  <circle cx="12" cy="12" r="1.8" />
                                  <circle cx="19" cy="12" r="1.8" />
                                </svg>
                              </button>

                              {openMenuWSID === ws.id && (
                                <div
                                  className="absolute right-0 top-full z-40 mt-1 w-44 rounded-[10px] bg-surface p-1 shadow-raised"
                                  style={{ animation: "pop-in 140ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "top right" }}
                                >
                                  <button
                                    type="button"
                                    data-ws-action="true"
                                    onClick={() => {
                                      setOpenMenuWSID(null);
                                      setRenameWSDraft(ws.name);
                                      setRenamingWSID(ws.id);
                                    }}
                                    className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink hover:bg-hover"
                                  >
                                    {locale === "zh" ? "重命名工作区" : "Rename workspace"}
                                  </button>
                                  <button
                                    type="button"
                                    data-ws-action="true"
                                    onClick={() => {
                                      setOpenMenuWSID(null);
                                      onChooseWorkspaceFolder(ws.id);
                                    }}
                                    className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink hover:bg-hover"
                                  >
                                    {ws.isFolderBacked
                                      ? locale === "zh"
                                        ? "更换关联文件夹…"
                                        : "Change folder…"
                                      : locale === "zh"
                                        ? "关联本地文件夹…"
                                        : "Link local folder…"}
                                  </button>
                                  {ws.isFolderBacked && (
                                    <button
                                      type="button"
                                      data-ws-action="true"
                                      onClick={() => {
                                        setOpenMenuWSID(null);
                                        onUnlinkWorkspaceFolder(ws.id);
                                      }}
                                      className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink-2 hover:bg-hover hover:text-ink"
                                    >
                                      {locale === "zh" ? "取消文件夹关联" : "Unlink folder"}
                                    </button>
                                  )}
                                  <div className="my-1 border-t border-line" />
                                  <button
                                    type="button"
                                    data-ws-action="true"
                                    onClick={() => {
                                      setOpenMenuWSID(null);
                                      onDeleteWorkspace(ws.id);
                                    }}
                                    className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-red hover:bg-red-tint"
                                  >
                                    {locale === "zh" ? "删除工作区" : "Delete workspace"}
                                  </button>
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}

                  {group.sessions.length > 0 ? (
                    group.sessions.map((s) => renderSessionRow(s, group.id))
                  ) : (
                    !collapsed && (
                      <div className="sidebar-copy mx-3 rounded-[7px] px-2 py-1.5 text-[12.5px] text-ink-3">
                        {locale === "zh" ? "拖入会话或点击 + 新建" : "Drag chat here or click +"}
                      </div>
                    )
                  )}
                </div>
              );
            })}

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

      {/* Lightweight floating drag ghost */}
      {(dragSession || dragWorkspace) && (
        <div
          className="pointer-events-none fixed z-50 flex max-w-[210px] items-center gap-1.5 rounded-[8px] bg-surface px-2.5 py-1.5 text-[13px] font-medium text-ink shadow-overlay"
          style={{
            left: (dragSession?.x ?? dragWorkspace?.x ?? 0) + 12,
            top: (dragSession?.y ?? dragWorkspace?.y ?? 0) - 14,
          }}
        >
          {dragWorkspace && <WorkspaceGlyph isFolderBacked={dragWorkspace.workspace.isFolderBacked} className="text-accent-ink" />}
          <span className="truncate">{dragSession?.session.title ?? dragWorkspace?.workspace.name}</span>
        </div>
      )}
    </aside>
  );
}
