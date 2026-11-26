import { Fragment } from "react";

export function renderTextWithMentions(text: string, variant: "accent" | "subtle" = "subtle") {
  if (!text.includes("@")) return text;
  const parts = text.split(/(@[^\s@，。！？,.!?:：；;]+)/g);
  return parts.map((part, idx) => {
    if (part.startsWith("@") && part.length > 1) {
      return (
        <span
          key={idx}
          className={
            variant === "accent"
              ? "mx-0.5 inline-block rounded-[5px] bg-white/22 px-1.5 py-0.2 font-semibold text-white"
              : "mx-0.5 inline-block rounded-[5px] bg-accent-tint px-1.5 py-0.2 font-medium text-accent-ink"
          }
        >
          {part}
        </span>
      );
    }
    return <Fragment key={idx}>{part}</Fragment>;
  });
}
