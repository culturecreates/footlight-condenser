const RUN_STATES = new Set(["queued", "running", "completed", "failed", "expired"]);

export function followTransitionRun(panel, {
  fetchStatus = (...args) => fetch(...args),
  schedule = (callback, delay) => window.setTimeout(callback, delay),
  cancel = (timer) => window.clearTimeout(timer),
  navigate = (url) => window.location.replace(url),
} = {}) {
  let stopped = false;
  let polling = false;
  let timer;
  let failures = 0;
  const controller = new AbortController();
  const connection = panel.querySelector("[data-run-connection]");
  const reportUrl = panel.dataset.reportUrl;
  const stop = () => {
    stopped = true;
    cancel(timer);
    controller.abort();
  };
  const connectionMessage = (message) => {
    connection.textContent = message;
    connection.hidden = !message;
  };
  const openReport = () => {
    if (!reportUrl.startsWith("/") || reportUrl.startsWith("//") || reportUrl.includes("\\")) {
      throw new Error("Invalid report URL");
    }
    navigate(reportUrl);
  };
  const poll = async () => {
    if (stopped || polling) return;
    polling = true;
    try {
      const response = await fetchStatus(panel.dataset.statusUrl, {
        headers: { Accept: "application/json" }, credentials: "same-origin", cache: "no-store", redirect: "error",
        signal: AbortSignal.any([controller.signal, AbortSignal.timeout(15000)]),
      });
      if (stopped) return;
      if ([401, 403, 404].includes(response.status)) {
        connectionMessage(response.status === 404 ? "This run is no longer available. Refresh status to check again." :
          "Sign-in is required. Refresh status to sign in and resume this run.");
        stop();
        return;
      }
      if (!response.ok) throw new Error("Status unavailable");
      const data = await response.json();
      if (stopped) return;
      if (String(data.run_id) !== panel.dataset.runId || !RUN_STATES.has(data.status) ||
          data.report_url !== reportUrl || !Array.isArray(data.phases_recorded)) throw new Error("Invalid run status");

      failures = 0;
      connectionMessage("");
      panel.querySelector("[data-run-label]").textContent = data.label;
      panel.querySelector("[data-run-message]").textContent = data.message;
      panel.querySelector("[data-run-phases]").textContent = data.phases_recorded.length ?
        `Recorded phases: ${data.phases_recorded.join(", ")}.` : "";
      panel.querySelector("[data-run-completed]").hidden = data.status !== "completed";
      panel.querySelector("[data-run-failed]").hidden = !["failed", "expired"].includes(data.status);
      panel.dataset.status = data.status;
      const terminal = !["queued", "running"].includes(data.status);
      panel.setAttribute("aria-busy", String(!terminal));
      if (terminal) {
        if (data.status === "completed") openReport();
        stop();
      }
    } catch (_error) {
      if (!stopped) {
        failures += 1;
        connectionMessage("Status temporarily unavailable. Retrying automatically; you can also refresh status.");
      }
    } finally {
      polling = false;
      if (!stopped) timer = schedule(poll, Math.min(30000, 5000 * (2 ** Math.min(failures, 3))));
    }
  };

  panel.querySelector("[data-run-refresh]").addEventListener("click", (event) => {
    if (stopped) return; // Keep the ordinary link working after terminal or authentication errors.
    event.preventDefault();
    cancel(timer);
    poll();
  });
  if (panel.dataset.status === "completed") {
    try { openReport(); } catch (_error) { connectionMessage("Open the completed report using the link below."); }
    stop();
  } else if (["failed", "expired"].includes(panel.dataset.status)) {
    stop();
  } else {
    poll();
  }
  return stop;
}

export function configureTransitionOptions(form) {
  const mode = form.querySelector('[name="check_options[sample_mode]"]');
  const size = form.querySelector('[name="check_options[sample_size]"]');
  const update = () => {
    size.disabled = mode.value !== "count";
    size.required = mode.value === "count";
  };
  mode.addEventListener("change", update);
  update();
}

function initializeTransitionChecks() {
  document.querySelectorAll("[data-transition-run]:not([data-initialized])").forEach((panel) => {
    panel.dataset.initialized = "true";
    const stop = followTransitionRun(panel);
    window.addEventListener("pagehide", stop, { once: true });
  });
  document.querySelectorAll(".website-transition-check-form:not([data-initialized])").forEach((form) => {
    form.dataset.initialized = "true";
    configureTransitionOptions(form);
  });
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", initializeTransitionChecks);
  document.addEventListener("turbo:load", initializeTransitionChecks);
  window.addEventListener("pageshow", (event) => {
    // Back/forward-cache restoration does not fire DOMContentLoaded. Re-read
    // this run's GET page after pagehide stopped its old polling loop.
    if (event.persisted && document.querySelector("[data-transition-run]")) window.location.reload();
  });
}
