function renderPreview(output, draft, kinds) {
  const document = output.ownerDocument;
  const preview = document.createDocumentFragment();
  let rubyCount = 0;

  // Use the pipeline's semicolon boundaries while keeping the draft text intact.
  for (const segment of draft.split(/(;)/)) {
    const library = segment.match(/^(\s*)(\$\$[A-Z][A-Z0-9_]*\$\$)(\s*)$/);
    const instruction = segment.match(/^(\s*)([a-z_]+)=/);
    if (!library && !instruction) {
      preview.append(segment);
      continue;
    }

    const span = document.createElement("span");
    const prefix = document.createElement("strong");
    prefix.className = "dsl-instruction-prefix";

    if (library) {
      span.className = "dsl-instruction dsl-instruction--library";
      prefix.textContent = library[2];
      span.append(library[1], prefix, library[3]);
    } else {
      const name = instruction[2];
      let kind = Object.hasOwn(kinds, name) ? kinds[name] : "other";
      if (name === "ruby") {
        rubyCount += 1;
        kind = rubyCount % 2 ? "ruby-a" : "ruby-b";
      }
      span.className = `dsl-instruction dsl-instruction--${kind}`;
      prefix.textContent = name + "=";
      span.append(instruction[1], prefix, segment.slice(instruction[0].length));
    }
    preview.append(span);
  }
  output.replaceChildren(preview);
}

export function setupDslPreview(workspace) {
  const editor = workspace.querySelector(".source-algorithm-editor");
  const panel = workspace.querySelector("#source_dsl_preview");
  const output = workspace.querySelector("[data-dsl-preview-output]");
  const refresh = workspace.querySelector("[data-dsl-preview-refresh]");
  const hide = workspace.querySelector("[data-dsl-preview-hide]");
  const status = workspace.querySelector("[data-dsl-preview-status]");
  const kinds = JSON.parse(workspace.dataset.dslPreviewKinds);
  let snapshot;

  function showPreview() {
    snapshot = editor.value;
    renderPreview(output, snapshot, kinds);
    panel.hidden = false;
    hide.hidden = false;
    refresh.textContent = "Refresh preview";
  }

  refresh.addEventListener("click", () => {
    showPreview();
    status.textContent = snapshot.trim() ? "Preview updated" : "No DSL to preview";
  });

  editor.addEventListener("input", () => {
    if (panel.hidden) return;
    const message = editor.value === snapshot ? "" : "Preview out of date";
    if (status.textContent !== message) status.textContent = message;
  });

  hide.addEventListener("click", () => {
    panel.hidden = true;
    hide.hidden = true;
    refresh.textContent = "Colorize preview";
    status.textContent = "";
    refresh.focus();
  });

  if (workspace.dataset.dslPreviewOnLoad === "true") showPreview();
  workspace.querySelector("[data-dsl-preview-actions]").hidden = false;
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-dsl-preview]").forEach(setupDslPreview);
  });
}
