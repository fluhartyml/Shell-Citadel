//
//  TerminalTabsView.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "we may need to add tab abilities to citadel so i can have
//  multiple terminals open."
//
//  THE NEED: "i want to get you and access to my raspberry pi to my ipad." With one
//  ConnectionProfile it was Claude OR the Pi — pointing it at one wiped the other. A tab
//  is an open connection, so the Claude tab can sit in .attach mode against tmux while a
//  Pi tab runs .direct at the same time. That combination was impossible while the mode
//  was global.
//
//  WHY EVERY TAB STAYS IN THE HIERARCHY. SwiftUI destroys @State when a view leaves the
//  view tree, and TerminalView owns the SSHSession as @State. Rendering only the selected
//  tab would therefore CLOSE the connection on every tab switch — the exact opposite of
//  what tabs are for. So all tabs are built and the ones not on screen are merely hidden.
//  Live sessions survive switching, which is the whole point.
//
//  ADAPTIVE LAYOUT — added 2026-08-29 for the iPhone Ultra. Michael: "the iphone ultra will
//  replace my ipad mini" / "the ultra comes out in a few weks." That device has TWO
//  displays, ~5.5" cover and ~7.8" inner, and it changes size WHILE THE APP IS RUNNING.
//
//  So layout is driven by `horizontalSizeClass` and by nothing else:
//    compact (cover screen, any iPhone) → one terminal, full width.
//    regular (inner screen, iPad)       → an optional two-pane split.
//
//  It is deliberately NOT driven by fold detection. `foldState` and `angleDegrees` are
//  PRIVATE framework strings in iOS 27, and private API is an App Store rejection — which
//  this app cannot afford now that it is on the submission track. Size class is what the
//  real device reports anyway, which is why an iPhone 17 sim and an iPad mini sim prove
//  both Ultra states with no new hardware and no resizable simulator (there isn't one in
//  Xcode 27 — checked).
//
//  THE FOLD-SAFETY PROPERTY falls out of the rule above: because every tab is always built,
//  unfolding, folding, rotating or splitting the app NEVER drops a session. The panes only
//  decide what is visible.
//
import SwiftUI

/// A tab is just an identity plus a label. The terminal state lives inside the
/// TerminalView keyed to that identity, and its profile persists under its own key.
struct TerminalTab: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String = "New") {
        self.id = id
        self.name = name
    }

    /// The AppStorage key this tab's ConnectionProfile persists under.
    var profileKey: String { "connectionProfile.\(id.uuidString)" }
}

struct TerminalTabsView: View {
    @AppStorage("terminalTabs") private var storedTabs = Data()
    /// Remembered across launches, but only ever ACTED on at regular width.
    @AppStorage("terminalSplit") private var splitEnabled = false

    @Environment(\.horizontalSizeClass) private var widthClass

    @State private var tabs: [TerminalTab] = []
    @State private var selection: UUID?
    /// The second pane's tab when split is showing. Nil until the user puts one there.
    @State private var companion: UUID?
    /// Which pane a tap on a chip fills. Ignored unless the split is showing.
    @State private var focusedPane: Pane = .primary
    /// Chip labels, keyed by tab. Held as state and only reassigned when a value really
    /// changed, so a defaults write that affects no label triggers no redraw.
    @State private var labels: [UUID: String] = [:]

    private enum Pane { case primary, secondary }

