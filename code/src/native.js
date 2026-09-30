// The editor can also run in a browser for development and tests.
export const isNativeApp = !!window.webkit?.messageHandlers?.app;

export function sendToApp(action, extra = {}) {
  if (isNativeApp) window.webkit.messageHandlers.app.postMessage({ action, ...extra });
}
