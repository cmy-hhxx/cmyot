import { memo, useEffect, useRef, useState } from "react";
import type { SessionSummary } from "../types";

type TopicRowProps = {
  topic: SessionSummary;
  isActive: boolean;
  isRenaming: boolean;
  renameDraft: string;
  canDelete: boolean;
  locale: "zh" | "en";
  onSelect: () => void;
  onStartRename: () => void;
  onRenameDraftChange: (v: string) => void;
  onCommitRename: () => void;
  onCancelRename: () => void;
  onTogglePin: () => void;
  onDelete: () => void;
};

const TopicRow = memo(function TopicRow({
  topic,
  isActive,
  isRenaming,
  renameDraft,
  canDelete,
  locale,
  onSelect,
  onStartRename,
  onRenameDraftChange,
  onCommitRename,
  onCancelRename,
  onTogglePin,
  onDelete,
}: TopicRowProps) {
  return (
    <div
      className={`group/topic flex items-center gap-1 rounded-[7px] px-2 py-1.5 transition-colors ${
        isActive ? "bg-hover-2 text-ink" : "text-ink-2 hover:bg-hover hover:text-ink"
      }`}
    >
      {isRenaming ? (
        <input
          autoFocus
          value={renameDraft}
          onChange={(e) => onRenameDraftChange(e.target.value)}
          onBlur={onCommitRename}
          onKeyDown={(e) => {
            if (e.key === "Enter") onCommitRename();
            if (e.key === "Escape") onCancelRename();
          }}
          className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none select-text"
        />
      ) : (
        <button
          type="button"
          onClick={onSelect}
          onDoubleClick={onStartRename}
          className="flex min-w-0 flex-1 items-center gap-1.5 text-left"
        >
          <span className="truncate text-[12.5px] font-medium">{topic.title}</span>
          {topic.messageCount !== undefined && (
            <span className="shrink-0 text-[11px] tabular-nums text-ink-3">{topic.messageCount}</span>
          )}
        </button>
      )}

      {!isRenaming && (
        <div className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover/topic:opacity-100">
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onTogglePin();
            }}
            title={topic.isPinned ? (locale === "zh" ? "取消置顶" : "Unpin") : locale === "zh" ? "置顶" : "Pin"}
            className={`flex size-5 items-center justify-center rounded-[4px] hover:bg-hover-2 ${
              topic.isPinned ? "text-ink" : "text-ink-3"
            }`}
          >
            <svg width="11" height="11" viewBox="0 0 24 24" fill={topic.isPinned ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2">
              <path d="M12 17v5M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16h14v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z" />
            </svg>
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onStartRename();
            }}
            title={locale === "zh" ? "重命名" : "Rename"}
            className="flex size-5 items-center justify-center rounded-[4px] text-ink-3 hover:bg-hover-2 hover:text-ink"
          >
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" />
            </svg>
          </button>
          {canDelete && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
              title={locale === "zh" ? "删除" : "Delete"}
              className="flex size-5 items-center justify-center rounded-[4px] text-ink-3 hover:bg-hover-2 hover:text-ink"
            >
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M18 6L6 18M6 6l12 12" />
              </svg>
            </button>
          )}
        </div>
      )}
    </div>
  );
});

export default function TopicHistoryMenu({
  topics,
  activeSessionID,
  locale,
  onSelectSession,
  onRenameSession,
  onDeleteSession,
  onTogglePinSession,
}: {
  topics: SessionSummary[];
  activeSessionID: string;
  locale: "zh" | "en";
  onSelectSession: (id: string) => void;
  onRenameSession: (id: string, title: string) => void;
  onDeleteSession: (id: string) => void;
  onTogglePinSession: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [renamingID, setRenamingID] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
        setRenamingID(null);
      }
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [open]);

  const sorted = [...topics].sort((a, b) => {
    if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
    return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
  });

  const commitRename = (id: string) => {
    const clean = renameDraft.trim();
    if (clean) onRenameSession(id, clean);
    setRenamingID(null);
  };

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={`flex h-8 items-center gap-1 rounded-[7px] px-2.5 text-[12.5px] font-medium transition-colors duration-100 ${
          open ? "bg-hover-2 text-ink" : "text-ink-2 hover:bg-hover hover:text-ink"
        }`}
      >
        <span>{locale === "zh" ? "历史话题" : "Topics"}</span>
        {sorted.length > 0 && (
          <span className="text-[11px] tabular-nums text-ink-3">{sorted.length}</span>
        )}
      </button>

      {open && (
        <div className="bui-scroll absolute right-0 top-9 z-40 max-h-[300px] w-[240px] overflow-y-auto rounded-[10px] bg-surface p-1.5 shadow-overlay">
          {sorted.map((topic) => (
            <TopicRow
              key={topic.id}
              topic={topic}
              isActive={topic.id === activeSessionID}
              isRenaming={renamingID === topic.id}
              renameDraft={renameDraft}
              canDelete={sorted.length > 1}
              locale={locale}
              onSelect={() => {
                onSelectSession(topic.id);
                setOpen(false);
              }}
              onStartRename={() => {
                setRenameDraft(topic.title);
                setRenamingID(topic.id);
              }}
              onRenameDraftChange={setRenameDraft}
              onCommitRename={() => commitRename(topic.id)}
              onCancelRename={() => setRenamingID(null)}
              onTogglePin={() => onTogglePinSession(topic.id)}
              onDelete={() => onDeleteSession(topic.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
