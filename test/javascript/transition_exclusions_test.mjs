import assert from "node:assert/strict";
import test from "node:test";
import { configureExclusionSelection } from "../../app/javascript/transition_exclusions.js";

class Checkbox extends EventTarget {
  checked = false;

  change(checked) {
    this.checked = checked;
    this.dispatchEvent(new Event("change"));
  }
}

test("select all toggles the candidates and reflects individual selections", () => {
  const master = new Checkbox();
  const candidates = Array.from({ length: 3 }, () => new Checkbox());
  configureExclusionSelection({
    querySelector: (selector) => selector === "[data-exclusion-select-all]" ? master : null,
    querySelectorAll: (selector) => selector === 'input[name="urls[]"]' ? candidates : [],
  });

  assert.equal(master.disabled, false);
  assert.ok(candidates.every((candidate) => !candidate.checked));
  master.change(true);
  assert.ok(candidates.every((candidate) => candidate.checked));
  assert.equal(master.indeterminate, false);

  candidates[0].change(false);
  assert.equal(master.checked, false);
  assert.equal(master.indeterminate, true);
  candidates[0].change(true);
  assert.equal(master.checked, true);
  assert.equal(master.indeterminate, false);

  master.change(false);
  assert.ok(candidates.every((candidate) => !candidate.checked));
  assert.equal(master.indeterminate, false);
});
