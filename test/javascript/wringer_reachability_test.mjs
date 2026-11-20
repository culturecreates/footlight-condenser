import assert from "node:assert/strict";
import test from "node:test";
import { updateWringerReachability } from "../../app/javascript/wringer_reachability.js";

function statusElement() {
  return { dataset: { wringerReachabilityUrl: "/options/wringer_reachability" }, textContent: "Checking…" };
}

test("navigation displays the result of the Condenser probe", async () => {
  const element = statusElement();
  await updateWringerReachability(element, async (url) => {
    assert.equal(url, "/options/wringer_reachability");
    return { ok: true, json: async () => ({ label: "Responded (HTTP 403)" }) };
  });
  assert.equal(element.textContent, "Responded (HTTP 403)");
});

test("navigation distinguishes a failed status request from an unreachable Wringer", async () => {
  const element = statusElement();
  await updateWringerReachability(element, async () => ({ ok: false }));
  assert.equal(element.textContent, "Status unavailable");
});
