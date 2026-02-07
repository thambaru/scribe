const ChatPortal = {
    mounted() {
        // Move this element into the sidebar slot
        const target = document.getElementById("chat-sidebar-slot")
        if (target) {
            // Clear existing content and append this portal
            target.innerHTML = ""
            target.appendChild(this.el)
        } else {
            console.warn("chat-sidebar-slot not found for portal")
        }
    },
    updated() {
        // On update, ensure we're still in the right place
        const target = document.getElementById("chat-sidebar-slot")
        if (target && this.el.parentElement !== target) {
            target.appendChild(this.el)
        }
    }
}

export default ChatPortal
