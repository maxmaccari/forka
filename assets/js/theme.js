const STORAGE_KEY = "forka:theme"
const MODES = ["system", "light", "dark"]
const LABELS = {
  system: "Tema: sistema. Trocar tema",
  light: "Tema: claro. Trocar tema",
  dark: "Tema: escuro. Trocar tema"
}

function getStoredMode() {
  try {
    const val = localStorage.getItem(STORAGE_KEY)
    return MODES.includes(val) ? val : "system"
  } catch (_) {
    return "system"
  }
}

function applyMode(mode) {
  if (mode === "light" || mode === "dark") {
    document.documentElement.setAttribute("data-theme", mode)
  } else {
    document.documentElement.removeAttribute("data-theme")
  }
  syncToggleButtons(mode)
}

function syncToggleButtons(mode) {
  const buttons = document.querySelectorAll("[data-theme-toggle]")
  buttons.forEach((btn) => {
    btn.setAttribute("aria-label", LABELS[mode] || LABELS.system)
    btn.querySelectorAll("[data-theme-icon]").forEach((icon) => {
      icon.classList.toggle("hidden", icon.dataset.themeIcon !== mode)
    })
  })
}

function isBackpexPage() {
  return Boolean(document.getElementById("backpex-app-shell"))
}

export function initThemeToggle() {
  if (isBackpexPage()) return

  applyMode(getStoredMode())

  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-theme-toggle]")
    if (!btn || isBackpexPage()) return

    const current = getStoredMode()
    const next = MODES[(MODES.indexOf(current) + 1) % MODES.length]
    try {
      if (next === "system") {
        localStorage.removeItem(STORAGE_KEY)
      } else {
        localStorage.setItem(STORAGE_KEY, next)
      }
    } catch (_) {}
    applyMode(next)
  })

  window.addEventListener("phx:page-loading-stop", () => {
    if (!isBackpexPage()) {
      syncToggleButtons(getStoredMode())
    }
  })

  window.addEventListener("storage", (e) => {
    if (e.key === STORAGE_KEY && !isBackpexPage()) {
      applyMode(getStoredMode())
    }
  })
}
