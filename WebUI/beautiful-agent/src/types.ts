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
  attachedDocuments?: string[];
  delegatedBotID?: string;
  delegatedBotName?: string;
  delegatedModel?: string;
};

export type SessionSummary = {
  id: string;
  title: string;
  isPinned: boolean;
  messageCount?: number;
  updatedAt?: number;
  workspaceID?: string | null;
  workspacePath?: string | null;
  workspaceName?: string | null;
  sortOrder?: number;
};

export type WorkspaceOption = {
  id: string;
  path: string;
  name: string;
  folderPath?: string | null;
  subtitle: string;
  isFolderBacked: boolean;
  isOpenInEditor: boolean;
};

export type DocumentMentionItem = {
  id: string;
  title: string;
  desc: string;
  sourceKind: "open_tab" | "stored_doc" | "weekly_report" | "workspace_file";
  filePath?: string | null;
  isActive?: boolean;
};

export type BotMentionItem = {
  id: string;
  name: string;
  nickname: string;
  handle: string;
  tagline: string;
  accentHex: string;
  model?: string | null;
};

export type AttachedDocumentRef = {
  id: string;
  title: string;
  sourceKind: DocumentMentionItem["sourceKind"];
  filePath?: string | null;
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

export type ButlerProactiveCard = {
  id: string;
  badge: string;
  title: string;
  subtitle: string;
  prompt: string;
  icon: "market" | "podcast" | "news" | "memory" | "sparkle";
};

export type ButlerBackgroundWorker = {
  id: string;
  title: string;
  status: "running" | "done" | "error";
  detail?: string;
  actionBoard?: string;
  actionQuery?: string;
  updatedAtMs: number;
};

export type MeetingRoomMessage = {
  id: string;
  role: "user" | "bot";
  botID?: string | null;
  botName?: string | null;
  botHandle?: string | null;
  botAccentHex?: string | null;
  botRoleLabel?: string | null;
  text: string;
  status: "speaking" | "done" | "error";
  receipts: string[];
  delegatedFromButler: boolean;
  createdAtMs: number;
};

export type MeetingRoomParticipant = {
  id: string;
  name: string;
  nickname: string;
  handle: string;
  roleLabel: string;
  accentHex: string;
  status: "idle" | "speaking" | "done" | "updated";
  todayBadge: string;
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
  greetingSubtitle?: string | null;
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
  availableWorkspaces?: WorkspaceOption[];
  availableDocuments?: DocumentMentionItem[];
  availableBots?: BotMentionItem[];
  themePageHex?: string | null;
  themeCanvasHex?: string | null;
  proactiveCards?: ButlerProactiveCard[];
  backgroundWorkers?: ButlerBackgroundWorker[];
  meetingRoomActive?: boolean;
  meetingRoomIsConvening?: boolean;
  meetingRoomMessages?: MeetingRoomMessage[];
  meetingRoomBots?: MeetingRoomParticipant[];
};

export type StreamPatch = {
  messageId: string;
  text?: string;
  thinking?: string;
  thinkingDurationMs?: number;
  steps?: ThinkingStep[];
  statusLabel?: string;
};
