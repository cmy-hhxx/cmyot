import { memo, useEffect, useState, type CSSProperties } from "react";
import type { MeetingRoomParticipant } from "../types";

type KineticStyle = "orbit" | "typewriter" | "stack" | "bars" | "ripple" | "scan";

type BotThinkingSpec = {
  style: KineticStyle;
  labelZh: string;
  labelEn: string;
};

const ORBIT_ORDER = [0, 1, 2, 5, 8, 7, 6, 3];
const ORBIT_DELAYS = Array.from({ length: 9 }, (_, i) => {
  const k = ORBIT_ORDER.indexOf(i);
  return k === -1 ? null : k * 105;
});

const CUSTOM_STYLES: KineticStyle[] = ["ripple", "typewriter", "bars", "orbit", "stack", "scan"];
const CUSTOM_VERBS_ZH = ["酝酿回复", "组织思路", "琢磨回应", "构思措辞"];
const CUSTOM_VERBS_EN = ["Composing", "Thinking", "Crafting", "Reflecting"];

function hashBotId(id: string): number {
  let h = 2166136261;
  for (let i = 0; i < id.length; i += 1) {
    h ^= id.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

function resolveBotThinkingSpec(bot: MeetingRoomParticipant, isStickerContext: boolean): BotThinkingSpec {
  switch (bot.id) {
    case "butler":
      return {
        style: "orbit",
        labelZh: isStickerContext ? "看看情况" : "统筹梳理",
        labelEn: isStickerContext ? "Checking in" : "Coordinating",
      };
    case "ghost":
      return {
        style: "typewriter",
        labelZh: isStickerContext ? "顺手接梗" : "落笔构思",
        labelEn: isStickerContext ? "Reacting" : "Drafting",
      };
    case "organizeAndMerge":
      return {
        style: "stack",
        labelZh: isStickerContext ? "搭话中" : "翻阅脉络",
        labelEn: isStickerContext ? "Responding" : "Organizing",
      };
    case "weeklyReport":
    case "weeklyReportItem":
    case "interactiveChart":
      return {
        style: "bars",
        labelZh: isStickerContext ? "凑过来聊" : "整理要点",
        labelEn: isStickerContext ? "Chiming in" : "Synthesizing",
      };
    case "persona":
      return {
        style: "ripple",
        labelZh: isStickerContext ? "体察情绪" : "细细琢磨",
        labelEn: isStickerContext ? "Sensing mood" : "Reflecting",
      };
    case "readingCompanion":
    case "translate":
    case "explain":
    case "summarize":
    case "ocrPolish":
      return {
        style: "scan",
        labelZh: isStickerContext ? "组织回应" : "梳理线索",
        labelEn: isStickerContext ? "Replying" : "Analyzing",
      };
    default: {
      const h = hashBotId(bot.id || bot.name);
      return {
        style: CUSTOM_STYLES[h % CUSTOM_STYLES.length],
        labelZh: isStickerContext ? "马上接话" : CUSTOM_VERBS_ZH[h % CUSTOM_VERBS_ZH.length],
        labelEn: isStickerContext ? "Replying" : CUSTOM_VERBS_EN[h % CUSTOM_VERBS_EN.length],
      };
    }
  }
}

function useElapsedSeconds(resetKey: string): string {
  const [ds, setDs] = useState(0);
  useEffect(() => {
    setDs(0);
    const t = setInterval(() => setDs((v) => v + 1), 100);
    return () => clearInterval(t);
  }, [resetKey]);
  const sec = ds / 10;
  if (sec < 60) return `${sec.toFixed(1)}s`;
  return `${Math.floor(sec / 60)}m ${(sec % 60).toFixed(0)}s`;
}

function BotKineticGlyph({ style, accent }: { style: KineticStyle; accent: string }) {
  if (style === "orbit") {
    return (
      <span aria-hidden className="grid shrink-0 grid-cols-[repeat(3,3.5px)] gap-[1.5px]">
        {ORBIT_DELAYS.map((delay, idx) => (
          <span
            key={idx}
            className="size-[3.5px] rounded-[1px]"
            style={{
              backgroundColor: accent,
              opacity: delay === null ? 0.14 : 0.2,
              animation: delay === null ? "none" : `pixel-on 880ms ease-in-out ${delay}ms infinite`,
            }}
          />
        ))}
      </span>
    );
  }

  if (style === "typewriter") {
    return (
      <span aria-hidden className="flex h-[14px] w-[20px] shrink-0 flex-col justify-center gap-[2.5px]">
        <span className="flex items-center gap-[1.5px]">
          <span
            className="h-[2px] w-[13px] origin-left rounded-full"
            style={{ backgroundColor: accent, animation: "bot-ink-line 1.25s ease-in-out infinite" }}
          />
          <span
            className="h-[6px] w-[1.5px] rounded-full"
            style={{ backgroundColor: accent, animation: "caret-blink 720ms step-end infinite" }}
          />
        </span>
        <span
          className="h-[2px] w-[10px] origin-left rounded-full opacity-55"
          style={{ backgroundColor: accent, animation: "bot-ink-line 1.25s ease-in-out 240ms infinite" }}
        />
      </span>
    );
  }

  if (style === "stack") {
    return (
      <span aria-hidden className="flex h-[14px] w-[18px] shrink-0 flex-col justify-center gap-[2.5px]">
        {[0, 140, 280].map((delay, idx) => (
          <span
            key={delay}
            className="h-[2px] rounded-full"
            style={{
              width: idx === 1 ? "16px" : idx === 2 ? "11px" : "14px",
              backgroundColor: accent,
              animation: `bot-stack-slide 1.15s ease-in-out ${delay}ms infinite`,
            }}
          />
        ))}
      </span>
    );
  }

  if (style === "bars") {
    return (
      <span aria-hidden className="flex h-[14px] w-[18px] shrink-0 items-center justify-center gap-[2px]">
        {[0, 120, 240, 360].map((delay) => (
          <span
            key={delay}
            className="h-[12px] w-[2.5px] origin-bottom rounded-full"
            style={{
              backgroundColor: accent,
              animation: `bot-bar-wave 960ms ease-in-out ${delay}ms infinite`,
            }}
          />
        ))}
      </span>
    );
  }

  if (style === "ripple") {
    return (
      <span aria-hidden className="relative flex size-[16px] shrink-0 items-center justify-center">
        <span
          className="absolute inset-0 rounded-full border-[1.5px]"
          style={{
            borderColor: accent,
            animation: "bot-ripple-ring 1.5s cubic-bezier(0.22, 1, 0.36, 1) infinite",
          }}
        />
        <span
          className="absolute inset-0 rounded-full border-[1.5px]"
          style={{
            borderColor: accent,
            animation: "bot-ripple-ring 1.5s cubic-bezier(0.22, 1, 0.36, 1) 520ms infinite",
          }}
        />
        <span className="size-[5px] rounded-full" style={{ backgroundColor: accent }} />
      </span>
    );
  }

  return (
    <span aria-hidden className="relative flex h-[12px] w-[20px] shrink-0 items-center overflow-hidden rounded-full bg-inset">
      <span
        className="h-[3px] w-[10px] rounded-full"
        style={{
          backgroundColor: accent,
          animation: "bot-scan-beam 1.2s ease-in-out infinite",
        }}
      />
    </span>
  );
}

const SingleBotThinkingRow = memo(function SingleBotThinkingRow({
  bot,
  locale,
  isStickerContext,
}: {
  bot: MeetingRoomParticipant;
  locale: "zh" | "en";
  isStickerContext: boolean;
}) {
  const [imgFailed, setImgFailed] = useState(false);
  useEffect(() => {
    setImgFailed(false);
  }, [bot.avatarURL]);

  const accent = bot.accentHex || "var(--accent)";
  const spec = resolveBotThinkingSpec(bot, isStickerContext);
  const label = locale === "zh" ? spec.labelZh : spec.labelEn;
  const elapsed = useElapsedSeconds(bot.id);

  const haloStyle: CSSProperties = {
    ["--bot-accent" as string]: accent,
    animation: "bot-avatar-halo 1.8s ease-in-out infinite",
  };

  return (
    <div
      role="status"
      className="flex items-start gap-2.5 pr-6"
      style={{ animation: "fade-up 180ms cubic-bezier(0.23,1,0.32,1) both" }}
    >
      <div
        className="flex size-[36px] shrink-0 items-center justify-center overflow-hidden rounded-[8px] border border-line bg-surface"
        style={
          !bot.avatarURL || imgFailed
            ? { ...haloStyle, backgroundColor: `${accent}20`, color: accent }
            : haloStyle
        }
      >
        {bot.avatarURL && !imgFailed ? (
          <img
            src={bot.avatarURL}
            alt={bot.name}
            onError={() => setImgFailed(true)}
            className="size-full object-cover"
          />
        ) : (
          <span className="text-[13.5px] font-semibold">{bot.name.slice(0, 1)}</span>
        )}
      </div>

      <div className="flex min-w-0 flex-col items-start gap-1">
        <div className="flex items-center gap-1.5">
          <span className="text-[12.5px] font-semibold text-ink-2">{bot.name}</span>
          {bot.roleLabel && (
            <span className="text-[11.5px] text-ink-3">{bot.roleLabel}</span>
          )}
        </div>

        <div
          className="inline-flex items-center gap-2.5 rounded-[12px] rounded-tl-[4px] border border-line bg-surface px-3 py-2 shadow-hairline"
          style={{
            borderColor: `color-mix(in srgb, ${accent} 24%, var(--line))`,
          }}
        >
          <BotKineticGlyph style={spec.style} accent={accent} />
          <span
            className="bg-clip-text text-[12.5px] font-medium text-transparent"
            style={{
              backgroundImage: `linear-gradient(90deg, var(--ink-3) 25%, ${accent} 50%, var(--ink-3) 75%)`,
              backgroundSize: "220% 100%",
              animation: "shimmer-text 1.45s linear infinite",
            }}
          >
            {label}
          </span>
          <span className="font-mono text-[11.5px] text-ink-3 tabular-nums">{elapsed}</span>
        </div>
      </div>
    </div>
  );
});

const MeetingBotThinkingCard = memo(function MeetingBotThinkingCard({
  thinkingBots,
  locale,
  isStickerContext,
}: {
  thinkingBots: MeetingRoomParticipant[];
  locale: "zh" | "en";
  isStickerContext: boolean;
}) {
  if (thinkingBots.length === 0) {
    return (
      <div
        role="status"
        className="flex items-center justify-start"
        style={{ animation: "fade-in 160ms ease-out both" }}
      >
        <div className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1.5 shadow-hairline">
          <span aria-hidden className="flex items-center gap-1">
            {[0, 140, 280].map((delay) => (
              <span
                key={delay}
                className="size-[5px] rounded-full bg-ink-3"
                style={{ animation: `bot-dot-hop 900ms ease-in-out ${delay}ms infinite` }}
              />
            ))}
          </span>
          <span className="text-[12px] font-medium text-ink-2">
            {locale === "zh" ? (isStickerContext ? "群里马上接话" : "成员思考中") : "Thinking"}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {thinkingBots.slice(0, 3).map((bot) => (
        <SingleBotThinkingRow
          key={bot.id}
          bot={bot}
          locale={locale}
          isStickerContext={isStickerContext}
        />
      ))}
    </div>
  );
});

export default MeetingBotThinkingCard;
