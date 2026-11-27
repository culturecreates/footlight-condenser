import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const script = readFileSync(new URL("../../app/javascript/color_theme.js", import.meta.url), "utf8");
const storageKey = "condenser.colorTheme";

function loadPage(preferences = new Map(), blockedStorage = false) {
  const root = { dataset: {} };
  const select = {
    hidden: true,
    value: "light",
    matches: (selector) => selector === "[data-theme-select]"
  };
  const listeners = new Map();
  const document = {
    documentElement: root,
    querySelector: () => select,
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
    select,
    ready: () => listeners.get("DOMContentLoaded")(),
    chooseTheme: (value) => {
      select.value = value;
      listeners.get("change")({ target: select });
    },
    restoreFromHistory: () => listeners.get("pageshow")({ persisted: true })
  };
}

test("Kolada persists across navigation and reflects changes when returning through browser history", () => {
  const preferences = new Map();
  const page = loadPage(preferences);
  page.ready();
  assert.equal(page.root.dataset.theme, "light");
  assert.equal(page.select.hidden, false);
  assert.equal(page.select.value, "light");

  page.chooseTheme("kolada");
  assert.equal(page.root.dataset.theme, "kolada");
  assert.equal(preferences.get(storageKey), "kolada");

  const nextPage = loadPage(preferences);
  assert.equal(nextPage.root.dataset.theme, "kolada");
  nextPage.ready();
  assert.equal(nextPage.select.value, "kolada");
  nextPage.chooseTheme("light");
  assert.equal(nextPage.root.dataset.theme, "light");
  assert.equal(preferences.get(storageKey), "light");
  page.restoreFromHistory();
  assert.equal(page.root.dataset.theme, "light");
  assert.equal(page.select.value, "light");
});

test("existing Light and Dark preferences still work and unknown saved values fall back to Light", () => {
  for (const [value, expected] of [["light", "light"], ["dark", "dark"], ["invalid", "light"]]) {
    const page = loadPage(new Map([[storageKey, value]]));
    assert.equal(page.root.dataset.theme, expected);
    page.ready();
    assert.equal(page.select.value, expected);
  }
});

test("the appearance selector works on the current page when browser storage is unavailable", () => {
  const page = loadPage(new Map(), true);
  page.ready();
  page.chooseTheme("kolada");
  assert.equal(page.root.dataset.theme, "kolada");
});
