// Shared by both Gantt stimulus controllers: sets --bar-fill per bar, plus a
// --bar-label-color computed from that fill's WCAG relative luminance so the
// project/stage name stays legible regardless of the bar's own color or the
// active theme (frappe-gantt's default label color only follows the theme,
// not the custom --bar-fill we set per bar).
function relativeLuminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

function contrastRatio(luminanceA, luminanceB) {
  const [light, dark] = luminanceA > luminanceB ? [luminanceA, luminanceB] : [luminanceB, luminanceA]
  return (light + 0.05) / (dark + 0.05)
}

function labelColorFor(barColor) {
  const barLuminance = relativeLuminance(barColor)
  return contrastRatio(barLuminance, 1) >= contrastRatio(barLuminance, 0) ? "#ffffff" : "#000000"
}

export function applyBarColors(container, colors, classPrefix) {
  colors.forEach(([id, _name, color]) => {
    container.querySelectorAll(`.bar-wrapper.${classPrefix}-${id}`).forEach((el) => {
      el.style.setProperty("--bar-fill", color)
      el.style.setProperty("--bar-label-color", labelColorFor(color))
    })
  })
}
