import ChatPortal from "./hooks/chat_portal"
import ChatScroll from "./hooks/chat_scroll"
import ChatSidebar from "./hooks/chat_sidebar"
import MentionInput from "./hooks/mention_input"

let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.ChatPortal = ChatPortal
Hooks.ChatScroll = ChatScroll
Hooks.ChatSidebar = ChatSidebar
Hooks.MentionInput = MentionInput

export default Hooks
