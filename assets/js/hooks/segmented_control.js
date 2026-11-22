const SegmentedControl = {
  mounted() {
    this._onKeyDown = (e) => {
      const radios = Array.from(this.el.querySelectorAll('[role="radio"]:not(:disabled)'))
      if (radios.length === 0) return

      const currentIndex = radios.indexOf(document.activeElement)
      if (currentIndex === -1) return

      let nextIndex = null
      if (e.key === "ArrowRight" || e.key === "ArrowDown") {
        nextIndex = (currentIndex + 1) % radios.length
      } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
        nextIndex = (currentIndex - 1 + radios.length) % radios.length
      } else if (e.key === "Home") {
        nextIndex = 0
      } else if (e.key === "End") {
        nextIndex = radios.length - 1
      } else {
        return
      }

      const target = radios[nextIndex]
      if (!target.hasAttribute("phx-click")) return

      e.preventDefault()
      radios.forEach((radio, i) => {
        radio.setAttribute("tabindex", i === nextIndex ? "0" : "-1")
      })
      target.focus()
      target.click()
    }

    this.el.addEventListener("keydown", this._onKeyDown)
  },

  destroyed() {
    if (this._onKeyDown) {
      this.el.removeEventListener("keydown", this._onKeyDown)
    }
  }
}

export default SegmentedControl
