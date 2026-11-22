(() => {
  const storageKey = "condenser.colorTheme";
  const themes = new Set(["light", "dark", "kolada"]);
  const root = document.documentElement;

  function updateControl() {
    const select = document.querySelector("[data-theme-select]");
    if (select) {
      select.value = root.dataset.theme || "light";
      select.hidden = false;
    }
  }

  function restoreTheme() {
    try {
      const savedTheme = window.localStorage.getItem(storageKey);
      root.dataset.theme = themes.has(savedTheme) ? savedTheme : "light";
    } catch {
      // Storage can be unavailable. Keep the current theme.
    }
  }

  restoreTheme();
  document.addEventListener("change", (event) => {
    if (!event.target.matches("[data-theme-select]")) return;
    const theme = event.target.value;
    if (!themes.has(theme)) return;
    root.dataset.theme = theme;
    try {
      window.localStorage.setItem(storageKey, theme);
    } catch {
      // The current page can still apply the theme.
    }
  });
  document.addEventListener("DOMContentLoaded", updateControl);
  document.addEventListener("turbo:load", updateControl);
  window.addEventListener("pageshow", (event) => {
    if (!event.persisted) return;
    restoreTheme();
    updateControl();
  });
})();
