import { memo, useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";
import GlideMenu from "./GlideMenu";
import SidebarMeetingGroup from "./SidebarMeetingGroup";
import type { MeetingRoomSessionSummary, SessionSummary, WorkspaceOption } from "../types";

/* ─────────────────────────────────────────────────────────
 * SIDEBAR NAV — Hierarchical Workspaces & Sessions
 *   · Collapsible Projects/Workspaces + General sessions
 *   · Pointer-event drag & drop for sessions & workspaces
 *   · GPU-friendly collapse (fixed-pos toggle, opacity-only copy fade)
 * ───────────────────────────────────────────────────────── */

const GENERAL_GROUP_ID = "__general__";
const COLLAPSED_GROUPS_STORAGE_KEY = "cot.sidebar.collapsedGroups.v1";

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
    // Ignore storage quota or private-mode restrictions
  }
}

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
  meetingRoomActive?: boolean;
  meetingRoomIsConvening?: boolean;
  meetingRoomSessions?: MeetingRoomSessionSummary[];
  activeMeetingSessionID?: string;
  onOpenMeetingRoom?: () => void;
  onNewMeetingSession?: () => void;
  onSelectMeetingSession?: (id: string) => void;
  onRenameMeetingSession?: (id: string, title: string) => void;
  onDeleteMeetingSession?: (id: string) => void;
  onTogglePinMeetingSession?: (id: string) => void;
};

type SessionGroup = {
  id: string;
  workspaceID: string | null;
  workspace: WorkspaceOption | null;
  label: string;
  sessions: SessionSummary[];
};

type SessionDragState = { session: SessionSummary; sourceGroupId: string; x: number; y: number };
type SessionDropTarget =
  | { kind: "row"; groupId: string; targetSessionId: string; position: "before" | "after" }
  | { kind: "group"; groupId: string };
type WorkspaceDragState = { workspace: WorkspaceOption; x: number; y: number };
type WorkspaceDropTarget = { targetWorkspaceId: string; position: "before" | "after" };

