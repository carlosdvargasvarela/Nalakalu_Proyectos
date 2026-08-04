import { Controller } from "@hotwired/stimulus"

// Repopulates a TomSelect-enhanced "select" target with the options relevant
// to whatever's chosen in a "control" select, driven by a server-provided
// { key: [[value, text], ...] } map. If the control's selected <option> has a
// data-key attribute, that's used as the lookup key; otherwise the control's
// own value is used directly.
export default class extends Controller {
  static targets = ["control", "select"]
  static values = { options: Object }

  connect() {
    if (!this.selectTarget.tomselect) new TomSelect(this.selectTarget, { create: false, allowEmptyOption: true })
    this.apply()
  }

  apply() {
    const selectedOption = this.controlTarget.selectedOptions[0]
    const key = (selectedOption && selectedOption.dataset.key) || this.controlTarget.value
    const ts = this.selectTarget.tomselect
    ts.clear(true)
    ts.clearOptions()
    ;(this.optionsValue[key] || []).forEach(([value, text]) => ts.addOption({ value: String(value), text }))
    ts.refreshOptions(false)
  }
}
