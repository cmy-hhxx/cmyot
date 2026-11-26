import { memo, useMemo, useState } from "react";
import type { StickerItem } from "../types";

type StickerPickerPopoverProps = {
  locale: "zh" | "en";
  stickers: StickerItem[];
  onSelectSticker: (sticker: StickerItem) => void;
  onToggleFavorite: (id: string) => void;
  onUploadSticker: () => void;
  onSearchOnline: (query: string) => void;
  onClose: () => void;
};

const CATEGORY_LABELS: Record<string, string> = {
  recent: "常用",
  fav: "收藏",
  all: "全部",
  cat: "猫",
  dog: "狗",
  deepseek: "DeepSeek",
  claude: "Claude",
  openai: "GPT",
  gemini: "Gemini",
  baoman: "暴漫",
  reaction: "表态",
  custom: "自定义",
};

function matchesSticker(item: StickerItem, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  return (
    item.ocrText.toLowerCase().includes(q) ||
    item.meaning.toLowerCase().includes(q) ||
    item.category.toLowerCase().includes(q) ||
    item.tags.some((t) => t.toLowerCase().includes(q)) ||
    item.moods.some((m) => m.toLowerCase().includes(q))
  );
}

const StickerPickerPopover = memo(function StickerPickerPopover({
  locale,
  stickers,
  onSelectSticker,
  onToggleFavorite,
  onUploadSticker,
  onSearchOnline,
}: StickerPickerPopoverProps) {
  const [tab, setTab] = useState<string>("all");
  const [query, setQuery] = useState("");
  const [onlineSearching, setOnlineSearching] = useState(false);

  const categories = useMemo(() => {
    const counts = new Map<string, number>();
    for (const s of stickers) {
      counts.set(s.category, (counts.get(s.category) ?? 0) + 1);
    }
    const keys = ["all", "fav", "recent", "cat", "dog", "deepseek", "claude", "openai", "gemini", "baoman", "reaction", "custom"];
    return keys.filter((k) => k === "all" || k === "fav" || k === "recent" || (counts.get(k) ?? 0) > 0);
  }, [stickers]);

  const visible = useMemo(() => {
    const cleanQ = query.trim();
    let list = stickers;
    if (tab === "fav") {
      list = list.filter((s) => s.isFavorite);
    } else if (tab === "recent") {
      list = list.filter((s) => s.useCount > 0).slice().sort((a, b) => b.useCount - a.useCount);
    } else if (tab !== "all") {
      list = list.filter((s) => s.category === tab);
    }
    if (cleanQ) {
      list = list.filter((s) => matchesSticker(s, cleanQ));
    }
    return list.slice(0, 80);
  }, [stickers, tab, query]);

  const triggerOnlineExpand = () => {
    const q = query.trim();
    if (!q) return;
    setOnlineSearching(true);
    onSearchOnline(q);
    setTimeout(() => setOnlineSearching(false), 1800);
  };

  return (
    <div
      onMouseDown={(e) => e.stopPropagation()}
      className="absolute bottom-full left-0 z-30 mb-2 flex w-[340px] flex-col overflow-hidden rounded-[12px] border border-line bg-surface shadow-raised"
      style={{ animation: "pop-in 150ms cubic-bezier(0.23,1,0.32,1) both", transformOrigin: "bottom left" }}
    >
      {/* Search + Upload header */}
      <div className="flex items-center gap-1.5 border-b border-line px-2.5 py-2">
        <div className="flex h-7.5 min-w-0 flex-1 items-center gap-1.5 rounded-[7px] bg-inset px-2">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="shrink-0 text-ink-3">
            <circle cx="11" cy="11" r="7" />
            <path d="M21 21l-4.3-4.3" />
          </svg>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && visible.length === 0 && query.trim()) {
                triggerOnlineExpand();
              }
            }}
            placeholder={locale === "zh" ? "搜索" : "Search"}
            className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3 select-text"
          />
        </div>
        <button
          type="button"
          onClick={onUploadSticker}
          className="flex h-7.5 shrink-0 items-center gap-1 rounded-[7px] bg-inset px-2 text-[12px] font-medium text-ink transition-colors hover:bg-hover-2"
        >
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
            <path d="M12 5v14M5 12h14" />
          </svg>
          <span>{locale === "zh" ? "上传" : "Add"}</span>
        </button>
      </div>

      {/* Category tabs */}
      <div className="bui-scroll flex items-center gap-1 overflow-x-auto border-b border-line px-2 py-1.5">
        {categories.map((key) => {
          const active = tab === key;
          return (
            <button
              key={key}
              type="button"
              onClick={() => setTab(key)}
              className={`shrink-0 rounded-[6px] px-2 py-1 text-[12px] font-medium transition-colors ${
                active ? "bg-hover-2 text-ink" : "text-ink-3 hover:bg-hover hover:text-ink"
              }`}
            >
              {CATEGORY_LABELS[key] ?? key}
            </button>
          );
        })}
      </div>

      {/* Grid */}
      <div className="bui-scroll grid h-[228px] grid-cols-4 gap-1.5 overflow-y-auto p-2">
        {visible.length === 0 ? (
          <div className="col-span-4 flex flex-col items-center justify-center gap-2 py-8 text-center">
            <span className="text-[12.5px] text-ink-3">
              {locale === "zh" ? "未找到匹配表情" : "No stickers"}
            </span>
            {query.trim().length > 0 && (
              <button
                type="button"
                onClick={triggerOnlineExpand}
                className="rounded-[7px] bg-inset px-3 py-1 text-[12px] font-medium text-ink hover:bg-hover-2"
              >
                {onlineSearching ? (locale === "zh" ? "搜索入库中…" : "Searching…") : locale === "zh" ? "在线搜图入库" : "Search Online"}
              </button>
            )}
          </div>
        ) : (
          visible.map((stk) => (
            <div key={stk.id} className="group/stk relative">
              <button
                type="button"
                onClick={() => onSelectSticker(stk)}
                title={stk.meaning || stk.ocrText || stk.category}
                className="flex aspect-square w-full items-center justify-center overflow-hidden rounded-[8px] border border-transparent bg-inset/70 p-1 transition-colors hover:border-line-strong hover:bg-hover"
              >
                <img
                  src={stk.url}
                  alt={stk.meaning || stk.ocrText || stk.category}
                  loading="lazy"
                  className="max-h-full max-w-full rounded-[5px] object-contain"
                />
              </button>
              <button
                type="button"
                aria-label="Favorite sticker"
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleFavorite(stk.id);
                }}
                className={`absolute top-1 right-1 flex size-5 items-center justify-center rounded-full bg-surface/90 text-[12px] shadow-hairline transition-opacity ${
                  stk.isFavorite ? "opacity-100 text-orange" : "opacity-0 text-ink-3 group-hover/stk:opacity-100 hover:text-ink"
                }`}
              >
                {stk.isFavorite ? "★" : "☆"}
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
});

export default StickerPickerPopover;
