const MentionInput = {
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
        // Skip if a pill was just removed — the input event fires from DOM changes
        // but there's nothing meaningful to process
        if (this._pillJustRemoved) {
            this._pillJustRemoved = false
            this.updateHiddenInput()
            return
        }

        const cursorPos = this.getCursorPosition()

        // Build text from only real text nodes (not pill contents) to avoid
        // pill text like "@Firstname" being matched as a mention pattern
        let textBeforeCursor = ""
        let pos = 0
        const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null, false)
        while (walker.nextNode()) {
            const node = walker.currentNode
            // Skip text nodes inside pills
            if (node.parentElement && node.parentElement.closest && node.parentElement.closest("[data-mention]")) {
                continue
            }
            const nodeLen = node.textContent.length
            if (pos + nodeLen <= cursorPos) {
                textBeforeCursor += node.textContent
            } else {
                textBeforeCursor += node.textContent.substring(0, cursorPos - pos)
            }
            pos += nodeLen
            if (pos >= cursorPos) break
        }

        // Check for @mention pattern: @ followed by at least 1 non-space char
        const mentionMatch = textBeforeCursor.match(/@(\S+)$/)

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

        // Resolve the pill (if any) immediately before the cursor, plus
        // any spacer text node sitting between the cursor and the pill.
        const { pill, spacer } = this.findPillBeforeCursor(range)

        if (!pill) return // No pill — let the browser handle normal backspace

        e.preventDefault()

        const firstname = pill.getAttribute("data-firstname") || pill.textContent.replace("@", "")
        const provider = pill.getAttribute("data-provider")

        // Determine a stable insertion point for the cursor anchor.
        // We grab references BEFORE removing anything so the DOM is still intact.
        const prevSibling = pill.previousSibling

        // Remove the spacer first (if it's a separate node from pill's previousSibling)
        if (spacer && spacer !== prevSibling) {
            spacer.remove()
        }

        // Remove the pill itself
        pill.remove()

        // Flag to prevent handleInput from processing the DOM mutation
        this._pillJustRemoved = true

        // Place a cursor anchor. We deliberately avoid a global cleanup —
        // only the nodes associated with this pill were removed.
        const cursorAnchor = document.createTextNode("\u200B")

        if (prevSibling && this.el.contains(prevSibling)) {
            // If the previous sibling is a text node, merge the anchor into it
            // to avoid accumulating orphan zero-width-space nodes.
            if (prevSibling.nodeType === Node.TEXT_NODE) {
                // Append the ZWS to the existing text node and place cursor at end
                prevSibling.after(cursorAnchor)
            } else {
                prevSibling.after(cursorAnchor)
            }
        } else if (this.el.firstChild) {
            this.el.insertBefore(cursorAnchor, this.el.firstChild)
        } else {
            this.el.appendChild(cursorAnchor)
        }

        // Set caret into the anchor node
        const newRange = document.createRange()
        newRange.setStart(cursorAnchor, 1)
        newRange.collapse(true)
        sel.removeAllRanges()
        sel.addRange(newRange)

        // Remove stray <br>s that contenteditable may leave behind,
        // but do NOT remove spacer text nodes belonging to other pills.
        this.removeStrayBRs()

        // Notify server
        this.pushEventTo(this.el, "remove_mention", {
            firstname: firstname,
            provider: provider
        })
        this.pushEventTo(this.el, "close_mention_dropdown", {})

        this.updateHiddenInput()
        this.updateSendButton()
    },

    // Walk backwards from the cursor to find a mention pill.
    // Returns { pill, spacer } where spacer is a whitespace-only text node
    // sitting between the cursor position and the pill (may be null).
    findPillBeforeCursor(range) {
        const container = range.startContainer
        const offset = range.startOffset

        // Case 1: Cursor is inside a text node
        if (container.nodeType === Node.TEXT_NODE) {
            const textBefore = container.textContent.substring(0, offset)

            // If there's real (non-whitespace) text before the cursor,
            // the user is typing in normal text — not adjacent to a pill.
            if (textBefore.replace(/[\u00A0\u200B]/g, "").length > 0) {
                return { pill: null, spacer: null }
            }

            // The text before cursor is empty or only whitespace/ZWS.
            // Check if the previous sibling (or the node before the spacer) is a pill.
            let candidate = container.previousSibling
            let spacerNode = (offset > 0 || textBefore.length > 0) ? container : null

            // If offset is 0 and the text node is empty, the spacer is the node itself
            // but only if it will be consumed. If offset > 0 we're inside a spacer.
            if (!candidate) {
                return { pill: null, spacer: null }
            }

            if (this.isPill(candidate)) {
                return { pill: candidate, spacer: spacerNode }
            }

            return { pill: null, spacer: null }
        }

        // Case 2: Cursor is at an element-level offset (e.g. directly inside this.el)
        if (container.nodeType === Node.ELEMENT_NODE) {
            const nodeBefore = container.childNodes[offset - 1]
            if (!nodeBefore) return { pill: null, spacer: null }

            if (this.isPill(nodeBefore)) {
                return { pill: nodeBefore, spacer: null }
            }

            // The node before might be a spacer text node; look one more step back.
            if (nodeBefore.nodeType === Node.TEXT_NODE &&
                nodeBefore.textContent.replace(/[\u00A0\u200B]/g, "").trim() === "") {
                const candidate = container.childNodes[offset - 2]
                if (candidate && this.isPill(candidate)) {
                    return { pill: candidate, spacer: nodeBefore }
                }
            }

            return { pill: null, spacer: null }
        }

        return { pill: null, spacer: null }
    },

    isPill(node) {
        return node &&
            node.nodeType === Node.ELEMENT_NODE &&
            node.getAttribute &&
            node.getAttribute("data-mention") === "true"
    },

    removeStrayBRs() {
        const children = Array.from(this.el.childNodes)
        for (const child of children) {
            if (child.nodeName === "BR") {
                child.remove()
            }
        }
    },

    getCrmIconSvg(provider) {
        if (provider === "hubspot") {
            return `<svg viewBox="0 0 24 24" fill="currentColor" class="text-orange-500 size-2.5" style="width:10px;height:10px;">
                <path d="M17.58 10.1V7.64a2.08 2.08 0 0 0 1.21-1.88v-.06A2.08 2.08 0 0 0 16.71 3.62h-.06A2.08 2.08 0 0 0 14.57 5.7v.06a2.08 2.08 0 0 0 1.21 1.88V10.1a5.33 5.33 0 0 0-2.4 1.18l-6.39-4.97a2.2 2.2 0 0 0 .06-.51 2.24 2.24 0 1 0-2.24 2.24c.35 0 .68-.09.98-.24l6.27 4.88a5.37 5.37 0 0 0 .14 6.06l-1.93 1.93a1.63 1.63 0 0 0-.47-.08 1.66 1.66 0 1 0 1.66 1.66 1.63 1.63 0 0 0-.08-.47l1.9-1.9a5.38 5.38 0 1 0 4.14-9.88zm-.93 7.64a2.54 2.54 0 1 1 0-5.08 2.54 2.54 0 0 1 0 5.08z"/>
            </svg>`
        } else if (provider === "salesforce") {
            return `<svg viewBox="0 0 24 24" fill="currentColor" class="text-[#00A1E0] size-2.5" style="width:10px;height:10px;">
                <path d="M10.05 5.43a4.35 4.35 0 0 1 3.37-1.6 4.39 4.39 0 0 1 4.1 2.87 3.65 3.65 0 0 1 1.47-.31 3.69 3.69 0 0 1 3.69 3.69 3.69 3.69 0 0 1-3.69 3.69h-.15l-.01.14a3.9 3.9 0 0 1-3.87 3.46 3.88 3.88 0 0 1-2.38-.82 4.67 4.67 0 0 1-3.54 1.63 4.68 4.68 0 0 1-4.44-3.19A3.43 3.43 0 0 1 3 11.73a3.43 3.43 0 0 1 2.79-3.37 4.07 4.07 0 0 1-.06-.72A4.14 4.14 0 0 1 9.87 3.5c.07 0 .13.01.18.01v-.01l.01.01-.01 1.92z"/>
            </svg>`
        }
        return ""
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

        const initial = firstname ? firstname.charAt(0).toUpperCase() : "?"

        // Create pill span with avatar + CRM badge
        const pill = document.createElement("span")
        pill.contentEditable = "false"
        pill.className = "inline-flex items-center gap-1 px-1 pr-2 py-0.5 mx-0.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium align-middle"
        pill.setAttribute("data-mention", "true")
        pill.setAttribute("data-provider", provider)
        pill.setAttribute("data-firstname", firstname)

        pill.innerHTML = `<span style="position:relative;display:inline-flex;flex-shrink:0;">
            <span style="width:20px;height:20px;border-radius:9999px;background:#c7d2fe;color:#4338ca;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:600;line-height:1;">${initial}</span>
            <span style="position:absolute;bottom:-2px;right:-2px;width:12px;height:12px;border-radius:9999px;background:white;display:flex;align-items:center;justify-content:center;">${this.getCrmIconSvg(provider)}</span>
        </span>@${firstname}`

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
                const firstname = node.getAttribute("data-firstname")
                text += firstname ? `@${firstname}` : node.textContent
            } else {
                text += node.textContent
            }
        })
        return text.replace(/[\u00A0\u200B]/g, " ").trim()
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

export default MentionInput
