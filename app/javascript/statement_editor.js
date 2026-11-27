const jsonToken = /"(?:[^"\\]|\\.)*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:e[+-]?\d+)?|true|false|null|[{}\[\]:,]/gi;

function isStructuredJson(text) {
  if (!/^[\s]*[\[{]/.test(text)) return false;
  try {
    JSON.parse(text);
    return true;
  } catch {
    return false;
  }
}

function layoutJson(text, append) {
  // Format whitespace around existing tokens, preserving exact strings, numbers and keys.
  const tokens = text.match(jsonToken);
  let depth = 0;
  const newline = () => append("\n" + "  ".repeat(depth));

  tokens.forEach((token, index) => {
    const previous = tokens[index - 1];
    const next = tokens[index + 1];
    if (token === "}" || token === "]") {
      depth -= 1;
      if (previous !== "{" && previous !== "[") newline();
    }
    if (token[0] === '"') {
      append(token, next === ":" ? "key" : "string");
    } else if (/^[-\d]/.test(token)) {
      append(token, "number");
    } else if (/^(true|false|null)$/.test(token)) {
      append(token, "literal");
    } else {
      append(token);
    }
    if (token === "{" || token === "[") {
      depth += 1;
      if (next !== "}" && next !== "]") newline();
    } else if (token === ",") {
      newline();
    } else if (token === ":") {
      append(" ");
    }
  });
}

function initializeStatementEditor(form) {
  const field = form.querySelector("#statement_cache");
  const preview = form.querySelector("#statement_cache_preview");
  const tools = form.querySelector("[data-cache-tools]");
  const format = form.querySelector("[data-format-json]");
  const previewButton = form.querySelector("[data-preview-json]");
  const tag = form.querySelector("[data-cache-format]");

  function updateTools() {
    const structured = isStructuredJson(field.value);
    format.disabled = !structured;
    previewButton.disabled = !structured;
    const label = structured ? "JSON" : (field.value.trim() ? "Plain text" : "Empty");
    if (tag.textContent !== label) tag.textContent = label;
  }

  function setPreview(enabled) {
    if (enabled) {
      const contents = document.createDocumentFragment();
      layoutJson(field.value, (token, type) => {
        if (type) {
          const span = document.createElement("span");
          span.className = "json-" + type;
          span.textContent = token;
          contents.append(span);
        } else {
          contents.append(token);
        }
      });
      preview.replaceChildren(contents);
    }

    field.hidden = enabled;
    preview.hidden = !enabled;
    previewButton.setAttribute("aria-pressed", String(enabled));
  }

  field.addEventListener("input", updateTools);
  previewButton.addEventListener("click", () => setPreview(preview.hidden));
  format.addEventListener("click", () => {
    let formatted = "";
    layoutJson(field.value, token => { formatted += token; });
    setPreview(false);
    if (field.value !== formatted) {
      field.setRangeText(formatted, 0, field.value.length, "start");
      field.dispatchEvent(new Event("input", { bubbles: true }));
    }
    field.focus();
  });

  updateTools();
  tools.hidden = false;
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-statement-editor]").forEach(initializeStatementEditor);
});
