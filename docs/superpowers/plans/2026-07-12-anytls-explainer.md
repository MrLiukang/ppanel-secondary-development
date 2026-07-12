# AnyTLS Explainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a self-contained interactive HTML page that explains AnyTLS to beginners, operators, and developers.

**Architecture:** One standalone HTML file with inline CSS and JavaScript. The page uses three tabs, semantic cards, a layer diagram, packet timeline, comparison table, and project-specific configuration mapping. No external assets or libraries are required.

**Tech Stack:** HTML5, CSS3, vanilla JavaScript.

---

### Task 1: Create the standalone explanation page

**Files:**
- Create: `docs/superpowers/mockups/anytls-explainer.html`

- [ ] **Step 1: Add the document shell and content model**

Create a UTF-8 HTML document with the title “AnyTLS：包到底有什么不同？”. Add three navigation buttons with `data-tab` values `overview`, `capture`, and `config`; matching `<section>` elements with those IDs; and a visible top-level conclusion stating that AnyTLS still runs over TCP/TLS in this project.

- [ ] **Step 2: Add the beginner layer diagram**

Add five clickable layer cards in this order: application data, AnyTLS session layer, TLS encryption, TCP, IP. Each card must have `data-layer`, a short visible description, and a hidden detail element. JavaScript will toggle the selected layer and detail text without navigation.

- [ ] **Step 3: Add packet comparison and timeline sections**

Add a comparison table for ordinary TLS, TLS carrying HTTP/2, and AnyTLS. Use the columns “线上可见”, “通常不可见”, and “可能暴露的形状”. Add a clickable timeline containing TCP SYN/SYN-ACK, TLS ClientHello/ServerHello, encrypted records, and padding/segmentation. The copy must distinguish metadata from plaintext content and mark inference as inference.

- [ ] **Step 4: Add the project configuration mapping**

Add code blocks showing `protocol: anytls`, `network: tcp`, and a `paddingScheme` example. Add a mapping card pointing to `node/core/inbound/anytls.go`, explaining that `buildAnyTLS` sets `inbound.Protocol = "anytls"`, selects TCP, and passes padding lines into `AnyTLSServerConfig`.

- [ ] **Step 5: Add inline styles and responsive behavior**

Use CSS variables, a dark navy background, cyan/green encrypted-state accents, and orange metadata accents. Add grid layouts that collapse to one column below 800px. Keep focus states visible and ensure code/text contrast is readable.

- [ ] **Step 6: Add vanilla JavaScript interactions**

Implement `setActiveTab(tabId)`, layer selection, and packet selection. The script must update `aria-selected`, hide/show sections, and write the selected explanation into a live status region. It must not depend on network requests.

### Task 2: Verify the artifact

**Files:**
- Test: `docs/superpowers/mockups/anytls-explainer.html`

- [ ] **Step 1: Validate required content and syntax markers**

Run:

```powershell
rg -n "AnyTLS|protocol: anytls|network: tcp|paddingScheme|buildAnyTLS|ClientHello|padding|aria-selected|setActiveTab" docs/superpowers/mockups/anytls-explainer.html
```

Expected: every search term appears at least once.

- [ ] **Step 2: Check for external dependencies and malformed tags**

Run:

```powershell
rg -n "<script[^>]+src=|<link[^>]+href=|TODO|TBD|待定" docs/superpowers/mockups/anytls-explainer.html
```

Expected: no output.

- [ ] **Step 3: Run whitespace and diff checks**

Run:

```powershell
git diff --check -- docs/superpowers/mockups/anytls-explainer.html docs/superpowers/plans/2026-07-12-anytls-explainer.md
```

Expected: exit code 0 with no whitespace errors.

- [ ] **Step 4: Open the page locally and exercise the interactions**

Open `docs/superpowers/mockups/anytls-explainer.html` in a browser. Confirm the overview/capture/config tabs switch, layer cards reveal different explanations, packet timeline items update the live status, and the layout remains readable at desktop and narrow widths.
