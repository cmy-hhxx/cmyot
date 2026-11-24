export type AgentMode = "butler" | "news";

export type EffortLevel = "simple" | "balanced" | "deep";

export type ThinkingStep = {
  id: string;
  label: string;
  chip?: string;
  status: "running" | "done" | "error";
  mono?: boolean;
  detail?: string[];
  durationMs?: number;
  kind?: "thinking" | "tool";
  startedAtMs?: number;
};

export type ToolReceipt = {
  id: string;
  label: string;
  detail?: string;
  status?: "done" | "error";
};

export type AgentMessage = {
  id: string;
  role: "user" | "assistant";
  text: string;
  thinking?: string;
  thinkingDurationMs?: number;
  steps?: ThinkingStep[];
  toolChips?: ToolReceipt[];
  followUps?: string[];
  isStreaming?: boolean;
  isError?: boolean;
  quoteContext?: string;
  createdAt?: number;
};

export type SessionSummary = {
  id: string;
  title: string;
  isPinned: boolean;
  messageCount?: number;
  updatedAt?: number;
};

export type ModelOption = {
  id: string;
  modelID: string;
  title: string;
  endpointID?: string;
  tag?: string;
  isFlagship?: boolean;
};

export type QuickSuggestion = {
  id: string;
  label: string;
  prompt: string;
  icon?: "stock" | "news" | "doc" | "search" | "spark" | "note" | "code" | "memory";
};

export type ContextSourceItem = {
  key: string;
  name: string;
  desc: string;
  glyph: "doc" | "selection" | "market" | "news" | "memory" | "globe";
  insertText: string;
};

export type SlashCommandItem = {
  key: string;
  name: string;
  desc: string;
  insertText: string;
};

export type HostState = {
  mode: AgentMode;
  isDark: boolean;
  locale: "zh" | "en";
  botName: string;
  botNickname: string;
  botAvatarDataURL?: string | null;
  piAvailable: boolean;
  piStatusLabel?: string;
  isPinnedPanel?: boolean;
  isDockedPane?: boolean;
  showSidebar?: boolean;
  sessions: SessionSummary[];
  activeSessionID: string;
  messages: AgentMessage[];
  isStreaming: boolean;
  streamingStatusLabel?: string;
  errorMessage?: string | null;
  placeholder: string;
  greetingName?: string;
  greetingSubtitle?: string;
  articleTitle?: string;
  articleSource?: string;
  quotedExcerpt?: string | null;
  availableModels: ModelOption[];
  selectedModelID: string;
  selectedModelTitle: string;
  effort?: EffortLevel;
  suggestions: QuickSuggestion[];
  contextSources: ContextSourceItem[];
  slashCommands: SlashCommandItem[];
};

export type StreamPatch = {
  messageId: string;
  text?: string;
  thinking?: string;
  thinkingDurationMs?: number;
  steps?: ThinkingStep[];
  statusLabel?: string;
};
