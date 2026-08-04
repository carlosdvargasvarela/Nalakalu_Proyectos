import { Controller } from "@hotwired/stimulus"

// Lets an admin map compatible fields between a ProjectTypeAssociation's two
// project types, so a shared value pre-fills when creating an associated project.
export default class extends Controller {
  static targets = ["fromType", "toType", "rows"]
  static values = { fieldsByType: Object, initialMappings: Array }

  connect() {
    this.initialMappingsValue.forEach((mapping) => this.addRow(mapping.from, mapping.to))
  }

  addBlankRow() {
    this.addRow(null, null)
  }

  resetRows() {
    this.rowsTarget.innerHTML = ""
  }

  fieldsCompatibleWith(field, candidates) {
    if (!field) return candidates
    return candidates.filter((c) => {
      if (c.data_type !== field.data_type) return false
      if (field.data_type === "reference" && c.reference_table !== field.reference_table) return false
      return true
    })
  }

  buildSelect(fields, selectedKey, onChange) {
    const select = document.createElement("select")
    select.className = "form-select form-select-sm"

    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = "Elegí un campo"
    select.appendChild(blank)

    fields.forEach((f) => {
      const option = document.createElement("option")
      option.value = f.key
      option.textContent = `${f.label} (${f.key})`
      if (f.key === selectedKey) option.selected = true
      select.appendChild(option)
    })

    select.addEventListener("change", onChange)
    return select
  }

  addRow(fromKey, toKey) {
    const fromFields = this.fieldsByTypeValue[this.fromTypeTarget.value] || []
    const toFields = this.fieldsByTypeValue[this.toTypeTarget.value] || []

    const row = document.createElement("div")
    row.className = "d-flex align-items-center gap-2 mb-2 shared-field-mapping-row"

    const fromInput = document.createElement("input")
    fromInput.type = "hidden"
    fromInput.name = "project_type_association[shared_field_mappings][][from]"
    fromInput.value = fromKey || ""

    const toInput = document.createElement("input")
    toInput.type = "hidden"
    toInput.name = "project_type_association[shared_field_mappings][][to]"
    toInput.value = toKey || ""

    const toWrapper = document.createElement("div")

    const refreshToOptions = () => {
      const field = fromFields.find((f) => f.key === fromInput.value)
      const compatible = this.fieldsCompatibleWith(field, toFields)
      const currentToValue = compatible.some((f) => f.key === toInput.value) ? toInput.value : ""
      toInput.value = currentToValue
      toWrapper.innerHTML = ""
      toWrapper.appendChild(this.buildSelect(compatible, currentToValue, function () {
        toInput.value = this.value
      }))
    }

    const fromSelectEl = this.buildSelect(fromFields, fromKey, function () {
      fromInput.value = this.value
      refreshToOptions()
    })

    const fromWrapper = document.createElement("div")
    fromWrapper.appendChild(fromSelectEl)

    const arrow = document.createElement("span")
    arrow.textContent = "→"

    refreshToOptions()

    const removeButton = document.createElement("button")
    removeButton.type = "button"
    removeButton.className = "btn btn-outline-danger btn-sm"
    removeButton.textContent = "Quitar"
    removeButton.addEventListener("click", () => row.remove())

    row.appendChild(fromWrapper)
    row.appendChild(arrow)
    row.appendChild(toWrapper)
    row.appendChild(fromInput)
    row.appendChild(toInput)
    row.appendChild(removeButton)
    this.rowsTarget.appendChild(row)
  }
}
