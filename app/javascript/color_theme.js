(() => {
  const storageKey = "condenser.colorTheme";
  const root = document.documentElement;

  function updateControl() {
    const button = document.querySelector("[data-theme-toggle]");
    if (button) {
      button.setAttribute("aria-pressed", String(root.dataset.theme === "dark"));
      button.hidden = false;
    }
  }

  function restoreTheme() {
    try {
      root.dataset.theme = window.localStorage.getItem(storageKey) === "dark" ? "dark" : "light";
    } catch {
      // Storage can be unavailable. Keep the current theme.
    }
  }

  restoreTheme();
  document.addEventListener("click", (event) => {
    if (!event.target.closest("[data-theme-toggle]")) return;
    const theme = root.dataset.theme === "dark" ? "light" : "dark";
    root.dataset.theme = theme;
    updateControl();
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
