import { memo, useState } from "react";
import type { MeetingRoomSessionSummary } from "../types";

type SidebarMeetingGroupProps = {
  sessions: MeetingRoomSessionSummary[];
  activeSessionID: string;
  meetingRoomActive: boolean;
  isConvening: boolean;
  locale: "zh" | "en";
  onNewMeeting: () => void;
  onSelectMeeting: (id: string) => void;
  onRenameMeeting: (id: string, title: string) => void;
  onDeleteMeeting: (id: string) => void;
  onTogglePinMeeting: (id: string) => void;
};

const SidebarMeetingGroup = memo(function SidebarMeetingGroup({
  sessions,
  activeSessionID,
  meetingRoomActive,
  isConvening,
  locale,
  onNewMeeting,
  onSelectMeeting,
  onRenameMeeting,
  onDeleteMeeting,
  onTogglePinMeeting,
}: SidebarMeetingGroupProps) {
  const [expanded, setExpanded] = useState(true);
  const [renamingID, setRenamingID] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");

  const commitRename = (id: string) => {
    const clean = renameDraft.trim();
    if (clean) onRenameMeeting(id, clean);
    setRenamingID(null);
  };

  return (
    <div className="mb-1">
      <div className="group/ws relative mx-2 flex h-8 items-center gap-1 rounded-[8px] px-1.5 transition-colors hover:bg-hover">
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="flex min-w-0 flex-1 items-center gap-1.5 text-left"
        >
          <span className={`flex size-4 shrink-0 items-center justify-center text-ink-3 transition-transform duration-150 ${expanded ? "rotate-90" : ""}`}>
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M9 6l6 6-6 6" />
            </svg>
          </span>
          <svg width="13.5" height="13.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className={`shrink-0 ${meetingRoomActive ? "text-ink" : "text-ink-3"}`}>
            <circle cx="9" cy="8" r="3" />
            <circle cx="17" cy="9" r="2.5" />
            <path d="M3.5 19a5.5 5.5 0 0 1 11 0" />
            <path d="M14.5 18.5a4.5 4.5 0 0 1 6 0" />
          </svg>
          <span className={`truncate text-[13px] font-medium ${meetingRoomActive ? "text-ink" : "text-ink-2"}`}>
            {locale === "zh" ? "会议室" : "Meetings"}
          </span>
          {isConvening && <span className="size-1.5 shrink-0 rounded-full bg-accent animate-pulse" />}
        </button>

        <span className="text-[12px] tabular-nums text-ink-3 group-hover/ws:hidden">
          {sessions.length}
        </span>
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            setExpanded(true);
            onNewMeeting();
          }}
          title={locale === "zh" ? "新建会议" : "New meeting"}
          className="hidden size-5.5 shrink-0 items-center justify-center rounded-[5px] text-ink-3 group-hover/ws:flex hover:bg-hover-2 hover:text-ink"
        >
          <svg width="12.5" height="12.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
            <path d="M12 5v14M5 12h14" />
          </svg>
        </button>
      </div>

      {expanded && (
        <div className="relative ml-[18px] mr-2 mt-0.5 mb-1.5 flex flex-col gap-0.5 border-l border-line-strong/80 pl-2">
          {sessions.map((sess) => {
            const isActive = meetingRoomActive && sess.id === activeSessionID;
            const isRenaming = renamingID === sess.id;
            return (
              <div
                key={sess.id}
                className={`group/row relative flex h-7.5 items-center rounded-[7px] px-2 transition-colors ${
                  isActive ? "bg-surface text-ink shadow-hairline" : "text-ink-2 hover:bg-hover hover:text-ink"
                }`}
              >
                {isRenaming ? (
                  <input
                    autoFocus
                    value={renameDraft}
                    onChange={(e) => setRenameDraft(e.target.value)}
                    onBlur={() => commitRename(sess.id)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") commitRename(sess.id);
                      if (e.key === "Escape") setRenamingID(null);
                    }}
                    className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none select-text"
                  />
                ) : (
                  <button
                    type="button"
                    onClick={() => onSelectMeeting(sess.id)}
                    onDoubleClick={() => {
                      setRenameDraft(sess.title);
                      setRenamingID(sess.id);
                    }}
                    className="flex min-w-0 flex-1 items-center gap-1.5 text-left"
                  >
                    {sess.isPinned && <span className="size-1.5 shrink-0 rounded-full bg-accent" />}
                    <span className="truncate text-[12.5px]">{sess.title}</span>
                  </button>
                )}

                {!isRenaming && (
                  <div className="hidden shrink-0 items-center gap-0.5 group-hover/row:flex">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onTogglePinMeeting(sess.id);
                      }}
                      title={sess.isPinned ? "取消置顶" : "置顶"}
                      className="flex size-5 items-center justify-center rounded-[4px] text-[12px] text-ink-3 hover:bg-hover-2 hover:text-ink"
                    >
                      {sess.isPinned ? "★" : "☆"}
                    </button>
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onDeleteMeeting(sess.id);
                      }}
                      title={locale === "zh" ? "删除" : "Delete"}
                      className="flex size-5 items-center justify-center rounded-[4px] text-ink-3 hover:bg-hover-2 hover:text-red"
                    >
                      ×
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
});

export default SidebarMeetingGroup;
