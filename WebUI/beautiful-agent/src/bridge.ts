type WebKitWindow = Window & {
  webkit?: {
    messageHandlers?: {
      cotAgent?: {
        postMessage: (payload: unknown) => void;
      };
    };
  };
};

export function postToNative(type: string, payload: Record<string, unknown> = {}): void {
  const handler = (window as WebKitWindow).webkit?.messageHandlers?.cotAgent;
  if (handler) {
    handler.postMessage({ type, ...payload });
  }
}

export function copyTextWithFallback(text: string): void {
  postToNative("copyText", { text });
  if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
    navigator.clipboard.writeText(text).catch(() => {});
  }
}
