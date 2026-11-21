import assert from "node:assert/strict";
import test from "node:test";
import { configureWebsiteDetails, configureWebsitePreferences, revealWebsiteGroup, configureTransitionSelection } from "../../app/javascript/website_index.js";

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

test("preferred controls submit the owning form once and initialization is idempotent", () => {
  let submitted = 0;
  const handlers = [];
  const input = { dataset: {}, form: { requestSubmit: () => submitted++ }, addEventListener: (name, fn) => handlers.push(fn) };
  const detached = { dataset: {}, form: null };
  const root = { querySelectorAll: () => [input, detached] };
  configureWebsitePreferences(root);
  configureWebsitePreferences(root);
  assert.equal(handlers.length, 1);
  handlers[0]();
  assert.equal(submitted, 1);
});

test("master selection covers every matching event checkbox including closed categories and preserves partial selection", () => {
  const input = () => ({ checked: false, handlers: {}, addEventListener(name, fn) { this.handlers[name] = fn; } });
  const inputs = [input(), input(), input()];
  const master = input();
  const count = { textContent: "" };
  const submit = { disabled: false };
  const label = { hidden: true };
  const controls = { "[data-transition-master]": master, "[data-transition-selection-count]": count, "[data-transition-submit]": submit, "[data-transition-master-label]": label };
  const form = { dataset: {}, querySelector: (selector) => controls[selector] };
  const root = { getElementById: () => form, querySelectorAll: () => inputs };
  configureTransitionSelection(root);
  assert.equal(label.hidden, false);
  assert.equal(submit.disabled, true);
  master.checked = true;
  master.handlers.change();
  assert(inputs.every((field) => field.checked));
  assert.equal(count.textContent, "3 of 3 matching event sites selected");
  inputs[1].checked = false;
  inputs[1].handlers.change();
  assert.equal(master.indeterminate, true);
  assert.equal(master.checked, false);
  assert.equal(submit.disabled, false);
});
