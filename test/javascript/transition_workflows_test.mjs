import test from "node:test";
import assert from "node:assert/strict";
import { followWorkflow } from "../../app/javascript/transition_workflows.js";

function harness(request) {
  const scheduled = [];
  const target = { innerHTML: "Original", querySelectorAll: () => [], querySelector: () => null };
  const note = { textContent: "" };
  const rows = ["passed", "attention", "running"].map((status) => ({ dataset: { workflowResult: status }, hidden: false }));
  const filter = { value: "all", addEventListener: () => {} };
  const root = { dataset: { statusUrl: "/distillator/site_transitions/1.json" },
    querySelector: (selector) => ({ "[data-workflow-status]": target, "[data-workflow-poll-note]": note, "[data-workflow-filter]": filter })[selector],
    querySelectorAll: () => rows };
  const follow = followWorkflow(root, { request, schedule: (fn, ms) => scheduled.push({ fn, ms }), cancel: () => {} });
  return { target, note, rows, filter, follow, scheduled };
}

test("completed polling updates results once and stops without launching jobs", async () => {
  const state = harness(async () => ({ ok: true, status: 200, json: async () => ({ html: "Finished result", finished: true }) }));
  await state.follow.poll();
  assert.equal(state.target.innerHTML, "Finished result");
  assert.match(state.note.textContent, /Workflow finished/);
  assert.equal(state.scheduled.length, 1);
});

test("network failures retain prior evidence and retry with backoff", async () => {
  const state = harness(async () => { throw new Error("offline"); });
  await state.follow.poll();
  assert.equal(state.target.innerHTML, "Original");
  assert.equal(state.scheduled.at(-1).ms, 10000);
  assert.match(state.note.textContent, /will not start another/);
});

test("authentication failures stop and group status filters remain local", async () => {
  const state = harness(async () => ({ ok: false, status: 401 }));
  await state.follow.poll();
  assert.equal(state.scheduled.length, 1);
  state.filter.value = "attention";
  state.follow.applyFilter();
  assert.deepEqual(state.rows.map((row) => row.hidden), [true, false, true]);
});

test("stopping a page ignores a late status response", async () => {
  let resolve;
  const state = harness(() => new Promise((done) => { resolve = done; }));
  const running = state.follow.poll();
  state.follow.stop();
  resolve({ ok: true, status: 200, json: async () => ({ html: "Late", finished: true }) });
  await running;
  assert.equal(state.target.innerHTML, "Original");
});
