import assert from "node:assert/strict";
import test from "node:test";
import { setImmediate } from "node:timers/promises";
import { configureTransitionOptions, followTransitionRun } from "../../app/javascript/transition_checks.js";

const reportUrl = "/distillator/shadow_report/134?run_id=7#transition-report-summary";
const payload = (status, overrides = {}) => ({
  run_id: 7, status, label: status, message: `Run is ${status}`, phases_recorded: [], report_url: reportUrl, ...overrides,
});
const response = (data, status = 200) => ({ ok: status === 200, status, json: async () => data });

// Only the panel's DOM interface is substituted; the production polling,
// response validation, retry scheduling and navigation all execute unchanged.
function harness(responses, initialState = "queued") {
  const elements = new Map();
  const panel = {
    dataset: { runId: "7", status: initialState, statusUrl: "/distillator/transition_checks/7.json", reportUrl },
    attributes: {},
    setAttribute(key, value) { this.attributes[key] = value; },
    querySelector(selector) {
      if (!elements.has(selector)) elements.set(selector, { hidden: true, textContent: "", handlers: {},
        addEventListener(name, callback) { this.handlers[name] = callback; } });
      return elements.get(selector);
    },
  };
  const timers = [];
  const requests = [];
  const navigation = [];
  const stop = followTransitionRun(panel, {
    async fetchStatus(url, options) {
      requests.push({ url, options });
      const next = responses.shift();
      if (next instanceof Error) throw next;
      assert.ok(next, "No unexpected extra poll");
      return next;
    },
    schedule(callback, delay) { const timer = { callback, delay }; timers.push(timer); return timer; },
    cancel(timer) { if (timer) timer.cancelled = true; },
    navigate(url) { navigation.push(url); },
  });
  return { panel, requests, navigation, stop,
    element: (key) => panel.querySelector(`[data-run-${key}]`),
    pendingTimers: () => timers.filter((timer) => !timer.cancelled),
    async nextPoll() {
      const timer = timers.find((entry) => !entry.cancelled);
      assert.ok(timer, "A retry was scheduled");
      timer.cancelled = true;
      await timer.callback();
    },
  };
}

test("queued -> running -> completed opens only this run's report and stops polling", async () => {
  const h = harness([response(payload("queued")), response(payload("running", { phases_recorded: ["Fetch"] })), response(payload("completed"))]);
  await setImmediate();
  assert.equal(h.element("label").textContent, "queued");
  await h.nextPoll();
  assert.equal(h.element("phases").textContent, "Recorded phases: Fetch.");
  assert.equal(h.panel.attributes["aria-busy"], "true");
  assert.deepEqual(h.navigation, []);
  await h.nextPoll();
  assert.deepEqual(h.navigation, [reportUrl]);
  assert.equal(h.panel.attributes["aria-busy"], "false");
  assert.equal(h.element("completed").hidden, false);
  assert.equal(h.pendingTimers().length, 0);
  assert.ok(h.requests.every(({ url, options }) => url.endsWith("/7.json") && !options.method && options.cache === "no-store"));
});

for (const status of ["failed", "expired"]) {
  test(`${status} exposes retry without navigating to an older comparison`, async () => {
    const h = harness([response(payload(status, { message: "Check could not finish" }))]);
    await setImmediate();
    assert.equal(h.element("failed").hidden, false);
    assert.equal(h.element("message").textContent, "Check could not finish");
    assert.deepEqual(h.navigation, []);
    assert.equal(h.pendingTimers().length, 0);
  });
}

test("reloading the same status URL resumes observing the same run without submitting a job", async () => {
  const first = harness([response(payload("running"))]);
  await setImmediate();
  first.stop();
  const resumed = harness([response(payload("completed"))], "running");
  await setImmediate();
  assert.equal(first.requests[0].url, resumed.requests[0].url);
  assert.deepEqual(resumed.navigation, [reportUrl]);
  assert.equal(resumed.requests.length, 1);
});

test("a temporary connection failure retries with backoff and recovers", async () => {
  const h = harness([new Error("offline"), response(payload("running")), response(payload("completed"))]);
  await setImmediate();
  assert.match(h.element("connection").textContent, /temporarily unavailable/);
  assert.equal(h.pendingTimers()[0].delay, 10000);
  await h.nextPoll();
  assert.equal(h.element("connection").hidden, true);
  assert.equal(h.pendingTimers()[0].delay, 5000);
  await h.nextPoll();
  assert.deepEqual(h.navigation, [reportUrl]);
});

test("a response for another run cannot redirect or replace the visible result", async () => {
  const h = harness([response(payload("completed", { run_id: 8, report_url: "/distillator/shadow_report/134?run_id=8" }))]);
  await setImmediate();
  assert.deepEqual(h.navigation, []);
  assert.equal(h.panel.dataset.status, "queued");
  assert.equal(h.element("connection").hidden, false);
  h.stop();
});

test("authentication loss stops polling and leaves the refresh link available to sign in", async () => {
  const h = harness([response(null, 401)]);
  await setImmediate();
  assert.match(h.element("connection").textContent, /Sign-in is required/);
  assert.equal(h.pendingTimers().length, 0);
  let prevented = false;
  h.element("refresh").handlers.click({ preventDefault() { prevented = true; } });
  assert.equal(prevented, false);
  assert.deepEqual(h.navigation, []);
});

test("leaving the page prevents a late response from navigating", async () => {
  let resolve;
  const deferred = new Promise((done) => { resolve = done; });
  const h = harness([deferred]);
  h.stop();
  resolve(response(payload("completed")));
  await setImmediate();
  assert.ok(h.requests[0].options.signal.aborted);
  assert.deepEqual(h.navigation, []);
  assert.equal(h.pendingTimers().length, 0);
});

test("a completed page opens its pinned report without polling; a failed page keeps retry visible", () => {
  const completed = harness([], "completed");
  assert.deepEqual(completed.navigation, [reportUrl]);
  assert.equal(completed.requests.length, 0);
  const failed = harness([], "failed");
  assert.equal(failed.requests.length, 0);
  assert.deepEqual(failed.navigation, []);
});

test("fixed page count is editable and required only when the fixed sampling mode is selected", () => {
  let onChange;
  const mode = { value: "default", addEventListener(_event, callback) { onChange = callback; } };
  const size = { value: 10 };
  configureTransitionOptions({ querySelector(selector) { return selector.includes("sample_mode") ? mode : size; } });
  assert.equal(size.disabled, true);
  mode.value = "count";
  onChange();
  assert.equal(size.disabled, false);
  assert.equal(size.required, true);
  mode.value = "all";
  onChange();
  assert.equal(size.disabled, true);
  assert.equal(size.required, false);
  assert.equal(size.value, 10);
});

test("restoring a status page with browser Back resumes by reloading its existing GET URL", async () => {
  const listeners = new Map();
  let reloads = 0;
  globalThis.document = { addEventListener() {}, querySelector() { return {}; } };
  globalThis.window = { addEventListener(name, callback) { listeners.set(name, callback); }, location: { reload() { reloads += 1; } } };
  try {
    await import("../../app/javascript/transition_checks.js?back-navigation-test");
    const restore = listeners.get("pageshow");
    restore({ persisted: false });
    assert.equal(reloads, 0);
    restore({ persisted: true });
    assert.equal(reloads, 1);
    document.querySelector = () => null;
    restore({ persisted: true });
    assert.equal(reloads, 1, "Other pages do not reload");
  } finally {
    delete globalThis.document;
    delete globalThis.window;
  }
});
