export function configureExclusionSelection(form) {
  const master = form.querySelector("[data-exclusion-select-all]");
  const candidates = [...form.querySelectorAll('input[name="urls[]"]')];
  const syncSelection = () => {
    const selected = candidates.filter((candidate) => candidate.checked).length;
    master.checked = selected > 0 && selected === candidates.length;
    master.indeterminate = selected > 0 && !master.checked;
  };

  master.addEventListener("change", () => {
    candidates.forEach((candidate) => { candidate.checked = master.checked; });
    syncSelection();
  });
  candidates.forEach((candidate) => candidate.addEventListener("change", syncSelection));
  master.disabled = candidates.length === 0;
  syncSelection();
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("form[data-exclusion-review]").forEach(configureExclusionSelection);
  });
}
