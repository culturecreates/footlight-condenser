const CARD_KEY = "operatorContextCardOpen";
const DOMAINS_KEY = "operatorContextDomains";

function readDomainState() {
  try {
    return JSON.parse(window.localStorage.getItem(DOMAINS_KEY) || "{}");
  } catch (_error) {
    return {};
  }
}

function writeDomainState(state) {
  window.localStorage.setItem(DOMAINS_KEY, JSON.stringify(state));
}

function restoreOperatorContextCard() {
  const card = document.querySelector("[data-operator-context-card]");
  if (!card) return;
  if (card.dataset.operatorContextInitialized === "true") return;

  card.dataset.operatorContextInitialized = "true";

  const storedCardOpen = window.localStorage.getItem(CARD_KEY);
  if (storedCardOpen === "true") card.open = true;
  if (storedCardOpen === "false") card.open = false;

  // Domain open state is intentionally shared across operator page types so
  // the same diagnostic sections stay open as people move between pages.
  const domainState = readDomainState();
  card.querySelectorAll("[data-context-domain]").forEach((section) => {
    const key = section.dataset.contextDomain;
    if (Object.prototype.hasOwnProperty.call(domainState, key)) {
      section.open = domainState[key];
    }
  });

  card.addEventListener("toggle", () => {
    window.localStorage.setItem(CARD_KEY, card.open ? "true" : "false");
  });

  card.querySelectorAll("[data-context-domain]").forEach((section) => {
    section.addEventListener("toggle", () => {
      const nextState = readDomainState();
      nextState[section.dataset.contextDomain] = section.open;
      writeDomainState(nextState);
    });
  });
}

document.addEventListener("DOMContentLoaded", restoreOperatorContextCard);
document.addEventListener("turbo:load", restoreOperatorContextCard);
