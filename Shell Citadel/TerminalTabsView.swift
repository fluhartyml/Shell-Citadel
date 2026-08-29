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
//  what tabs are for. So all tabs are built in a ZStack and the unselected ones are merely
//  hidden. Live sessions survive switching, which is the whole point.
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
    @State private var tabs: [TerminalTab] = []
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 { tabBar }

            ZStack {
                ForEach(tabs) { tab in
                    // The first tab keeps the ORIGINAL storage key so an existing install
                    // opens already pointed at his Mac rather than blank.
                    TerminalView(profileKey: tab.id == tabs.first?.id ? "connectionProfile"
                                                                     : tab.profileKey)
                        .opacity(tab.id == selection ? 1 : 0)
                        .allowsHitTesting(tab.id == selection)
                        // Keep it laid out but out of the accessibility tree, so
                        // VoiceOver does not read three hidden terminals.
                        .accessibilityHidden(tab.id != selection)
                }
            }
        }
        .onAppear(perform: restore)
        .onChange(of: tabs) { _, _ in persist() }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
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
        .background(.bar)
    }

    private func tabChip(_ tab: TerminalTab) -> some View {
        let isSelected = tab.id == selection
        return HStack(spacing: 5) {
            Text(tab.name)
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
                .accessibilityLabel("Close \(tab.name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { selection = tab.id }
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
