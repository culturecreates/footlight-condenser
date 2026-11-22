const hoverDelay = 300;
const leaveDelay = 350;
const gap = 10;
const minimumHoverWidth = 640;

function positionPreview(panel, trigger) {
  const anchor = trigger.getBoundingClientRect();
  const { width, height } = panel.getBoundingClientRect();
  const maxX = window.innerWidth - width - gap;
  const maxY = window.innerHeight - height - gap;
  const leftSpace = anchor.left - width - gap;
  const rightSpace = anchor.right + gap;
  const beside = leftSpace >= gap || rightSpace <= maxX;
  const x = leftSpace >= gap ? leftSpace : rightSpace <= maxX ? rightSpace : anchor.right - width;
  let y = anchor.top - 42;
  if (!beside) {
    const below = anchor.bottom + gap;
    const above = anchor.top - height - gap;
    y = below <= maxY ? below : above >= gap ? above : anchor.top < window.innerHeight / 2 ? maxY : gap;
  }
  panel.style.left = `${Math.max(gap, Math.min(x, maxX))}px`;
  panel.style.top = `${Math.max(gap, Math.min(y, maxY))}px`;
}

function initializePreview() {
  const panel = document.querySelector("#source-page-preview");
  if (!panel || typeof panel.showPopover !== "function") return;

  const frame = panel.querySelector("iframe");
  const urlLabel = panel.querySelector("[data-preview-url]");
  const external = panel.querySelector("[data-preview-external]");
  const close = panel.querySelector("[data-preview-close]");
  const links = document.querySelectorAll("[data-source-page-view]");
  let active = null;
  let pinned = false;
  let opening;
  let closing;
  panel.hidden = false;

  function hide(restoreFocus = false) {
    clearTimeout(opening);
    clearTimeout(closing);
    if (!active) return;

    const previous = active;
    active = null;
    pinned = false;
    previous.setAttribute("aria-expanded", "false");
    panel.hidePopover();
    frame.removeAttribute("src");
    if (restoreFocus) previous.focus({ preventScroll: true });
  }

  function show(link, pin) {
    clearTimeout(opening);
    clearTimeout(closing);
    if (active !== link) {
      active?.setAttribute("aria-expanded", "false");
      active = link;
      external.href = link.href;
      urlLabel.textContent = link.href;
      frame.src = link.href;
    }
    pinned = pin;
    link.setAttribute("aria-expanded", "true");
    if (!panel.matches(":popover-open")) panel.showPopover();
    positionPreview(panel, link);
    if (pin) close.focus({ preventScroll: true });
  }

  function closeAfterLeave() {
    clearTimeout(closing);
    closing = setTimeout(() => {
      if (!pinned && active && !active.matches(":hover") && !panel.matches(":hover") && !panel.contains(document.activeElement)) {
        hide();
      }
    }, leaveDelay);
  }

  for (const link of links) {
    const previewOnClick = link.dataset.sourcePageView === "preview";
    if (previewOnClick) link.setAttribute("aria-haspopup", "dialog");
    link.setAttribute("aria-controls", panel.id);
    link.setAttribute("aria-expanded", "false");
    link.addEventListener("pointerenter", (event) => {
      if (event.pointerType !== "mouse" || window.innerWidth < minimumHoverWidth || pinned) return;
      clearTimeout(opening);
      clearTimeout(closing);
      opening = setTimeout(() => show(link, false), hoverDelay);
    });
    link.addEventListener("pointerleave", () => {
      clearTimeout(opening);
      closeAfterLeave();
    });
    link.addEventListener("click", (event) => {
      if (!previewOnClick || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      show(link, true);
    });
  }

  panel.addEventListener("pointerenter", () => clearTimeout(closing));
  panel.addEventListener("pointerleave", closeAfterLeave);
  close.addEventListener("click", () => hide(true));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && active) {
      event.preventDefault();
      hide(pinned || panel.contains(document.activeElement));
    }
  });
  document.addEventListener("pointerdown", (event) => {
    if (!panel.contains(event.target) && !event.target.closest("[data-source-page-view]")) hide();
  });
  document.addEventListener("focusin", (event) => {
    if (pinned && active !== event.target && !panel.contains(event.target)) hide();
  });
  window.addEventListener("resize", () => { if (active) positionPreview(panel, active); });
  window.addEventListener("scroll", () => {
    if (pinned && active) positionPreview(panel, active);
    else hide();
  }, { capture: true, passive: true });
}

document.addEventListener("DOMContentLoaded", initializePreview);
