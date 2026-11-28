import { memo } from "react";
import type { AutonomousDeliverable, AutonomousWorkReport } from "../types";

type WorkReportCardProps = {
  report: AutonomousWorkReport;
  locale: "zh" | "en";
  onOpenDeliverable: (deliverable: AutonomousDeliverable) => void;
};

const WorkReportCard = memo(function WorkReportCard({
  report,
  locale,
  onOpenDeliverable,
}: WorkReportCardProps) {
  return (
    <div className="mt-2.5 flex flex-col gap-2 rounded-[11px] border border-line bg-surface p-3 shadow-hairline">
      <div className="flex items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          <span className="size-2 shrink-0 rounded-full bg-green" />
          <span className="truncate text-[13px] font-semibold text-ink">{report.title}</span>
        </div>
        <span className="shrink-0 rounded-[5px] bg-inset px-1.5 py-0.5 text-[11px] font-medium text-ink-3">
          {locale === "zh" ? "自主交付" : "Delivered"}
        </span>
      </div>

      {report.steps.length > 0 && (
        <div className="flex flex-col gap-1 border-t border-line pt-2">
          {report.steps.map((step, idx) => (
            <div key={`${report.missionID}-s-${idx}`} className="flex items-start gap-1.5 text-[12px] text-ink-2">
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.4"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="mt-0.5 shrink-0 text-green"
              >
                <path d="M20 6L9 17l-5-5" />
              </svg>
              <span className="min-w-0 break-words">{step}</span>
            </div>
          ))}
        </div>
      )}

      {report.deliverables.length > 0 && (
        <div className="flex flex-wrap gap-1.5 border-t border-line pt-2">
          {report.deliverables.map((d) => (
            <button
              key={d.id}
              type="button"
              onClick={() => onOpenDeliverable(d)}
              className="flex h-7 items-center gap-1.5 rounded-[7px] border border-line bg-page px-2.5 text-[12px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-hover"
            >
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.9"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="shrink-0 text-ink-3"
              >
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6" />
              </svg>
              <span className="max-w-[200px] truncate">{d.title}</span>
              {d.subtitle && (
                <span className="text-[11px] text-ink-3">{d.subtitle}</span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
});

export default WorkReportCard;
