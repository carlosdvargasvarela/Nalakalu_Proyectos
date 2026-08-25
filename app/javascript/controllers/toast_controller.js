import { Controller } from "@hotwired/stimulus"

// Shows a flash message as a Bootstrap toast; autohide/delay use Bootstrap's defaults (5s).
export default class extends Controller {
  connect() {
    bootstrap.Toast.getOrCreateInstance(this.element).show()
  }
}
