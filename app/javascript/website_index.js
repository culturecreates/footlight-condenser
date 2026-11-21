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

export function configureTransitionSelection(root = document) {
  const form = root.getElementById("website-transition-batch");
  if (!form || form.dataset.selectionBound) return;
  form.dataset.selectionBound = "true";
  const inputs = [...root.querySelectorAll("input[data-transition-site]")];
  const master = form.querySelector("[data-transition-master]");
  const count = form.querySelector("[data-transition-selection-count]");
  const submit = form.querySelector("[data-transition-submit]");
  form.querySelector("[data-transition-master-label]").hidden = false;
  const update = () => {
    const selected = inputs.filter((input) => input.checked).length;
    count.textContent = `${selected} of ${inputs.length} matching event sites selected`;
    master.checked = inputs.length > 0 && selected === inputs.length;
    master.indeterminate = selected > 0 && selected < inputs.length;
    master.disabled = inputs.length === 0;
    submit.disabled = selected === 0;
  };
  master.addEventListener("change", () => { inputs.forEach((input) => { input.checked = master.checked; }); update(); });
  inputs.forEach((input) => input.addEventListener("change", update));
  update();
}

if (typeof document !== "undefined") {
  const initialize = () => {
    configureWebsiteDetails();
    configureWebsitePreferences();
    configureTransitionSelection();
    revealWebsiteGroup(document, window.location.hash);
  };
  document.addEventListener("DOMContentLoaded", initialize);
  window.addEventListener("hashchange", () => revealWebsiteGroup(document, window.location.hash));
  if (document.readyState !== "loading") initialize();
}
