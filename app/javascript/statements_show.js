function initStatementsShow() {
  const sourceRoot = document.querySelector(".dsl-source");
  if (!sourceRoot) return;

  const TRACE_VIEW_MODE = Number(sourceRoot.dataset.traceViewMode || 0);

  window.toggleTraceExpandable = function(el) {
    if (!el || !el.dataset) return;
    const expanded = el.classList.toggle("expanded");
    const full = el.dataset.full;
    const truncated = el.dataset.truncated;
    el.textContent = expanded ? full : truncated;
  };

  window.toggleDslStep = function(el) {
    if (TRACE_VIEW_MODE !== 4 || !el) return;

    const step = el.dataset.step;
    if (!step) return;

    el.classList.toggle("active");

    const details = document.querySelector('.dsl-step-details[data-step="' + step + '"]');
    if (!details) return;

    const isVisible = details.style.display === "block";
    details.style.display = isVisible ? "none" : "block";

    if (!isVisible) {
      const rect = details.getBoundingClientRect();
      const offset = window.innerHeight / 2 - rect.height / 2;

      window.scrollTo({
        top: window.scrollY + rect.top - offset,
        behavior: "smooth"
      });
    }
  };

  const firstDslError = document.querySelector(".dsl-step.dsl-error");
  const firstTraceError = document.querySelector(".trace-first-error");

  if (TRACE_VIEW_MODE === 4) {
    if (firstDslError) window.toggleDslStep(firstDslError);
    return;
  }

  if (!firstTraceError) return;

  const rect = firstTraceError.getBoundingClientRect();
  const offset = window.innerHeight / 2 - rect.height / 2;

  window.scrollTo({
    top: window.scrollY + rect.top - offset,
    behavior: "smooth"
  });
}

document.addEventListener("DOMContentLoaded", initStatementsShow);
document.addEventListener("turbo:load", initStatementsShow);
