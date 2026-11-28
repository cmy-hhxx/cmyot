import { memo, useEffect, useState } from "react";
import type { ContactSummary } from "../types";

type CreateGroupModalProps = {
  open: boolean;
  locale: "zh" | "en";
  contacts: ContactSummary[];
  onClose: () => void;
  onCreate: (title: string, participantIDs: string[]) => void;
};

const CreateGroupModal = memo(function CreateGroupModal({
  open,
  locale,
  contacts,
  onClose,
  onCreate,
}: CreateGroupModalProps) {
  const [title, setTitle] = useState("");
  const [selectedIDs, setSelectedIDs] = useState<string[]>(["butler"]);

  useEffect(() => {
    if (!open) return;
    setTitle("");
    const hasButler = contacts.some((c) => c.id === "butler");
    setSelectedIDs(hasButler ? ["butler"] : contacts.slice(0, 1).map((c) => c.id));
  }, [open, contacts]);

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  const toggleID = (id: string) => {
    setSelectedIDs((prev) => (prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]));
  };

  const handleConfirm = () => {
    if (selectedIDs.length === 0) return;
    onCreate(title.trim(), selectedIDs);
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-[2px]"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex w-full max-w-[400px] flex-col overflow-hidden rounded-[14px] border border-line bg-surface shadow-overlay"
        style={{ animation: "pop-in 160ms cubic-bezier(0.23,1,0.32,1) both" }}
      >
        <div className="flex h-12 shrink-0 items-center justify-between border-b border-line px-4">
          <div className="flex items-center gap-2">
            <span className="text-[14px] font-semibold text-ink">
              {locale === "zh" ? "新建群聊" : "New Group"}
            </span>
            <span className="rounded-[6px] bg-inset px-1.5 py-0.5 text-[11px] font-medium text-ink-3">
              {locale === "zh" ? "群主：我" : "Owner: Me"}
            </span>
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="flex size-7 items-center justify-center rounded-[7px] text-ink-3 transition-colors hover:bg-hover hover:text-ink"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round">
              <path d="M18 6L6 18M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="flex flex-col gap-3 p-4">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={locale === "zh" ? "群聊名称" : "Group name"}
            className="h-9 w-full rounded-[9px] border border-line bg-inset px-3 text-[13.5px] text-ink outline-none placeholder:text-ink-3 focus:border-line-strong select-text"
          />

          <div className="flex items-center justify-between">
            <span className="text-[12px] font-medium text-ink-2">
              {locale === "zh" ? `选择入群智能体 (${selectedIDs.length})` : `Select Bots (${selectedIDs.length})`}
            </span>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setSelectedIDs(contacts.map((c) => c.id))}
                className="text-[12px] font-medium text-ink-3 hover:text-ink"
              >
                {locale === "zh" ? "全选" : "All"}
              </button>
              <button
                type="button"
                onClick={() => setSelectedIDs([])}
                className="text-[12px] font-medium text-ink-3 hover:text-ink"
              >
                {locale === "zh" ? "清空" : "None"}
              </button>
            </div>
          </div>

          <div className="bui-scroll flex max-h-[260px] flex-col gap-1 overflow-y-auto pr-0.5">
            {contacts.map((c) => {
              const checked = selectedIDs.includes(c.id);
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => toggleID(c.id)}
                  className={`flex w-full items-center gap-2.5 rounded-[9px] px-2.5 py-2 text-left transition-colors ${
                    checked ? "bg-hover-2 text-ink" : "hover:bg-hover text-ink-2"
                  }`}
                >
                  <span
                    className="flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-[8px] border border-line bg-surface"
                    style={!c.avatarURL ? { backgroundColor: `${c.accentHex}20`, color: c.accentHex } : undefined}
                  >
                    {c.avatarURL ? (
                      <img src={c.avatarURL} alt={c.name} className="size-full object-cover" />
                    ) : (
                      <span className="text-[12px] font-semibold">{c.name.slice(0, 1)}</span>
                    )}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="truncate text-[13px] font-medium text-ink">{c.name}</span>
                      {c.isButler && (
                        <span className="rounded-[5px] bg-inset px-1.5 py-0.5 text-[10.5px] font-medium text-ink-3">
                          {locale === "zh" ? "总管" : "Chief"}
                        </span>
                      )}
                    </div>
                    {c.tagline && (
                      <div className="truncate text-[12px] text-ink-3">{c.tagline}</div>
                    )}
                  </div>
                  <span
                    className={`flex size-4.5 shrink-0 items-center justify-center rounded-[5px] border transition-colors ${
                      checked
                        ? "border-accent bg-accent text-white"
                        : "border-line-strong bg-page"
                    }`}
                  >
                    {checked && (
                      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M20 6L9 17l-5-5" />
                      </svg>
                    )}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 border-t border-line px-4 py-3">
          <button
            type="button"
            onClick={onClose}
            className="flex h-8 items-center rounded-[8px] px-3 text-[13px] font-medium text-ink-2 hover:bg-hover"
          >
            {locale === "zh" ? "取消" : "Cancel"}
          </button>
          <button
            type="button"
            disabled={selectedIDs.length === 0}
            onClick={handleConfirm}
            className="flex h-8 items-center rounded-[8px] bg-accent px-3.5 text-[13px] font-medium text-white transition-opacity disabled:opacity-45"
          >
            {locale === "zh" ? "创建群聊" : "Create Group"}
          </button>
        </div>
      </div>
    </div>
  );
});

export default CreateGroupModal;
