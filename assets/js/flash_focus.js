const FOCUS_RING_BUFFER_PX = 2
const MIN_FOCUS_RING_OUTSET_PX = 4

let initialized = false

function getPaintedBannerBottom(targetRect) {
  const group = document.getElementById("flash-group")
  if (!group) return null

  let bottom = null
  for (const notice of group.querySelectorAll('[role="alert"]')) {
    const style = getComputedStyle(notice)
    if (style.display === "none" || style.visibility === "hidden") continue

    const rect = notice.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) continue
    if (rect.bottom <= 0 || rect.top >= window.innerHeight) continue
    if (rect.right <= targetRect.left || rect.left >= targetRect.right) continue

    bottom = bottom === null ? rect.bottom : Math.max(bottom, rect.bottom)
  }

  return bottom
}

function getFocusRingOutset(target) {
  const style = getComputedStyle(target)
  const outlineWidth = style.outlineStyle === "none" ? 0 : parseFloat(style.outlineWidth) || 0
  const outlineOffset = outlineWidth > 0 ? Math.max(0, parseFloat(style.outlineOffset) || 0) : 0
  return Math.max(MIN_FOCUS_RING_OUTSET_PX, Math.ceil(outlineWidth + outlineOffset))
}

function isFocusVisible(target) {
  try {
    return target.matches(":focus-visible")
  } catch (_) {
    return false
  }
}

function revealFocusedControl(target) {
  if (document.activeElement !== target) return
  if (!target.isConnected || !target.closest("main")) return
  if (target.closest('[aria-modal="true"], dialog[open]')) return
  if (!isFocusVisible(target)) return

  const targetRect = target.getBoundingClientRect()
  if (targetRect.width <= 0 || targetRect.height <= 0) return

  const bannerBottom = getPaintedBannerBottom(targetRect)
  if (bannerBottom === null) return

  const clearance = getFocusRingOutset(target) + FOCUS_RING_BUFFER_PX
  const overlap = bannerBottom + clearance - targetRect.top

  if (overlap > 0 && window.scrollY > 0) {
    window.scrollBy({ top: -Math.ceil(overlap), behavior: "instant" })
  }
}

export function initFlashFocusReveal() {
  if (initialized) return
  initialized = true

  let rafId = null

  document.addEventListener("focusin", (event) => {
    const target = event.target
    if (!(target instanceof Element)) return
    if (!target.closest("main")) return
    if (target.closest('[aria-modal="true"], dialog[open]')) return

    if (rafId !== null) {
      cancelAnimationFrame(rafId)
    }

    rafId = requestAnimationFrame(() => {
      rafId = null
      revealFocusedControl(target)
    })
  })
}
