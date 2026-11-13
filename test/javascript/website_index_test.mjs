import assert from "node:assert/strict";
import test from "node:test";
import { configureWebsiteDetails, revealWebsiteGroup } from "../../app/javascript/website_index.js";

function harness() {
  const rows = new Map();
  const buttons = [1, 2].map((id) => {
    const controls = `website-details-${id}`;
    rows.set(controls, { hidden: true });
    return { dataset: {}, hidden: true, textContent: "Details", attributes: { "aria-controls": controls, "aria-expanded": "false" },
      getAttribute(name) { return this.attributes[name]; },
      setAttribute(name, value) { this.attributes[name] = value; },
      handlers: [], addEventListener(name, fn) { this.handlers.push(fn); },
      click() { this.handlers.forEach((fn) => fn()); } };
  });
  const root = { querySelectorAll: () => buttons, getElementById: (id) => rows.get(id) };
  return { root, buttons, rows };
}

test("Details opens and closes only its own row and updates accessible state", () => {
  const { root, buttons, rows } = harness();
  configureWebsiteDetails(root);
  assert.equal(buttons[0].hidden, false);
  assert.equal(rows.get("website-details-1").hidden, true);
  buttons[0].click();
  assert.equal(rows.get("website-details-1").hidden, false);
  assert.equal(rows.get("website-details-2").hidden, true);
  assert.equal(buttons[0].attributes["aria-expanded"], "true");
  assert.equal(buttons[0].textContent, "Close details");
  buttons[0].click();
  assert.equal(rows.get("website-details-1").hidden, true);
  assert.equal(buttons[0].attributes["aria-expanded"], "false");
});

test("reinitialization does not attach duplicate toggles and missing targets stay unavailable", () => {
  const { root, buttons, rows } = harness();
  rows.delete("website-details-2");
  configureWebsiteDetails(root);
  configureWebsiteDetails(root);
  assert.equal(buttons[0].handlers.length, 1);
  assert.equal(buttons[1].hidden, true);
  buttons[0].click();
  assert.equal(rows.get("website-details-1").hidden, false);
});

test("sorting can reopen its category while an unrelated hash cannot open other content", () => {
  const group = { open: false, matches: (selector) => selector === "details.website-index-category" };
  const root = { getElementById: (id) => id === "website-list-unscheduled" ? group : null };
  revealWebsiteGroup(root, "#website-list-unscheduled");
  assert.equal(group.open, true);
  group.open = false;
  revealWebsiteGroup(root, "#unrelated");
  assert.equal(group.open, false);
  revealWebsiteGroup(root, "#website-list-tests");
  assert.equal(group.open, false);
});
