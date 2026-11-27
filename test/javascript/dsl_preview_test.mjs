import assert from "node:assert/strict";
import test from "node:test";
import { setupDslPreview } from "../../app/javascript/dsl_preview.js";

function setupEditor(value, previewOnLoad = false) {
  function element(tag) {
    const handlers = new Map();
    return {
      tag,
      hidden: true,
      ownerDocument: document,
      children: [],
      get textContent() {
        return this.children.map(child => typeof child === "string" ? child : child.textContent).join("");
      },
      set textContent(text) { this.children = [text]; },
      append(...children) { this.children.push(...children); },
      replaceChildren(fragment) { this.children = [...fragment.children]; },
      addEventListener(type, handler) { handlers.set(type, handler); },
      emit(type) { handlers.get(type)(); },
      focus() { this.focused = true; }
    };
  }
  const document = {
    createElement: element,
    createDocumentFragment: () => element("fragment")
  };
  const editor = Object.assign(element("textarea"), { value });
  const panel = element("section");
  const output = element("pre");
  const refresh = element("button");
  const hide = element("button");
  const status = element("span");
  const actions = element("div");
  const elements = {
    ".source-algorithm-editor": editor,
    "#source_dsl_preview": panel,
    "[data-dsl-preview-output]": output,
    "[data-dsl-preview-refresh]": refresh,
    "[data-dsl-preview-hide]": hide,
    "[data-dsl-preview-status]": status,
    "[data-dsl-preview-actions]": actions
  };
  setupDslPreview({
    dataset: { dslPreviewKinds: JSON.stringify({ xpath: "extraction", api: "navigation" }), dslPreviewOnLoad: String(previewOnLoad) },
    querySelector: selector => elements[selector]
  });
  return { editor, panel, output, refresh, hide, status, actions };
}

test("colorizing a draft keeps every character and uses the shared instruction styles", () => {
  const draft = 'xpath=//h1;\nruby=\n  "<script>Événement</script>";\nruby=$array;\n$$META_TITLE$$;api="/data";';
  const { editor, panel, output, refresh, actions } = setupEditor(draft);

  assert.equal(actions.hidden, false);
  assert.equal(panel.hidden, true);
  refresh.emit("click");

  assert.equal(panel.hidden, false);
  assert.equal(editor.value, draft);
  assert.equal(output.textContent, draft);
  assert.deepEqual(
    output.children.filter(child => child.tag === "span").map(child => child.className.split("--")[1]),
    ["extraction", "ruby-a", "ruby-b", "library", "navigation"]
  );
});

test("editing keeps the preview open and refresh uses the current draft", () => {
  const { editor, panel, output, refresh, hide, status } = setupEditor("xpath=//h1", true);
  assert.equal(panel.hidden, false);
  assert.equal(refresh.textContent, "Refresh preview");
  assert.equal(output.textContent, "xpath=//h1");
  editor.value += ";\n$$META_TITLE$$";
  editor.emit("input");

  assert.equal(panel.hidden, false);
  assert.equal(output.textContent, "xpath=//h1");
  assert.equal(status.textContent, "Preview out of date");

  refresh.emit("click");
  assert.equal(output.textContent, editor.value);
  assert.equal(status.textContent, "Preview updated");
  hide.emit("click");
  assert.equal(panel.hidden, true);
  assert.equal(refresh.focused, true);
  assert.equal(editor.value, "xpath=//h1;\n$$META_TITLE$$");
});
