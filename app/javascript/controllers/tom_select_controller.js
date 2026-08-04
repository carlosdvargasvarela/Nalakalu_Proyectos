import { Controller } from "@hotwired/stimulus"

// Enhances a <select> with TomSelect. TomSelect itself loads via the CDN
// <script> tag in the layout (a classic script, so it's ready as a global
// before this module runs) - this controller just wires it to its element.
export default class extends Controller {
  connect() {
    if (!this.element.tomselect) new TomSelect(this.element, { create: false, allowEmptyOption: true })
  }
}