function WorkspaceGlyph({
  isFolderBacked,
  isGeneral,
  expanded = false,
  className = "",
}: {
  isFolderBacked?: boolean;
  isGeneral?: boolean;
  expanded?: boolean;
  className?: string;
}) {
  if (isGeneral) {
    return (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
      </svg>
    );
  }
  if (isFolderBacked) {
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
        {expanded ? (
          <path d="M3 7a2 2 0 0 1 2-2h4.2l1.8 2H19a2 2 0 0 1 2 2v1.5M3 11.5h18l-1.6 6.5a2 2 0 0 1-1.94 1.5H5.54a2 2 0 0 1-1.94-1.5L2 11.5z" />
        ) : (
          <path d="M3 7a2 2 0 0 1 2-2h4.2l1.8 2H19a2 2 0 0 1 2 2v8.5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
        )}
      </svg>
    );
  }
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${className}`}>
      <path d="M3 7.5a2 2 0 0 1 2-2h4.2l1.8 2H19a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      {expanded && <path d="M7.5 13.5h9" strokeOpacity="0.65" />}
    </svg>
  );
}

function computeSessionDropTarget(container: HTMLElement | null, clientX: number, clientY: number): SessionDropTarget | null {
  if (!container) return null;
  const cRect = container.getBoundingClientRect();
  if (clientX < cRect.left - 28 || clientX > cRect.right + 28) return null;

  for (const el of container.querySelectorAll<HTMLElement>("[data-session-id]")) {
    const r = el.getBoundingClientRect();
    if (clientY >= r.top - 4 && clientY <= r.bottom + 4) {
      const targetSessionId = el.dataset.sessionId;
      const groupId = el.dataset.groupId;
      if (!targetSessionId || !groupId) continue;
      return { kind: "row", groupId, targetSessionId, position: clientY < r.top + r.height / 2 ? "before" : "after" };
    }
  }
  for (const el of container.querySelectorAll<HTMLElement>("[data-group-drop-id]")) {
    const r = el.getBoundingClientRect();
    if (clientY >= r.top - 2 && clientY <= r.bottom + 2) {
      const groupId = el.dataset.groupDropId;
      if (groupId) return { kind: "group", groupId };
    }
  }
  return null;
}

function computeWorkspaceDropTarget(container: HTMLElement | null, clientX: number, clientY: number): WorkspaceDropTarget | null {
  if (!container) return null;
  const cRect = container.getBoundingClientRect();
  if (clientX < cRect.left - 28 || clientX > cRect.right + 28) return null;

  for (const el of container.querySelectorAll<HTMLElement>("[data-workspace-group-id]")) {
    const r = el.getBoundingClientRect();
    if (clientY >= r.top - 4 && clientY <= r.bottom + 4) {
      const targetWorkspaceId = el.dataset.workspaceGroupId;
      if (!targetWorkspaceId) continue;
      return { targetWorkspaceId, position: clientY < r.top + r.height / 2 ? "before" : "after" };
    }
  }
  return null;
}

function resolveMovedSessionPin(
  remaining: SessionSummary[],
  targetIdx: number,
  position: "before" | "after",
  currentPinned?: boolean,
): boolean | undefined {
  const targetSession = targetIdx >= 0 ? remaining[targetIdx] : undefined;
  if (!targetSession) return currentPinned;
  if (targetSession.isPinned && position === "before") return true;
  if (!targetSession.isPinned && position === "after") return false;
  if (targetSession.isPinned && position === "after") {
    return remaining[targetIdx + 1]?.isPinned ? true : currentPinned;
  }
  const prevNeighbor = targetIdx > 0 ? remaining[targetIdx - 1] : undefined;
  return prevNeighbor && !prevNeighbor.isPinned ? false : currentPinned;
}

function useSidebarDragAndDrop(params: {
  listContainerRef: MutableRefObject<HTMLDivElement | null>;
  groupedSessions: SessionGroup[];
  availableWorkspaces: WorkspaceOption[];
  onMoveSession: SidebarNavProps["onMoveSession"];
  onReorderWorkspaces: SidebarNavProps["onReorderWorkspaces"];
  setGroupExpanded: (groupId: string, expanded: boolean) => void;
  setOpenMenuWSID: (id: string | null) => void;
}) {
  const { listContainerRef, groupedSessions, availableWorkspaces, onMoveSession, onReorderWorkspaces, setGroupExpanded, setOpenMenuWSID } = params;
  const [dragSession, setDragSession] = useState<SessionDragState | null>(null);
  const [sessionDropTarget, setSessionDropTarget] = useState<SessionDropTarget | null>(null);
  const [dragWorkspace, setDragWorkspace] = useState<WorkspaceDragState | null>(null);
  const [workspaceDropTarget, setWorkspaceDropTarget] = useState<WorkspaceDropTarget | null>(null);

  const suppressClickRef = useRef(false);
  const pendingSessionDragRef = useRef<{ session: SessionSummary; sourceGroupId: string; startX: number; startY: number } | null>(null);
  const activeSessionDragRef = useRef<SessionDragState | null>(null);
  const sessionDropTargetRef = useRef<SessionDropTarget | null>(null);
  const pendingWSDragRef = useRef<{ workspace: WorkspaceOption; startX: number; startY: number } | null>(null);
  const activeWSDragRef = useRef<WorkspaceDragState | null>(null);
  const workspaceDropTargetRef = useRef<WorkspaceDropTarget | null>(null);

  const latestRef = useRef({ groupedSessions, availableWorkspaces, onMoveSession, onReorderWorkspaces, setGroupExpanded, setOpenMenuWSID });
  latestRef.current = { groupedSessions, availableWorkspaces, onMoveSession, onReorderWorkspaces, setGroupExpanded, setOpenMenuWSID };

  useEffect(() => {
    const onPointerMove = (e: PointerEvent) => {
      const pendingSess = pendingSessionDragRef.current;
      if (pendingSess && !activeSessionDragRef.current && Math.hypot(e.clientX - pendingSess.startX, e.clientY - pendingSess.startY) >= 5) {
        suppressClickRef.current = true;
        window.getSelection()?.removeAllRanges();
        latestRef.current.setOpenMenuWSID(null);
        const started: SessionDragState = { session: pendingSess.session, sourceGroupId: pendingSess.sourceGroupId, x: e.clientX, y: e.clientY };
        activeSessionDragRef.current = started;
        setDragSession(started);
      }
      if (activeSessionDragRef.current) {
        e.preventDefault();
        const updated = { ...activeSessionDragRef.current, x: e.clientX, y: e.clientY };
        activeSessionDragRef.current = updated;
        setDragSession(updated);
        const drop = computeSessionDropTarget(listContainerRef.current, e.clientX, e.clientY);
        sessionDropTargetRef.current = drop;
        setSessionDropTarget(drop);
        return;
      }
      const pendingWS = pendingWSDragRef.current;
      if (pendingWS && !activeWSDragRef.current && Math.hypot(e.clientX - pendingWS.startX, e.clientY - pendingWS.startY) >= 5) {
        suppressClickRef.current = true;
        window.getSelection()?.removeAllRanges();
        latestRef.current.setOpenMenuWSID(null);
        const started: WorkspaceDragState = { workspace: pendingWS.workspace, x: e.clientX, y: e.clientY };
        activeWSDragRef.current = started;
        setDragWorkspace(started);
      }
      if (activeWSDragRef.current) {
        e.preventDefault();
        const updated = { ...activeWSDragRef.current, x: e.clientX, y: e.clientY };
        activeWSDragRef.current = updated;
        setDragWorkspace(updated);
        const drop = computeWorkspaceDropTarget(listContainerRef.current, e.clientX, e.clientY);
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
        setTimeout(() => { suppressClickRef.current = false; }, 60);
      }

      const { groupedSessions: groups, availableWorkspaces: wss, onMoveSession: moveSess, onReorderWorkspaces: reorderWS, setGroupExpanded: expandGroup } = latestRef.current;

      if (activeSess && dropSess) {
        const targetGroup = groups.find((g) => g.id === dropSess.groupId);
        if (!targetGroup) return;
        const remaining = targetGroup.sessions.filter((s) => s.id !== activeSess.session.id);
        if (dropSess.kind === "row") {
          if (dropSess.targetSessionId === activeSess.session.id && dropSess.groupId === activeSess.sourceGroupId) return;
          const targetIdx = remaining.findIndex((s) => s.id === dropSess.targetSessionId);
          const insertAt = targetIdx === -1 ? remaining.length : dropSess.position === "before" ? targetIdx : targetIdx + 1;
          const nextList = remaining.slice();
          nextList.splice(insertAt, 0, activeSess.session);
          const nextPinned = resolveMovedSessionPin(remaining, targetIdx, dropSess.position, activeSess.session.isPinned);
          moveSess(activeSess.session.id, dropSess.groupId === GENERAL_GROUP_ID ? null : dropSess.groupId, nextList.map((s) => s.id), nextPinned);
        } else {
          const nextList = remaining.slice();
          if (activeSess.session.isPinned) {
            const lastPinnedIdx = nextList.reduce((acc, item, i) => (item.isPinned ? i : acc), -1);
            nextList.splice(lastPinnedIdx + 1, 0, activeSess.session);
          } else {
            nextList.push(activeSess.session);
          }
          moveSess(activeSess.session.id, dropSess.groupId === GENERAL_GROUP_ID ? null : dropSess.groupId, nextList.map((s) => s.id), activeSess.session.isPinned);
          if (dropSess.groupId !== GENERAL_GROUP_ID) expandGroup(dropSess.groupId, true);
        }
        return;
      }

      if (activeWS && dropWS && dropWS.targetWorkspaceId !== activeWS.workspace.id) {
        const ids = wss.map((w) => w.id).filter((id) => id !== activeWS.workspace.id);
        const idx = ids.indexOf(dropWS.targetWorkspaceId);
        if (idx === -1) return;
        ids.splice(dropWS.position === "before" ? idx : idx + 1, 0, activeWS.workspace.id);
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
  }, [listContainerRef]);

  return {
    dragSession,
    sessionDropTarget,
    dragWorkspace,
    workspaceDropTarget,
    suppressClickRef,
    pendingSessionDragRef,
    pendingWSDragRef,
  };
}

const SidebarSessionRow = memo(function SidebarSessionRow(props: {
  session: SessionSummary;
  groupId: string;
  nested: boolean;
  active: boolean;
  isRenaming: boolean;
  renameDraft: string;
  collapsed: boolean;
  canDrag: boolean;
  isBeingDragged: boolean;
  showInsertBefore: boolean;
  showInsertAfter: boolean;
  locale: "zh" | "en";
  onSelect: (id: string) => void;
  onStartRename: (id: string, title: string) => void;
  onRenameDraftChange: (value: string) => void;
  onCommitRename: (id: string) => void;
  onCancelRename: () => void;
  onTogglePin: (id: string) => void;
  onDelete: (id: string) => void;
  onPointerStart: (session: SessionSummary, groupId: string, x: number, y: number) => void;
  suppressClickRef: MutableRefObject<boolean>;
}) {
  const {
    session, groupId, nested, active, isRenaming, renameDraft, collapsed, canDrag,
    isBeingDragged, showInsertBefore, showInsertAfter, locale,
    onSelect, onStartRename, onRenameDraftChange, onCommitRename, onCancelRename,
    onTogglePin, onDelete, onPointerStart, suppressClickRef,
  } = props;

  return (
    <div
      data-row
      data-session-id={session.id}
      data-group-id={groupId}
      role="button"
      tabIndex={0}
      title={session.workspaceName ? `${session.title} · ${session.workspaceName}` : session.title}
      onPointerDown={(e) => {
        if (!canDrag || e.button !== 0) return;
        if ((e.target as HTMLElement).closest("[data-row-action], input")) return;
        onPointerStart(session, groupId, e.clientX, e.clientY);
      }}
      onClick={() => {
        if (suppressClickRef.current || isRenaming) return;
        onSelect(session.id);
      }}
      onDoubleClick={() => {
        if (!collapsed) onStartRename(session.id, session.title);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !isRenaming) onSelect(session.id);
      }}
      className={`group/item relative z-10 flex items-center gap-1.5 rounded-[7px] px-2 transition-[background-color,opacity] duration-100 select-none ${
        nested ? "h-[30px] w-full" : "mx-2 h-8"
      } ${isBeingDragged ? "opacity-35" : active ? "bg-hover-2" : ""} ${
        canDrag ? "cursor-grab active:cursor-grabbing" : "cursor-pointer"
      }`}
    >
      {showInsertBefore && (
        <span aria-hidden className="pointer-events-none absolute inset-x-1 -top-0.5 z-30 h-0.5 rounded-full bg-accent">
          <span className="absolute -left-0.5 -top-[3px] size-2 rounded-full bg-accent" />
        </span>
      )}
      {showInsertAfter && (
        <span aria-hidden className="pointer-events-none absolute inset-x-1 -bottom-0.5 z-30 h-0.5 rounded-full bg-accent">
          <span className="absolute -left-0.5 -top-[3px] size-2 rounded-full bg-accent" />
        </span>
      )}
      {session.isPinned && <span className="size-1.5 shrink-0 rounded-full bg-accent" />}
      {isRenaming ? (
        <input
          autoFocus
          value={renameDraft}
          onChange={(e) => onRenameDraftChange(e.target.value)}
          onBlur={() => onCommitRename(session.id)}
          onKeyDown={(e) => {
            e.stopPropagation();
            if (e.key === "Enter") onCommitRename(session.id);
            if (e.key === "Escape") onCancelRename();
          }}
          className="min-w-0 flex-1 bg-transparent text-[13px] font-medium text-ink outline-none select-text"
        />
      ) : (
        <span className={`min-w-0 flex-1 truncate text-[13px] ${active ? "font-medium text-ink" : "font-normal text-ink-2 group-hover/item:text-ink"}`}>
          {session.title}
        </span>
      )}
      {!isRenaming && !collapsed && !isBeingDragged && (
        <div className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity duration-100 group-hover/item:opacity-100">
          <button
            type="button"
            data-row-action="true"
            aria-label={session.isPinned ? "Unpin" : "Pin"}
            onClick={(e) => { e.stopPropagation(); onTogglePin(session.id); }}
            className="flex size-5.5 items-center justify-center rounded-[5px] text-ink-3 hover:bg-hover hover:text-ink"
            title={session.isPinned ? (locale === "zh" ? "取消置顶" : "Unpin") : locale === "zh" ? "置顶" : "Pin"}
          >
            <svg width="11.5" height="11.5" viewBox="0 0 24 24" fill={session.isPinned ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2">
              <path d="M12 17v5M5 9l7-7 7 7-3 3v4H8v-4z" />
            </svg>
          </button>
          <button
            type="button"
            data-row-action="true"
            aria-label="Delete"
            onClick={(e) => { e.stopPropagation(); onDelete(session.id); }}
            className="flex size-5.5 items-center justify-center rounded-[5px] text-ink-3 hover:bg-hover hover:text-red"
            title={locale === "zh" ? "删除" : "Delete"}
          >
            <svg width="11.5" height="11.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
              <path d="M18 6L6 18M6 6l12 12" />
            </svg>
          </button>
        </div>
      )}
    </div>
  );
});

const SidebarWorkspaceMenu = memo(function SidebarWorkspaceMenu(props: {
  ws: WorkspaceOption;
  locale: "zh" | "en";
  onRename: () => void;
  onChooseFolder: () => void;
  onUnlinkFolder: () => void;
  onDelete: () => void;
}) {
  const { ws, locale, onRename, onChooseFolder, onUnlinkFolder, onDelete } = props;
  return (
    <div
      className="absolute right-0 top-full z-40 mt-1 w-44 rounded-[10px] bg-surface p-1 shadow-raised"
      style={{ animation: "pop-in 140ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "top right" }}
    >
      <button type="button" data-ws-action="true" onClick={onRename} className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink hover:bg-hover">
        {locale === "zh" ? "重命名工作区" : "Rename workspace"}
      </button>
      <button type="button" data-ws-action="true" onClick={onChooseFolder} className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink hover:bg-hover">
        {ws.isFolderBacked ? (locale === "zh" ? "更换关联文件夹…" : "Change folder…") : locale === "zh" ? "关联本地文件夹…" : "Link local folder…"}
      </button>
      {ws.isFolderBacked && (
        <button type="button" data-ws-action="true" onClick={onUnlinkFolder} className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-ink-2 hover:bg-hover hover:text-ink">
          {locale === "zh" ? "取消文件夹关联" : "Unlink folder"}
        </button>
      )}
      <div className="my-1 border-t border-line" />
      <button type="button" data-ws-action="true" onClick={onDelete} className="flex h-8 w-full items-center rounded-[7px] px-2.5 text-left text-[13px] text-red hover:bg-red-tint">
        {locale === "zh" ? "删除工作区" : "Delete workspace"}
      </button>
    </div>
  );
});

const SidebarWorkspaceGroup = memo(function SidebarWorkspaceGroup(props: {
  group: SessionGroup;
  expanded: boolean;
  activeSessionID: string;
  isGroupDropHighlight: boolean;
  isWSDragged: boolean;
  showWSBefore: boolean;
  showWSAfter: boolean;
  menuOpen: boolean;
  isRenamingWS: boolean;
  renameWSDraft: string;
  canDrag: boolean;
  isDraggingAny: boolean;
  locale: "zh" | "en";
  onToggleExpand: () => void;
  onStartRenameWS: () => void;
  onRenameWSDraftChange: (v: string) => void;
  onCommitRenameWS: () => void;
  onCancelRenameWS: () => void;
  onToggleMenu: () => void;
  onCloseMenu: () => void;
  onNewChatInWS: () => void;
  onChooseFolder: () => void;
  onUnlinkFolder: () => void;
  onDeleteWS: () => void;
  onPointerStartWS: (ws: WorkspaceOption, x: number, y: number) => void;
  suppressClickRef: MutableRefObject<boolean>;
  renderChildRow: (s: SessionSummary) => React.ReactNode;
}) {
  const {
    group, expanded, activeSessionID, isGroupDropHighlight, isWSDragged,
    showWSBefore, showWSAfter, menuOpen, isRenamingWS, renameWSDraft,
    canDrag, isDraggingAny, locale, onToggleExpand, onStartRenameWS,
    onRenameWSDraftChange, onCommitRenameWS, onCancelRenameWS, onToggleMenu,
    onCloseMenu, onNewChatInWS, onChooseFolder, onUnlinkFolder, onDeleteWS,
    onPointerStartWS, suppressClickRef, renderChildRow,
  } = props;
  const ws = group.workspace!;
  const containsActive = group.sessions.some((s) => s.id === activeSessionID);

  return (
    <div
      data-group-drop-id={group.id}
      data-workspace-group-id={ws.id}
      className={`relative mb-0.5 rounded-[8px] transition-colors duration-100 ${
        isGroupDropHighlight ? "bg-accent-tint/80 ring-1 ring-accent/45" : ""
      } ${isWSDragged ? "opacity-40" : ""}`}
    >
      {showWSBefore && <span aria-hidden className="pointer-events-none absolute inset-x-3 -top-0.5 z-30 h-0.5 rounded-full bg-accent" />}
      {showWSAfter && <span aria-hidden className="pointer-events-none absolute inset-x-3 -bottom-0.5 z-30 h-0.5 rounded-full bg-accent" />}

      <div
        data-workspace-drag-id={ws.id}
        onPointerDown={(e) => {
          if (!canDrag || e.button !== 0) return;
          if ((e.target as HTMLElement).closest("[data-ws-action], input, button")) return;
          onPointerStartWS(ws, e.clientX, e.clientY);
        }}
        onClick={(e) => {
          if (suppressClickRef.current || isRenamingWS) return;
          if ((e.target as HTMLElement).closest("[data-ws-action], input, button")) return;
          onToggleExpand();
        }}
        className="group/ws relative mx-2 flex h-8 cursor-pointer items-center gap-1 rounded-[7px] px-1.5 transition-colors duration-100 hover:bg-hover active:cursor-grabbing"
      >
        <span className={`flex size-4 shrink-0 items-center justify-center text-ink-3 transition-transform duration-150 ${expanded ? "rotate-90" : "rotate-0"} ${group.sessions.length === 0 && !expanded ? "opacity-45" : "opacity-85 group-hover/ws:text-ink-2"}`}>
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 6l6 6-6 6" />
          </svg>
        </span>

        {isRenamingWS ? (
          <input
            autoFocus
            value={renameWSDraft}
            onChange={(e) => onRenameWSDraftChange(e.target.value)}
            onBlur={onCommitRenameWS}
            onKeyDown={(e) => {
              e.stopPropagation();
              if (e.key === "Enter") onCommitRenameWS();
              if (e.key === "Escape") onCancelRenameWS();
            }}
            className="min-w-0 flex-1 bg-transparent text-[13px] font-medium text-ink outline-none select-text"
          />
        ) : (
          <span
            onDoubleClick={(e) => { e.stopPropagation(); onStartRenameWS(); }}
            className={`flex min-w-0 flex-1 items-center gap-1.5 text-[13px] font-medium select-none ${containsActive ? "text-ink" : "text-ink-2 group-hover/ws:text-ink"}`}
            title={ws.subtitle ? `${ws.name} · ${ws.subtitle}` : ws.name}
          >
            <WorkspaceGlyph isFolderBacked={ws.isFolderBacked} expanded={expanded && group.sessions.length > 0} className={containsActive ? "text-ink" : "text-ink-3 group-hover/ws:text-ink-2"} />
            <span className="truncate">{group.label}</span>
          </span>
        )}

        {!isDraggingAny && !isRenamingWS && (
          <div className="relative flex shrink-0 items-center">
            <div className={`flex items-center gap-1.5 pr-1 transition-opacity duration-100 ${menuOpen ? "pointer-events-none opacity-0" : "opacity-100 group-hover/ws:pointer-events-none group-hover/ws:opacity-0"}`}>
              {!expanded && containsActive && <span className="size-1.5 rounded-full bg-accent" />}
              {group.sessions.length > 0 && <span className="text-[11.5px] tabular-nums text-ink-3">{group.sessions.length}</span>}
            </div>
            <div className={`absolute right-0 flex items-center gap-0.5 transition-opacity duration-100 ${menuOpen ? "opacity-100" : "pointer-events-none opacity-0 group-hover/ws:pointer-events-auto group-hover/ws:opacity-100"}`}>
              <button
                type="button"
                data-ws-action="true"
                onClick={(e) => { e.stopPropagation(); onNewChatInWS(); }}
                title={locale === "zh" ? `在「${group.label}」新建会话` : `New session in ${group.label}`}
                className="flex size-5.5 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink"
              >
                <svg width="12.5" height="12.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </button>
              <div data-ws-menu-wrap className="relative">
                <button
                  type="button"
                  data-ws-action="true"
                  aria-label="Workspace actions"
                  onClick={(e) => { e.stopPropagation(); onToggleMenu(); }}
                  className="flex size-5.5 shrink-0 items-center justify-center rounded-[5px] text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink"
                >
                  <svg width="12.5" height="12.5" viewBox="0 0 24 24" fill="currentColor">
                    <circle cx="5" cy="12" r="1.8" />
                    <circle cx="12" cy="12" r="1.8" />
                    <circle cx="19" cy="12" r="1.8" />
                  </svg>
                </button>
                {menuOpen && (
                  <SidebarWorkspaceMenu
                    ws={ws}
                    locale={locale}
                    onRename={() => { onCloseMenu(); onStartRenameWS(); }}
                    onChooseFolder={() => { onCloseMenu(); onChooseFolder(); }}
                    onUnlinkFolder={() => { onCloseMenu(); onUnlinkFolder(); }}
                    onDelete={() => { onCloseMenu(); onDeleteWS(); }}
                  />
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {expanded && (
        <div className="relative ml-[18px] mr-2 mt-0.5 mb-1.5 flex flex-col gap-0.5 border-l border-line-strong/80 pl-2">
          {group.sessions.length > 0 ? (
            group.sessions.map((s) => renderChildRow(s))
          ) : (
            <button
              type="button"
              onClick={onNewChatInWS}
              className="flex h-7 w-full items-center gap-1.5 rounded-[6px] px-2 text-left text-[12px] text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink-2"
            >
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span>{locale === "zh" ? "新建会话" : "New chat"}</span>
            </button>
          )}
        </div>
      )}
    </div>
  );
});

const SidebarPrimaryHeader = memo(function SidebarPrimaryHeader(props: {
  botName: string;
  botAvatarDataURL?: string | null;
  collapsed: boolean;
  locale: "zh" | "en";
  activeWorkspaceID?: string | null;
  activeWorkspacePath?: string | null;
  meetingRoomActive: boolean;
  meetingRoomIsConvening: boolean;
  onToggleCollapse: () => void;
  onNewChat: (workspaceID?: string | null, workspacePath?: string | null) => void;
  onStartCreateWorkspace: () => void;
  onOpenMeetingRoom?: () => void;
}) {
  const {
    botName, botAvatarDataURL, collapsed, locale, activeWorkspaceID, activeWorkspacePath,
    meetingRoomActive, meetingRoomIsConvening, onToggleCollapse, onNewChat,
    onStartCreateWorkspace, onOpenMeetingRoom,
  } = props;

  return (
    <>
      <div className="mb-2 flex h-9 shrink-0 items-center gap-1.5 px-[9px]">
        <button
          type="button"
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          onClick={onToggleCollapse}
          className="flex size-8 shrink-0 items-center justify-center rounded-[8px] text-ink-3 transition-colors duration-150 hover:bg-hover-2 hover:text-ink"
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

        <div className="sidebar-copy flex min-w-0 flex-1 items-center gap-2 rounded-[8px] px-1 py-1">
          {botAvatarDataURL ? (
            <img src={botAvatarDataURL} alt={botName} className="size-6 shrink-0 rounded-[7px] object-cover shadow-hairline" />
          ) : (
            <span className="flex size-6 shrink-0 items-center justify-center rounded-[7px] bg-ink text-[13px] font-semibold text-surface">
              {botName.slice(0, 1)}
            </span>
          )}
          <span className="truncate text-[14px] font-semibold text-ink">{botName}</span>
        </div>
      </div>

      <GlideMenu rowSelector="[data-row]" highlightClassName="sidebar-glide-highlight rounded-[8px] bg-hover-2" className="flex flex-col gap-0.5">
        <button
          data-row
          type="button"
          onClick={() => onNewChat(activeWorkspaceID ?? null, activeWorkspacePath ?? null)}
          title={locale === "zh" ? "新建会话" : "New session"}
          className="sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-colors duration-150 active:scale-[0.98]"
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
          onClick={onStartCreateWorkspace}
          title={locale === "zh" ? "新建逻辑工作区分区" : "New logical workspace"}
          className="sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-colors duration-150 active:scale-[0.98]"
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

        {onOpenMeetingRoom && collapsed && (
          <button
            data-row
            type="button"
            onClick={onOpenMeetingRoom}
            title={locale === "zh" ? "会议室" : "Meeting Room"}
            className={`sidebar-row relative z-10 mx-2 flex h-8.5 items-center rounded-[8px] px-2 text-left transition-colors duration-150 active:scale-[0.98] ${
              meetingRoomActive ? "bg-surface shadow-hairline" : ""
            }`}
          >
            <span className={`flex size-4.5 shrink-0 items-center justify-center ${meetingRoomActive ? "text-ink" : "text-ink-2"}`}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="9" cy="8" r="3" />
                <circle cx="17" cy="9" r="2.5" />
                <path d="M3.5 19a5.5 5.5 0 0 1 11 0" />
                <path d="M14.5 18.5a4.5 4.5 0 0 1 6 0" />
              </svg>
            </span>
            <span className={`sidebar-copy ml-2 flex-1 truncate text-[13.5px] font-medium ${meetingRoomActive ? "text-ink" : "text-ink-2"}`}>
              {locale === "zh" ? "会议室" : "Meeting Room"}
            </span>
            {meetingRoomIsConvening && !collapsed && (
              <span className="sidebar-copy size-1.5 shrink-0 rounded-full bg-accent" />
            )}
          </button>
        )}
      </GlideMenu>
    </>
  );
});

const SidebarSearchHeader = memo(function SidebarSearchHeader(props: {
  searchOpen: boolean;
  query: string;
  hasWorkspaces: boolean;
  locale: "zh" | "en";
  searchRef: MutableRefObject<HTMLInputElement | null>;
  onOpenSearch: () => void;
  onCloseSearch: () => void;
  onQueryChange: (v: string) => void;
}) {
  const { searchOpen, query, hasWorkspaces, locale, searchRef, onOpenSearch, onCloseSearch, onQueryChange } = props;
  return (
    <div className="relative mx-2 mb-1.5 h-7">
      <div
        aria-hidden={searchOpen}
        className={`absolute inset-0 flex items-center gap-1 px-2 text-[12px] font-medium text-ink-3 transition-opacity duration-150 ${
          searchOpen ? "pointer-events-none opacity-0" : "opacity-100"
        }`}
      >
        <span>{hasWorkspaces ? (locale === "zh" ? "工作区" : "Projects") : locale === "zh" ? "会话列表" : "Sessions"}</span>
      </div>
      <button
        type="button"
        aria-label="Search sessions"
        onClick={onOpenSearch}
        className={`absolute right-0 top-0 z-10 flex size-7 items-center justify-center rounded-[7px] text-ink-3 transition-opacity duration-150 hover:bg-hover-2 hover:text-ink ${
          searchOpen ? "pointer-events-none opacity-0" : "opacity-100"
        }`}
      >
        <svg width="13.5" height="13.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="11" cy="11" r="7" />
          <path d="M21 21l-4.3-4.3" />
        </svg>
      </button>
      <div
        className={`absolute right-0 top-0 z-20 flex h-7 items-center overflow-hidden rounded-[7px] bg-surface text-ink-3 shadow-hairline transition-[width,opacity] duration-150 ${
          searchOpen ? "pointer-events-auto opacity-100" : "pointer-events-none opacity-0"
        }`}
        style={{ width: searchOpen ? "100%" : 28 }}
      >
        <span className="ml-2 flex shrink-0 items-center justify-center">
          <svg width="12.5" height="12.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" />
            <path d="M21 21l-4.3-4.3" />
          </svg>
        </span>
        <input
          ref={searchRef}
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Escape") onCloseSearch(); }}
          placeholder={locale === "zh" ? "搜索" : "Search"}
          className="ml-1.5 min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3 select-text"
        />
        <button type="button" aria-label="Close search" onClick={onCloseSearch} className="flex size-6.5 shrink-0 items-center justify-center text-ink-3 hover:text-ink">
          <svg width="11.5" height="11.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>
  );
});

const SidebarGeneralGroup = memo(function SidebarGeneralGroup(props: {
  group: SessionGroup;
  hasWorkspaces: boolean;
  isGroupDropHighlight: boolean;
  isDraggingAny: boolean;
  locale: "zh" | "en";
  onNewChat: () => void;
  renderRow: (s: SessionSummary) => React.ReactNode;
}) {
  const { group, hasWorkspaces, isGroupDropHighlight, isDraggingAny, locale, onNewChat, renderRow } = props;
  return (
    <div
      data-group-drop-id={group.id}
      className={`relative rounded-[8px] transition-colors duration-100 ${
        isGroupDropHighlight ? "bg-accent-tint/80 ring-1 ring-accent/45" : ""
      }`}
    >
      {hasWorkspaces && (
        <>
          <div className="mx-3 my-2 border-t border-line" />
          <div className="group/general mx-2 mb-1 flex h-6 items-center justify-between px-2">
            <span className="text-[11.5px] font-medium text-ink-3 select-none">{group.label}</span>
            {!isDraggingAny && (
              <button
                type="button"
                onClick={onNewChat}
                title={locale === "zh" ? "新建通用会话" : "New general session"}
                className="flex size-5.5 items-center justify-center rounded-[5px] text-ink-3 opacity-60 transition-opacity duration-100 hover:bg-hover-2 hover:text-ink hover:opacity-100"
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </button>
            )}
          </div>
        </>
      )}
      {group.sessions.length > 0 ? (
        <div className="flex flex-col gap-0.5">{group.sessions.map(renderRow)}</div>
      ) : (
        hasWorkspaces && (
          <div className="mx-2 px-2 py-1 text-[12px] text-ink-3/70 select-none">{locale === "zh" ? "暂无会话" : "No chats"}</div>
        )
      )}
    </div>
  );
});

const SidebarFooterSettings = memo(function SidebarFooterSettings({
  locale,
  onOpenSettings,
}: {
  locale: "zh" | "en";
  onOpenSettings: () => void;
}) {
  return (
    <div className="sidebar-copy mx-2 mt-2 border-t border-line pt-2">
      <button
        type="button"
        onClick={onOpenSettings}
        className="flex h-8.5 w-full items-center justify-center gap-1.5 rounded-control bg-hover-2 text-[13px] font-medium text-ink transition-colors duration-150 hover:bg-line-strong active:scale-[0.98]"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
        </svg>
        {locale === "zh" ? "助手设置" : "Agent Settings"}
      </button>
    </div>
  );
});

function useSidebarGroups(
  sessions: SessionSummary[],
  availableWorkspaces: WorkspaceOption[],
  query: string,
  locale: "zh" | "en",
) {
  const visibleSessions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sessions;
    return sessions.filter((s) => s.title.toLowerCase().includes(q) || (s.workspaceName && s.workspaceName.toLowerCase().includes(q)));
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
      groups.push({ id: ws.id, workspaceID: ws.id, workspace: ws, label: ws.name, sessions: list });
    }
    if (!isSearching || general.length > 0) {
      groups.push({ id: GENERAL_GROUP_ID, workspaceID: null, workspace: null, label: locale === "zh" ? "通用会话" : "General", sessions: general });
    }
    return groups;
  }, [visibleSessions, availableWorkspaces, query, locale]);

  return { visibleSessions, groupedSessions };
}

function SidebarNav({
  botName, botAvatarDataURL, sessions, activeSessionID, availableWorkspaces, collapsed, locale,
  onToggleCollapse, onNewChat, onCreateWorkspace, onRenameWorkspace, onDeleteWorkspace,
  onChooseWorkspaceFolder, onUnlinkWorkspaceFolder, onReorderWorkspaces, onMoveSession,
  onSelectSession, onDeleteSession, onRenameSession, onTogglePinSession, onOpenSettings,
  meetingRoomActive = false, meetingRoomIsConvening = false, meetingRoomSessions = [],
  activeMeetingSessionID = "", onOpenMeetingRoom, onNewMeetingSession,
  onSelectMeetingSession, onRenameMeetingSession, onDeleteMeetingSession, onTogglePinMeetingSession,
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
  const [collapsedGroupMap, setCollapsedGroupMap] = useState<Record<string, boolean>>(() => loadCollapsedGroups());

  const searchRef = useRef<HTMLInputElement>(null);
  const listContainerRef = useRef<HTMLDivElement>(null);

  useEffect(() => { if (searchOpen) searchRef.current?.focus(); }, [searchOpen]);
  useEffect(() => {
    if (!collapsed) return;
    if (searchOpen) setSearchOpen(false);
    if (query) setQuery("");
    if (creatingWorkspace) setCreatingWorkspace(false);
    if (openMenuWSID !== null) setOpenMenuWSID(null);
  }, [collapsed, searchOpen, query, creatingWorkspace, openMenuWSID]);
  useEffect(() => {
    if (!openMenuWSID) return;
    const onDown = (e: PointerEvent) => {
      if (!(e.target as HTMLElement | null)?.closest("[data-ws-menu-wrap]")) setOpenMenuWSID(null);
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [openMenuWSID]);

  const activeSession = sessions.find((s) => s.id === activeSessionID);
  const setGroupExpanded = useCallback((groupId: string, expanded: boolean) => {
    setCollapsedGroupMap((prev) => {
      const collapsedFlag = !expanded;
      if (prev[groupId] === collapsedFlag) return prev;
      const next = { ...prev, [groupId]: collapsedFlag };
      saveCollapsedGroups(next);
      return next;
    });
  }, []);

  useEffect(() => {
    const wid = activeSession?.workspaceID?.trim();
    if (!wid) return;
    setCollapsedGroupMap((prev) => {
      if (prev[wid] === false) return prev;
      const next = { ...prev, [wid]: false };
      saveCollapsedGroups(next);
      return next;
    });
  }, [activeSession?.workspaceID]);

  const { visibleSessions, groupedSessions } = useSidebarGroups(sessions, availableWorkspaces, query, locale);
  const drag = useSidebarDragAndDrop({
    listContainerRef, groupedSessions, availableWorkspaces, onMoveSession, onReorderWorkspaces, setGroupExpanded, setOpenMenuWSID,
  });

  const isSearching = query.trim().length > 0;
  const canDrag = !collapsed && !isSearching && !renamingID && !renamingWSID;
  const isGroupExpanded = (group: SessionGroup): boolean =>
    isSearching ? true : Object.prototype.hasOwnProperty.call(collapsedGroupMap, group.id) ? !collapsedGroupMap[group.id] : group.sessions.length > 0;

  const commitRename = (id: string) => { const c = renameDraft.trim(); if (c) onRenameSession(id, c); setRenamingID(null); };
  const commitWorkspaceRename = (id: string) => { const c = renameWSDraft.trim(); if (c) onRenameWorkspace(id, c); setRenamingWSID(null); };
  const submitNewWorkspace = () => { const c = newWorkspaceDraft.trim(); if (c) onCreateWorkspace(c); setCreatingWorkspace(false); setNewWorkspaceDraft(""); };

  const renderRow = (session: SessionSummary, groupId: string, nested: boolean) => {
    const isBeingDragged = drag.dragSession?.session.id === session.id;
    return (
      <SidebarSessionRow
        key={session.id} session={session} groupId={groupId} nested={nested} active={session.id === activeSessionID}
        isRenaming={renamingID === session.id} renameDraft={renameDraft} collapsed={collapsed} canDrag={canDrag} isBeingDragged={isBeingDragged}
        showInsertBefore={drag.sessionDropTarget?.kind === "row" && drag.sessionDropTarget.targetSessionId === session.id && drag.sessionDropTarget.position === "before" && !isBeingDragged}
        showInsertAfter={drag.sessionDropTarget?.kind === "row" && drag.sessionDropTarget.targetSessionId === session.id && drag.sessionDropTarget.position === "after" && !isBeingDragged}
        locale={locale} onSelect={onSelectSession} onStartRename={(id, title) => { setRenameDraft(title); setRenamingID(id); }}
        onRenameDraftChange={setRenameDraft} onCommitRename={commitRename} onCancelRename={() => setRenamingID(null)}
        onTogglePin={onTogglePinSession} onDelete={onDeleteSession}
        onPointerStart={(s, gid, x, y) => { drag.pendingSessionDragRef.current = { session: s, sourceGroupId: gid, startX: x, startY: y }; }}
        suppressClickRef={drag.suppressClickRef}
      />
    );
  };

  const generalGroup = groupedSessions.find((g) => g.workspace === null);
  const isDraggingAny = Boolean(drag.dragSession || drag.dragWorkspace);

  return (
    <aside
      data-sidebar-collapsed={collapsed}
      aria-label="Sessions navigation"
      className="relative flex h-full shrink-0 overflow-hidden border-r border-line bg-canvas transition-[width]"
      style={{ width: collapsed ? 50 : 232, transitionDuration: "220ms", transitionTimingFunction: "cubic-bezier(0.32, 0.72, 0, 1)", willChange: "width" }}
    >
      <div className="flex min-h-0 w-[232px] shrink-0 flex-col py-2">
        <SidebarPrimaryHeader
          botName={botName} botAvatarDataURL={botAvatarDataURL} collapsed={collapsed} locale={locale}
          activeWorkspaceID={activeSession?.workspaceID} activeWorkspacePath={activeSession?.workspacePath}
          meetingRoomActive={meetingRoomActive} meetingRoomIsConvening={meetingRoomIsConvening}
          onToggleCollapse={onToggleCollapse} onNewChat={onNewChat} onOpenMeetingRoom={onOpenMeetingRoom}
          onStartCreateWorkspace={() => { if (collapsed) onToggleCollapse(); setCreatingWorkspace(true); setNewWorkspaceDraft(""); }}
        />

        {creatingWorkspace && !collapsed && (
          <div className="mx-3 mt-1.5 flex items-center gap-1 rounded-[8px] bg-surface px-2 py-1 shadow-hairline">
            <input
              autoFocus value={newWorkspaceDraft} onChange={(e) => setNewWorkspaceDraft(e.target.value)}
              onBlur={() => { if (newWorkspaceDraft.trim()) submitNewWorkspace(); else setCreatingWorkspace(false); }}
              onKeyDown={(e) => { if (e.key === "Enter") submitNewWorkspace(); if (e.key === "Escape") { setCreatingWorkspace(false); setNewWorkspaceDraft(""); } }}
              placeholder={locale === "zh" ? "工作区名称，回车创建…" : "Workspace name…"}
              className="min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none placeholder:text-ink-3 select-text"
            />
          </div>
        )}

        <div ref={listContainerRef} className={`bui-scroll mt-3 min-h-0 flex-1 overflow-y-auto transition-opacity duration-120 ease-out ${collapsed ? "pointer-events-none opacity-0" : "opacity-100"}`}>
          {onSelectMeetingSession && onNewMeetingSession && (
            <SidebarMeetingGroup
              sessions={meetingRoomSessions}
              activeSessionID={activeMeetingSessionID}
              meetingRoomActive={meetingRoomActive}
              isConvening={meetingRoomIsConvening}
              locale={locale}
              onNewMeeting={onNewMeetingSession}
              onSelectMeeting={onSelectMeetingSession}
              onRenameMeeting={onRenameMeetingSession ?? (() => {})}
              onDeleteMeeting={onDeleteMeetingSession ?? (() => {})}
              onTogglePinMeeting={onTogglePinMeetingSession ?? (() => {})}
            />
          )}
          <SidebarSearchHeader
            searchOpen={searchOpen} query={query} hasWorkspaces={availableWorkspaces.length > 0} locale={locale} searchRef={searchRef}
            onOpenSearch={() => setSearchOpen(true)} onCloseSearch={() => { setSearchOpen(false); setQuery(""); }} onQueryChange={setQuery}
          />
          <GlideMenu rowSelector="[data-row]" highlightClassName={`sidebar-glide-highlight rounded-[7px] bg-hover-2 ${isDraggingAny ? "hidden" : ""}`} className="group/glide flex flex-col">
            {groupedSessions.filter((g) => g.workspace !== null).map((group) => {
              const ws = group.workspace!;
              const isWSDragged = drag.dragWorkspace?.workspace.id === ws.id;
              return (
                <SidebarWorkspaceGroup
                  key={group.id} group={group} expanded={isGroupExpanded(group)} activeSessionID={activeSessionID}
                  isGroupDropHighlight={drag.sessionDropTarget?.kind === "group" && drag.sessionDropTarget.groupId === group.id}
                  isWSDragged={isWSDragged}
                  showWSBefore={drag.workspaceDropTarget?.targetWorkspaceId === ws.id && drag.workspaceDropTarget.position === "before" && !isWSDragged}
                  showWSAfter={drag.workspaceDropTarget?.targetWorkspaceId === ws.id && drag.workspaceDropTarget.position === "after" && !isWSDragged}
                  menuOpen={openMenuWSID === ws.id} isRenamingWS={renamingWSID === ws.id} renameWSDraft={renameWSDraft}
                  canDrag={canDrag} isDraggingAny={isDraggingAny} locale={locale}
                  onToggleExpand={() => setGroupExpanded(group.id, !isGroupExpanded(group))}
                  onStartRenameWS={() => { setRenameWSDraft(ws.name); setRenamingWSID(ws.id); }}
                  onRenameWSDraftChange={setRenameWSDraft} onCommitRenameWS={() => commitWorkspaceRename(ws.id)} onCancelRenameWS={() => setRenamingWSID(null)}
                  onToggleMenu={() => setOpenMenuWSID((cur) => (cur === ws.id ? null : ws.id))} onCloseMenu={() => setOpenMenuWSID(null)}
                  onNewChatInWS={() => { setGroupExpanded(group.id, true); onNewChat(group.workspaceID, ws.folderPath ?? null); }}
                  onChooseFolder={() => onChooseWorkspaceFolder(ws.id)} onUnlinkFolder={() => onUnlinkWorkspaceFolder(ws.id)} onDeleteWS={() => onDeleteWorkspace(ws.id)}
                  onPointerStartWS={(w, x, y) => { drag.pendingWSDragRef.current = { workspace: w, startX: x, startY: y }; }}
                  suppressClickRef={drag.suppressClickRef} renderChildRow={(s) => renderRow(s, group.id, true)}
                />
              );
            })}
            {generalGroup && (
              <SidebarGeneralGroup
                key={generalGroup.id} group={generalGroup} hasWorkspaces={availableWorkspaces.length > 0}
                isGroupDropHighlight={drag.sessionDropTarget?.kind === "group" && drag.sessionDropTarget.groupId === generalGroup.id}
                isDraggingAny={isDraggingAny} locale={locale} onNewChat={() => onNewChat(null, null)}
                renderRow={(s) => renderRow(s, generalGroup.id, false)}
              />
            )}
            {query && visibleSessions.length === 0 && (
              <div className="mx-2 px-2 py-2 text-[12.5px] text-ink-3">{locale === "zh" ? "未找到匹配会话" : "No sessions found"}</div>
            )}
          </GlideMenu>
        </div>

        <SidebarFooterSettings locale={locale} onOpenSettings={onOpenSettings} />
      </div>

      {isDraggingAny && (
        <div
          className="pointer-events-none fixed z-50 flex max-w-[210px] items-center gap-1.5 rounded-[8px] bg-surface px-2.5 py-1.5 text-[13px] font-medium text-ink shadow-overlay"
          style={{ left: (drag.dragSession?.x ?? drag.dragWorkspace?.x ?? 0) + 12, top: (drag.dragSession?.y ?? drag.dragWorkspace?.y ?? 0) - 14 }}
        >
          {drag.dragWorkspace && <WorkspaceGlyph isFolderBacked={drag.dragWorkspace.workspace.isFolderBacked} className="text-ink-2" />}
          <span className="truncate">{drag.dragSession?.session.title ?? drag.dragWorkspace?.workspace.name}</span>
        </div>
      )}
    </aside>
  );
}

export default memo(SidebarNav);
