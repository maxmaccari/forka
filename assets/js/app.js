// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { Hooks as BackpexHooks, backpexParams } from 'backpex';
import { initThemeToggle } from "./theme"
import GameKeyboard from "./hooks/game_keyboard"
import RopeFeedback from "./hooks/rope_feedback"

initThemeToggle()

const Hooks = {
  GameKeyboard,
  RopeFeedback
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: backpexParams({_csrf_token: csrfToken}),
  hooks: {...Hooks, ...BackpexHooks}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "hsl(16 94% 61%)"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
