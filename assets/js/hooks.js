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
        this.lastCursorPos = 0
        this.lastMentionMatch = null

        // Disable send button initially (input is empty)
        this.updateSendButton()

        this.el.addEventListener("input", (e) => {
            this.handleInput()
            this.updateSendButton()
        })

        this.el.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                this.submitMessage()
            } else if (e.key === "Backspace") {
                this.handleBackspace(e)
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
            this.updateSendButton()
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
            if (query.length >= 2) {
                // Save cursor position and match for later pill insertion
                this.lastCursorPos = cursorPos
                this.lastMentionMatch = mentionMatch
                this.pushEventTo(this.el, "mention_search", { query: query })
            }
        } else {
            this.pushEventTo(this.el, "close_mention_dropdown", {})
        }

        this.updateHiddenInput()
    },

    handleBackspace(e) {
        const sel = window.getSelection()
        if (!sel.rangeCount) return

        const range = sel.getRangeAt(0)
        
        // Only handle backspace if cursor is collapsed (no selection)
        if (!range.collapsed) return

        // Check if there's a pill immediately before the cursor
        let nodeBefore = null
        
        if (range.startOffset === 0 && range.startContainer.previousSibling) {
            // At the start of a text node, check previous sibling
            nodeBefore = range.startContainer.previousSibling
        } else if (range.startContainer.nodeType === Node.ELEMENT_NODE) {
            // Inside an element, check child before cursor
            nodeBefore = range.startContainer.childNodes[range.startOffset - 1]
        } else if (range.startOffset > 0) {
            // Inside text node, not deleting a pill
            return
        }

        // Check if the node before is a mention pill
        if (nodeBefore && nodeBefore.nodeType === Node.ELEMENT_NODE && 
            nodeBefore.getAttribute && nodeBefore.getAttribute("data-mention") === "true") {
            e.preventDefault()
            
            const firstname = nodeBefore.textContent.replace('@', '')
            const provider = nodeBefore.getAttribute("data-provider")
            
            // Remove the pill
            nodeBefore.remove()
            
            // Notify server to remove from mentioned_contacts
            this.pushEventTo(this.el, "remove_mention", { 
                firstname: firstname,
                provider: provider 
            })
            
            this.updateHiddenInput()
            this.updateSendButton()
        }
    },

    insertMentionPill(firstname, provider) {
        if (!this.lastMentionMatch) {
            // No saved mention context, can't insert pill
            this.el.focus()
            return
        }

        const mentionMatch = this.lastMentionMatch
        const mentionLength = mentionMatch[0].length
        const mentionStartPos = this.lastCursorPos - mentionLength

        // Create pill span
        const pill = document.createElement("span")
        pill.contentEditable = "false"
        pill.className = "inline-flex items-center gap-0.5 px-1.5 py-0.5 mx-0.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium"
        pill.setAttribute("data-mention", "true")
        pill.setAttribute("data-provider", provider)
        pill.textContent = `@${firstname}`

        // Find the text node containing the @mention
        let currentPos = 0
        let targetNode = null
        let nodeStartPos = 0

        const walker = document.createTreeWalker(
            this.el,
            NodeFilter.SHOW_TEXT,
            null,
            false
        )

        while (walker.nextNode()) {
            const node = walker.currentNode
            const nodeLength = node.textContent.length

            if (currentPos + nodeLength > mentionStartPos) {
                targetNode = node
                nodeStartPos = currentPos
                break
            }
            currentPos += nodeLength
        }

        if (targetNode && targetNode.nodeType === Node.TEXT_NODE) {
            const localStartPos = mentionStartPos - nodeStartPos
            const localEndPos = localStartPos + mentionLength

            const before = targetNode.textContent.substring(0, localStartPos)
            const after = targetNode.textContent.substring(localEndPos)

            const beforeNode = document.createTextNode(before)
            const afterNode = document.createTextNode(after || "\u00A0")

            const parent = targetNode.parentNode
            parent.insertBefore(beforeNode, targetNode)
            parent.insertBefore(pill, targetNode)
            parent.insertBefore(afterNode, targetNode)
            parent.removeChild(targetNode)

            // Place cursor after pill
            const range = document.createRange()
            const sel = window.getSelection()
            range.setStart(afterNode, Math.min(1, afterNode.textContent.length))
            range.collapse(true)
            sel.removeAllRanges()
            sel.addRange(range)
        }

        // Clear saved state
        this.lastMentionMatch = null
        this.lastCursorPos = 0

        this.el.focus()
        this.updateHiddenInput()
        this.updateSendButton()
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

    updateSendButton() {
        const btn = document.getElementById("chat-send-btn")
        if (btn) {
            const isEmpty = this.getPlainText() === ""
            btn.disabled = isEmpty
            this.updatePlaceholderState(isEmpty)
        }
    },

    updatePlaceholderState(isEmpty) {
        this.el.dataset.empty = isEmpty ? "true" : "false"
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