import { useLayoutEffect, useRef, useState } from "react";
import type { ThinkingStep } from "../types";

/* ─────────────────────────────────────────────────────────
 * THINKING STATE — live expandable trace (beautifului.dev)
 * Drives real Pi reasoning + real tool execution steps:
 *   · shimmering header while working, quiet summary once done
 *   · smooth grid-template-rows expand/collapse with thin vertical guide line
 *   · live spinner → crisp checkmark per step, click row to inspect tool output
 * ───────────────────────────────────────────────────────── */

export default function ThinkingState({
  thinking = "",
  steps = [],
  isWorking = false,
  durationMs,
  locale = "zh",
  activeLabel,
}: {
  thinking?: string;
  steps?: ThinkingStep[];
  isWorking?: boolean;
  durationMs?: number;
  locale?: "zh" | "en";
  activeLabel?: string;
}) {
  const [manualExpanded, setManualExpanded] = useState<boolean | null>(null);
  const [openStepIds, setOpenStepIds] = useState<Set<string>>(new Set());
  const traceRef = useRef<HTMLDivElement>(null);
  const [lineHeight, setLineHeight] = useState(0);

  const hasContent = Boolean(thinking.trim()) || steps.length > 0;
  const autoExpanded = isWorking;
  const expanded = manualExpanded ?? autoExpanded;

  useLayoutEffect(() => {
    if (traceRef.current) setLineHeight(traceRef.current.offsetHeight);
  }, [thinking, steps, expanded, openStepIds]);

  if (!hasContent && !isWorking) return null;

  const runningStep = steps.find((s) => s.status === "running");
  const activeTitle =
    activeLabel ||
    (runningStep
      ? runningStep.chip
        ? `${runningStep.label} · ${runningStep.chip}`
        : runningStep.label
      : locale === "zh"
        ? "正在思考"
        : "Thinking");

  const doneSummary = (() => {
    const secs = durationMs && durationMs > 0 ? Math.max(0.1, durationMs / 1000).toFixed(1) : null;
    if (steps.length > 0) {
      return locale === "zh"
        ? `已执行 ${steps.length} 项工具${secs ? ` · ${secs}s` : ""}`
        : `Ran ${steps.length} ${steps.length === 1 ? "tool" : "tools"}${secs ? ` · ${secs}s` : ""}`;
    }
    return locale === "zh"
      ? secs
        ? `思考了 ${secs} 秒`
        : "思考过程"
      : secs
        ? `Thought for ${secs}s`
        : "Thought process";
  })();

  const toggleStepDetail = (id: string) => {
    setOpenStepIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div className="mb-2 flex w-full flex-col">
      <button
        type="button"
        aria-expanded={expanded}
        onClick={() => setManualExpanded((cur) => !(cur ?? autoExpanded))}
        className="-mx-1.5 flex w-fit max-w-full items-center gap-2 rounded-control px-1.5 py-1 transition-colors duration-100 hover:bg-hover-2"
      >
        <svg
          width="15"
          height="15"
          viewBox="0 0 24 24"
          fill={isWorking ? "var(--ink-2)" : "var(--ink-3)"}
          className="shrink-0 transition-colors duration-200"
        >
          <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
        </svg>

        <span role="status" className="min-w-0 truncate">
          {isWorking ? (
            <span
              className="bg-clip-text text-[12.5px] font-medium whitespace-nowrap text-transparent"
              style={{
                backgroundImage:
                  "linear-gradient(90deg, var(--ink-3) 35%, var(--ink) 50%, var(--ink-3) 65%)",
                backgroundSize: "200% 100%",
                animation: "shimmer-text 1.4s linear infinite",
              }}
            >
              {activeTitle}
            </span>
          ) : (
            <span className="text-[12.5px] font-medium whitespace-nowrap text-ink-2" style={{ animation: "fade-in 260ms ease-out both" }}>
              {doneSummary}
            </span>
          )}
        </span>

        {hasContent && (
          <svg
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="none"
            stroke="var(--ink-3)"
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="shrink-0 transition-transform duration-300"
            style={{ transform: expanded ? "rotate(180deg)" : "rotate(0)" }}
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        )}
      </button>

      {hasContent && (
        <div
          className="grid transition-[grid-template-rows,opacity] duration-300"
          style={{
            gridTemplateRows: expanded ? "1fr" : "0fr",
            opacity: expanded ? 1 : 0,
            transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
          }}
        >
          <div className="overflow-hidden">
            <div className="relative mt-0.5 ml-[5px] pl-4">
              <span
                aria-hidden
                className="absolute left-[3px] w-px bg-line"
                style={{
                  top: -6,
                  height: lineHeight ? Math.max(0, lineHeight - 2) : 0,
                  transition: "height 360ms cubic-bezier(0.23,1,0.32,1)",
                }}
              />
              <div ref={traceRef} className="flex flex-col gap-1 py-1">
                {thinking.trim() && (
                  <p className="select-text whitespace-pre-wrap px-1.5 py-0.5 text-[12px] leading-relaxed text-ink-2">
                    {thinking.trim()}
                  </p>
                )}

                {steps.map((step, i) => {
                  const hasDetail = Boolean(step.detail && step.detail.length > 0);
                  const isOpen = openStepIds.has(step.id);
                  return (
                    <div
                      key={step.id}
                      style={{ animation: `fade-up 280ms cubic-bezier(0.23,1,0.32,1) ${Math.min(i, 5) * 60}ms both` }}
                    >
                      <button
                        type="button"
                        disabled={!hasDetail}
                        onClick={() => hasDetail && toggleStepDetail(step.id)}
                        className={`flex min-h-7 w-full items-center gap-2 rounded-[6px] px-1.5 py-0.5 text-left transition-colors duration-100 ${
                          hasDetail ? "hover:bg-hover" : "cursor-default"
                        }`}
                      >
                        {step.status === "running" ? (
                          <span
                            className="size-3 shrink-0 rounded-full border-[1.5px] border-line-strong border-t-ink-2"
                            style={{ animation: "spin 700ms linear infinite" }}
                          />
                        ) : step.status === "error" ? (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--red)" strokeWidth="2.4" strokeLinecap="round" className="shrink-0">
                            <path d="M18 6L6 18M6 6l12 12" />
                          </svg>
                        ) : (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--green)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                            <path d="M20 6L9 17l-5-5" />
                          </svg>
                        )}

                        <span className="shrink-0 text-[12px] font-medium text-ink">{step.label}</span>

                        {step.chip && (
                          <span
                            className={`inline-flex h-5 min-w-0 flex-1 items-center truncate rounded-chip bg-field px-1.5 text-[11px] text-ink-2 shadow-hairline ${
                              step.mono ? "font-mono" : ""
                            }`}
                          >
                            {step.chip}
                          </span>
                        )}

                        {step.durationMs !== undefined && step.durationMs > 0 && (
                          <span className="shrink-0 font-mono text-[10.5px] text-ink-3 tabular-nums">
                            {step.durationMs < 1000 ? `${step.durationMs}ms` : `${(step.durationMs / 1000).toFixed(1)}s`}
                          </span>
                        )}
                      </button>

                      {hasDetail && (
                        <div
                          className="grid transition-[grid-template-rows,opacity] duration-250"
                          style={{
                            gridTemplateRows: isOpen ? "1fr" : "0fr",
                            opacity: isOpen ? 1 : 0,
                            transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
                          }}
                        >
                          <div className="min-h-0 overflow-hidden">
                            <div className="mt-0.5 mb-1 ml-2 flex flex-col gap-0.5 border-l border-line py-0.5 pl-3">
                              {step.detail!.slice(0, 12).map((line, lineIdx) => (
                                <span
                                  key={lineIdx}
                                  className="select-text break-words font-mono text-[11px] leading-[1.55] text-ink-2"
                                >
                                  {line}
                                </span>
                              ))}
                            </div>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
