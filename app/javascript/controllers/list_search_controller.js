import { Controller } from "@hotwired/stimulus"

// Client-side filter over a list of items already in the DOM (no server
// round-trip) - matches the search box's value anywhere in each item's name.
export default class extends Controller {
  static targets = ["search", "item"]

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    this.itemTargets.forEach((item) => {
      item.hidden = query !== "" && !item.dataset.name.toLowerCase().includes(query)
    })
  }
}
