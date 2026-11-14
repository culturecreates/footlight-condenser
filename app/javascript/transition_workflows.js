export function followWorkflow(root, { request = globalThis.fetch, schedule = globalThis.setTimeout, cancel = globalThis.clearTimeout } = {}) {
  if (root.dataset.workflowBound) return;
  root.dataset.workflowBound = "true";
  const target = root.querySelector("[data-workflow-status]");
  const note = root.querySelector("[data-workflow-poll-note]");
  const filter = root.querySelector("[data-workflow-filter]");
  const applyFilter = () => {
    root.querySelectorAll("[data-workflow-result]").forEach((row) => {
      const state = row.dataset.workflowResult;
      const value = filter?.value || "all";
      row.hidden = !(value === "all" || value === state || value === "attention" && ["attention", "recovery_failed"].includes(state) || value === "pending" && ["queued", "running"].includes(state));
    });
  };
  filter?.addEventListener("change", applyFilter);
  let failures = 0;
  let stopped = false;
  let polling = false;
  let timer;
  const controller = new AbortController();
  const stop = () => { stopped = true; cancel(timer); controller.abort(); };
  const poll = async () => {
    if (stopped || polling) return;
    polling = true;
    try {
      const response = await request(root.dataset.statusUrl, { credentials: "same-origin", cache: "no-store", redirect: "error",
        signal: AbortSignal.any([controller.signal, AbortSignal.timeout(15000)]), headers: { Accept: "application/json" } });
      if (stopped) return;
      if ([401, 403, 404].includes(response.status)) { note.textContent = "Refresh this report to sign in again or check whether it is still available."; stop(); return; }
      if (!response.ok) throw new Error("Status unavailable");
      const data = await response.json();
      if (stopped) return;
      if (typeof data.html !== "string" || typeof data.finished !== "boolean") throw new Error("Invalid status");
      const open = [...target.querySelectorAll("details[id][open]")].map((details) => details.id);
      const scroll = target.querySelector("[data-workflow-scroll]")?.scrollLeft || 0;
      const focused = globalThis.document?.activeElement;
      const focusId = focused && target.contains(focused) ? focused.id : null;
      target.innerHTML = data.html;
      open.forEach((id) => { const details = target.querySelector(`#${id}`); if (details) details.open = true; });
      const scroller = target.querySelector("[data-workflow-scroll]");
      if (scroller) scroller.scrollLeft = scroll;
      if (focusId && /^[\w-]+$/.test(focusId)) target.querySelector(`#${focusId}`)?.focus({ preventScroll: true });
      applyFilter();
      failures = 0;
      note.textContent = data.finished ? "Workflow finished. Results remain available at this address." : "Following this workflow automatically.";
      if (data.finished) stop();
    } catch {
      if (!stopped) {
        failures++;
        note.textContent = "Status temporarily unavailable. Retrying; refreshing this page will not start another workflow.";
      }
    } finally {
      polling = false;
      if (!stopped) timer = schedule(poll, Math.min(30000, 5000 * 2 ** Math.min(failures, 3)));
    }
  };
  timer = schedule(poll, 1000);
  return { poll, applyFilter, stop };
}

if (typeof document !== "undefined") {
  const initialize = () => document.querySelectorAll("[data-workflow-follow]").forEach((root) => {
    const follow = followWorkflow(root);
    if (follow) window.addEventListener("pagehide", follow.stop, { once: true });
  });
  document.addEventListener("DOMContentLoaded", initialize);
  if (document.readyState !== "loading") initialize();
  window.addEventListener("pageshow", (event) => {
    if (event.persisted && document.querySelector("[data-workflow-follow]")) window.location.reload();
  });
}
