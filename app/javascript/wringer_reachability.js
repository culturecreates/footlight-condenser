export async function updateWringerReachability(element, fetchStatus = fetch) {
  if (!element || element.dataset.wringerReachabilityInitialized) return;
  element.dataset.wringerReachabilityInitialized = "true";

  try {
    const response = await fetchStatus(element.dataset.wringerReachabilityUrl, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error("Wringer status check failed");
    const { label } = await response.json();
    element.textContent = label;
  } catch {
    element.textContent = "Status unavailable";
  }
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    updateWringerReachability(document.querySelector("[data-wringer-reachability-url]"));
  });
}
