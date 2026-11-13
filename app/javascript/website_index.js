export function configureWebsiteDetails(root = document) {
  root.querySelectorAll("button[data-website-details]").forEach((button) => {
    const row = root.getElementById(button.getAttribute("aria-controls"));
    if (!row || button.dataset.detailsBound) return;
    button.dataset.detailsBound = "true";
    button.hidden = false;
    button.addEventListener("click", () => {
      row.hidden = !row.hidden;
      button.setAttribute("aria-expanded", String(!row.hidden));
      button.textContent = row.hidden ? "Details" : "Close details";
    });
  });
}

export function revealWebsiteGroup(root, hash) {
  if (!/^#website-list-(unscheduled|entities|templates|tests)$/.test(hash)) return;
  const group = root.getElementById(hash.slice(1));
  if (group?.matches("details.website-index-category")) group.open = true;
}

export function configureWebsitePreferences(root = document) {
  root.querySelectorAll("input[data-auto-submit-preference]").forEach((input) => {
    if (input.dataset.preferenceBound || !input.form) return;
    input.dataset.preferenceBound = "true";
    input.addEventListener("change", () => input.form.requestSubmit());
  });
}

if (typeof document !== "undefined") {
  const initialize = () => {
    configureWebsiteDetails();
    configureWebsitePreferences();
    revealWebsiteGroup(document, window.location.hash);
  };
  document.addEventListener("DOMContentLoaded", initialize);
  window.addEventListener("hashchange", () => revealWebsiteGroup(document, window.location.hash));
  if (document.readyState !== "loading") initialize();
}
