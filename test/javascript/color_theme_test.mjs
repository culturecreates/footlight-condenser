import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const script = readFileSync(new URL("../../app/javascript/color_theme.js", import.meta.url), "utf8");
const storageKey = "condenser.colorTheme";

function loadPage(preferences = new Map(), blockedStorage = false) {
  const root = { dataset: {} };
  const button = {
    hidden: true,
    attributes: {},
    setAttribute(name, value) { this.attributes[name] = value; }
  };
  const listeners = new Map();
  const document = {
    documentElement: root,
    querySelector: () => button,
    addEventListener: (name, callback) => listeners.set(name, callback)
  };
  const window = {
    addEventListener: (name, callback) => listeners.set(name, callback),
    get localStorage() {
      if (blockedStorage) throw new Error("Storage is unavailable");
      return {
        getItem: (key) => preferences.get(key),
        setItem: (key, value) => preferences.set(key, value)
      };
    }
  };
  runInNewContext(script, { document, window });

  return {
    root,
    button,
    ready: () => listeners.get("DOMContentLoaded")(),
    toggle: () => listeners.get("click")({ target: { closest: () => button } }),
    restoreFromHistory: () => listeners.get("pageshow")({ persisted: true })
  };
}

test("dark mode remembers the choice and restores it before page ready", () => {
  const preferences = new Map();
  const page = loadPage(preferences);
  page.ready();
  assert.notEqual(page.root.dataset.theme, "dark");
  assert.equal(page.button.hidden, false);
  assert.equal(page.button.attributes["aria-pressed"], "false");

  page.toggle();
  assert.equal(page.root.dataset.theme, "dark");
  assert.equal(page.button.attributes["aria-pressed"], "true");
  assert.equal(preferences.get(storageKey), "dark");

  const nextPage = loadPage(preferences);
  assert.equal(nextPage.root.dataset.theme, "dark");
  nextPage.ready();
  assert.equal(nextPage.button.attributes["aria-pressed"], "true");
  nextPage.toggle();
  assert.equal(nextPage.root.dataset.theme, "light");
  assert.equal(preferences.get(storageKey), "light");
  page.restoreFromHistory();
  assert.equal(page.root.dataset.theme, "light");
  assert.equal(page.button.attributes["aria-pressed"], "false");
});

test("the switch works on the current page when browser storage is unavailable", () => {
  const page = loadPage(new Map(), true);
  page.ready();
  page.toggle();
  assert.equal(page.root.dataset.theme, "dark");
  assert.equal(page.button.attributes["aria-pressed"], "true");
});
