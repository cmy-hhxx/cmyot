import type { ToolReceipt } from "../types";

/* ─────────────────────────────────────────────────────────
 * TOOL CHIPS (beautifului.dev)
 * Compact status pills showing completed workspace / agent actions.
 * ───────────────────────────────────────────────────────── */

export default function ToolChips({ items }: { items: ToolReceipt[] }) {
  if (!items.length) return null;

  return (
    <div className="mt-2.5 flex flex-wrap gap-1.5">
      {items.map((item, i) => {
        const isErr = item.status === "error";
        return (
          <span
            key={item.id || `${item.label}-${i}`}
            className="inline-flex h-6 max-w-full items-center gap-1.5 rounded-chip bg-surface px-2 text-[11.5px] font-medium text-ink shadow-btn"
            style={{ animation: `pop-in 220ms cubic-bezier(0.23,1,0.32,1) ${Math.min(i, 6) * 55}ms both` }}
          >
            <span className={`size-1.5 shrink-0 rounded-full ${isErr ? "bg-red" : "bg-green"}`} />
            <span className="truncate">{item.label}</span>
            {item.detail && (
              <span className="truncate font-mono text-[10.5px] font-normal text-ink-3">{item.detail}</span>
            )}
          </span>
        );
      })}
    </div>
  );
}