    /// The split is a REGULAR-WIDTH affordance. On the Ultra's cover screen — or any
    /// iPhone — there is no room for two terminals, so the stored preference is simply not
    /// applied. Nothing is turned off and nothing is forgotten; folding the phone shut and
    /// opening it again returns to the same two panes.
    private var showingSplit: Bool {
        widthClass == .regular && splitEnabled && tabs.count > 1 && companion != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always visible: the + lives in this bar, so hiding it until a second tab
            // exists made the second tab impossible to create.
            tabBar

            if showingSplit {
                HStack(spacing: 0) {
                    pane(.primary)
                    Divider()
                    pane(.secondary)
                }
            } else {
                pane(.primary)
            }
        }
        .onAppear(perform: restore)
        .onAppear(perform: refreshLabels)
        // A chip's label lives in the profile the connection sheet writes, and that write
        // happens inside a child view, which does not redraw this one.
        //
        // ⚠️ THE FIRST VERSION OF THIS BUMPED A COUNTER ON EVERY DEFAULTS CHANGE, AND THAT
        // COULD FEED ITSELF. Connecting writes the profile to @AppStorage — a defaults
        // change — so the redraw it triggered could produce another write and another
        // redraw. Michael: "why cant shell citadel connect locally".
        //
        // Now the notification only RECOMPUTES the labels and assigns them when they
        // actually differ. A defaults write that changes no label changes no state, so
        // the loop has nowhere to go.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshLabels()
        }
        .onChange(of: tabs) { _, _ in refreshLabels() }
        .onChange(of: tabs) { _, _ in persist() }
        .onChange(of: tabs) { _, new in
            // A closed tab must not stay wired to a pane.
            if let c = companion, !new.contains(where: { $0.id == c }) { companion = nil }
        }
    }

    /// Every tab is built every time, in both layouts. Only visibility changes — which is
    /// why nothing disconnects when the device folds, rotates, or splits.
    private func pane(_ which: Pane) -> some View {
        let shown = which == .primary ? selection : companion
        let isFocused = showingSplit && which == focusedPane
        return ZStack {
            ForEach(tabs) { tab in
                // The first tab keeps the ORIGINAL storage key so an existing install
                // opens already pointed at his Mac rather than blank.
                TerminalView(profileKey: tab.id == tabs.first?.id ? "connectionProfile"
                                                                 : tab.profileKey)
                    .opacity(tab.id == shown ? 1 : 0)
                    .allowsHitTesting(tab.id == shown)
                    // Keep it laid out but out of the accessibility tree, so VoiceOver
                    // does not read every hidden terminal.
                    .accessibilityHidden(tab.id != shown)
            }
        }
        .overlay(alignment: .top) {
            // Only while split, and only a hairline: which pane a tab tap will fill has to
            // be visible, but a terminal is not the place for chrome.
            if isFocused {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        // ⚠️ THE GESTURE ONLY EXISTS WHILE SPLIT, AND THAT IS THE WHOLE POINT.
        //
        // This used to be an unconditional `.contentShape(Rectangle()).onTapGesture`
        // with the `if showingSplit` guard INSIDE the closure. The guard stopped the
        // ACTION, but the gesture was still installed on every pane, on every device,
        // all the time — and `contentShape(Rectangle())` made the whole pane hit-
        // testable, so a container tap gesture sat on top of the transcript's ScrollView
        // and competed with its drags.
        //
        // Michael, 2026-08-30, on the iPad: "I cant scroll back on my ipad" and "A big
        // bug is from our iphone fix." He was right on both counts. This came in with
        // the iPhone Ultra split-pane work, which he never uses on the iPad, and it cost
        // him the ability to read back through his own conversation.
        //
        // A guard inside a closure does not remove a gesture. The gesture has to not be
        // there.  → Skills Lab: a guard that gives up and forces is not a guard — this
        // is its cousin, a guard placed where it cannot help.
        .modifier(PaneFocusTap(active: showingSplit) { focusedPane = which })
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        tabChip(tab)
                    }
                    addButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            // Regular width only. On the cover screen the button would be an offer the
            // screen cannot honour, and an offer you cannot accept is worse than no offer.
            if widthClass == .regular && tabs.count > 1 {
                splitButton
                    .padding(.trailing, 8)
            }
        }
        .background(.bar)
    }

    private var splitButton: some View {
        Button {
            if showingSplit {
                splitEnabled = false
                focusedPane = .primary
            } else {
                splitEnabled = true
                // Open onto a tab that is not already in the first pane, so the split
                // shows two different terminals rather than the same one twice.
                if companion == nil || companion == selection {
                    companion = tabs.first(where: { $0.id != selection })?.id
                }
                focusedPane = .secondary
            }
        } label: {
            Image(systemName: showingSplit
                  ? "rectangle.split.2x1.fill"
                  : "rectangle.split.2x1")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingSplit ? "Show one terminal" : "Show two terminals side by side")
    }

    /// The label a chip shows: the connection's own name, exactly as it reads in the
    /// connection sheet, or "remote" until one is given.
    ///
    /// Derived rather than stored. `TerminalTab.name` was set once at creation and never
    /// written again, so every tab said "New" forever no matter what it was connected to.
    /// Reading the profile the sheet already persists means renaming a connection renames
    /// its tab with no bookkeeping to keep in sync.
    /// Recompute every chip's label and store the result ONLY if something moved.
    /// The equality check is the whole point — see the note on the notification above.
    private func refreshLabels() {
        var fresh: [UUID: String] = [:]
        for tab in tabs { fresh[tab.id] = label(for: tab) }
        if fresh != labels { labels = fresh }
    }

    private func label(for tab: TerminalTab) -> String {
        // The first tab kept the original un-suffixed key; the rest are per-tab.
        // Same resolution as the TerminalView construction above.
        let key = tab.id == tabs.first?.id ? "connectionProfile" : tab.profileKey
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(ConnectionProfile.self, from: data)
        else { return "remote" }
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        // ⚠️ NO SENTINEL. The first pass also treated "My Mac" as meaning "unconfigured",
        // because the library treats it that way when deciding what to save a connection
        // under. That was wrong here and Michael caught it: the sheet said "My Mac" and
        // the tab said "remote". His rule is literal — "default is remote unless named in
        // the connection sheet" — and "My Mac" IS a name in the sheet. Only genuinely
        // having no name falls back.
        return name.isEmpty ? "remote" : name
    }

    private func tabChip(_ tab: TerminalTab) -> some View {
        // "Selected" means on screen, which is two tabs while split.
        let isSelected = tab.id == selection || (showingSplit && tab.id == companion)
        // The stored label, falling back to a fresh read for a tab added this pass.
        let title = labels[tab.id] ?? label(for: tab)
        return HStack(spacing: 5) {
            Text(title)
                .font(TerminalFont.mono(.footnote))
                .lineLimit(1)
            if tabs.count > 1 {
                Button {
                    close(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            // A chip fills the pane you are looking at. With no split there is only one
            // pane, so this is the old behavior unchanged.
            if showingSplit && focusedPane == .secondary {
                companion = tab.id
            } else {
                selection = tab.id
                // Never show the same terminal twice — move the other pane aside instead.
                if showingSplit && companion == tab.id {
                    companion = tabs.first(where: { $0.id != tab.id })?.id
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var addButton: some View {
        Button {
            let new = TerminalTab(name: "New")
            tabs.append(new)
            selection = new.id
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New terminal tab")
    }

    // MARK: - Lifecycle

    /// Closing a tab does NOT delete its saved profile. He can reopen and it is still
    /// configured — and a mis-tapped x on the wrong tab is then a nuisance rather than a
    /// loss. → fail-safe: never satisfy a request by destroying the work.
    private func close(_ tab: TerminalTab) {
        guard tabs.count > 1 else { return }
        let wasSelected = tab.id == selection
        tabs.removeAll { $0.id == tab.id }
        if wasSelected { selection = tabs.first?.id }
    }

    private func restore() {
        guard tabs.isEmpty else { return }
        if let decoded = try? JSONDecoder().decode([TerminalTab].self, from: storedTabs),
           !decoded.isEmpty {
            tabs = decoded
        } else {
            tabs = [TerminalTab(name: "Terminal")]
        }
        selection = tabs.first?.id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tabs) { storedTabs = data }
    }
}

#Preview {
    TerminalTabsView()
}

/// Tap-to-focus that cannot steal anything underneath it.
///
/// HIS SPECIFICATION, 2026-08-30 07:09, and it is three requirements at once:
///   "I want the tab bar to only be tapable unless you are highlighting to copy scrollable
///    terminal text, you can do it on the mac you should be able to do it on ipad. I want
///    the tabs to only be tapable and to tap the screen you want to focus everything on"
///
///   1. tab bar taps switch tabs
///   2. tapping a screen focuses that screen — he wants this KEPT
///   3. selecting text to copy, and scrolling back, must work like they do on his Mac
///
/// The old code failed 3 to get 2, and it failed it everywhere rather than only while
/// split. `.textSelection(.enabled)` was already on in both views; it did nothing because
/// an exclusive `onTapGesture` over the whole pane consumed the long-press that starts a
/// selection and the drag that scrolls. One cause, all three symptoms.
///
/// TWO CHANGES, BOTH NEEDED:
///   • `simultaneousGesture` instead of `onTapGesture` — it runs ALONGSIDE the scroll view
///     and the text selection rather than in place of them, so nothing is consumed.
///   • only while split — with one pane there is nothing to focus, so the safest thing to
///     put over his transcript is nothing at all.
private struct PaneFocusTap: ViewModifier {
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if active {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            content
        }
    }
}
