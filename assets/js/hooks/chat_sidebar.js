const ChatSidebar = {
    mounted() {
        // Enable CSS transition only after the initial render frame,
        // so the sidebar doesn't animate on first page load or navigation.
        requestAnimationFrame(() => {
            this.el.classList.add("transition-transform", "duration-300", "ease-in-out")
        })
    }
}

export default ChatSidebar
