document.addEventListener("DOMContentLoaded", () => {
  const header = document.querySelector("[data-condenser-header]");
  if (!header) return;

  document.addEventListener("click", (event) => {
    const openMenu = header.querySelector("[data-header-menu][open]");
    if (openMenu && !openMenu.contains(event.target)) openMenu.open = false;
  });

  header.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;

    const openMenu = header.querySelector("[data-header-menu][open]");
    if (!openMenu) return;

    openMenu.open = false;
    openMenu.querySelector("summary").focus();
    event.preventDefault();
  });
});
