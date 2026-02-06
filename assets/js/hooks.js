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

// --- Chat Sidebar Hooks ---

Hooks.ChatPortal = {
    mounted() {
        const target = document.getElementById("chat-sidebar-slot")
        if (target) {
            target.innerHTML = ""
            target.appendChild(this.el)
        }
    }
}

Hooks.ChatScroll = {
    mounted() {
        this.scrollToBottom()
        this.observer = new MutationObserver(() => {
            this.scrollToBottom()
        })
        this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
        this.scrollToBottom()
    },
    destroyed() {
        if (this.observer) {
            this.observer.disconnect()
        }
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

Hooks.MentionInput = {
    mounted() {
        this.el.addEventListener("input", (e) => {
            this.handleInput()
        })

        this.el.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                this.submitMessage()
            }
        })

        // Listen for mention pill insertion from the server
        this.handleEvent("insert_mention_pill", ({ firstname, provider }) => {
            this.insertMentionPill(firstname, provider)
        })

        // Listen for input clear after sending
        this.handleEvent("clear_chat_input", () => {
            this.el.innerHTML = ""
            this.updateHiddenInput()
        })
    },

    handleInput() {
        const text = this.el.innerText
        const cursorPos = this.getCursorPosition()
        const beforeCursor = text.substring(0, cursorPos)

        // Check for @mention pattern: @ followed by at least 1 non-space char
        const mentionMatch = beforeCursor.match(/@(\S+)$/)

        if (mentionMatch) {
            const query = mentionMatch[1]
            if (query.length >= 1) {
                this.pushEventTo(this.el, "mention_search", { query: query })
            }
        } else {
            this.pushEventTo(this.el, "close_mention_dropdown", {})
        }

        this.updateHiddenInput()
    },

    insertMentionPill(firstname, provider) {
        // Remove the @query text
        const text = this.el.innerText
        const cursorPos = this.getCursorPosition()
        const beforeCursor = text.substring(0, cursorPos)
        const mentionMatch = beforeCursor.match(/@(\S+)$/)

        if (mentionMatch) {
            // Find and remove the @query text node
            const range = window.getSelection().getRangeAt(0)
            const startOffset = range.startOffset - mentionMatch[0].length

            // Create pill span
            const pill = document.createElement("span")
            pill.contentEditable = "false"
            pill.className = "inline-flex items-center gap-0.5 px-1.5 py-0.5 mx-0.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium"
            pill.setAttribute("data-mention", "true")
            pill.setAttribute("data-provider", provider)
            pill.textContent = `@${firstname}`

            // Replace @query with pill
            const sel = window.getSelection()
            const node = sel.focusNode

            if (node.nodeType === Node.TEXT_NODE) {
                const before = node.textContent.substring(0, startOffset)
                const after = node.textContent.substring(cursorPos)

                const beforeNode = document.createTextNode(before)
                const afterNode = document.createTextNode(after || "\u00A0")

                const parent = node.parentNode
                parent.insertBefore(beforeNode, node)
                parent.insertBefore(pill, node)
                parent.insertBefore(afterNode, node)
                parent.removeChild(node)

                // Place cursor after pill
                const newRange = document.createRange()
                newRange.setStart(afterNode, afterNode.textContent.length > 0 ? 1 : 0)
                newRange.collapse(true)
                sel.removeAllRanges()
                sel.addRange(newRange)
            }
        }

        this.el.focus()
        this.updateHiddenInput()
    },

    submitMessage() {
        const text = this.getPlainText()
        if (text.trim() === "") return

        const hiddenInput = document.getElementById("chat-message-hidden")
        if (hiddenInput) {
            hiddenInput.value = text
        }

        // Submit the form
        const form = this.el.closest("form")
        if (form) {
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        }
    },

    updateHiddenInput() {
        const hiddenInput = document.getElementById("chat-message-hidden")
        if (hiddenInput) {
            hiddenInput.value = this.getPlainText()
        }
    },

    getPlainText() {
        let text = ""
        this.el.childNodes.forEach(node => {
            if (node.nodeType === Node.TEXT_NODE) {
                text += node.textContent
            } else if (node.getAttribute && node.getAttribute("data-mention") === "true") {
                text += node.textContent
            } else {
                text += node.textContent
            }
        })
        return text.replace(/\u00A0/g, " ").trim()
    },

    getCursorPosition() {
        const sel = window.getSelection()
        if (!sel.rangeCount) return 0

        const range = sel.getRangeAt(0)
        const preRange = range.cloneRange()
        preRange.selectNodeContents(this.el)
        preRange.setEnd(range.startContainer, range.startOffset)
        return preRange.toString().length
    }
}

export default Hooks