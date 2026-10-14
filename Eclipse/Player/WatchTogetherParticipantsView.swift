import SwiftUI

struct WatchTogetherParticipantSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isLocal: Bool
    let isReconnecting: Bool
}

#if os(iOS)
struct WatchTogetherParticipantsView: View {
    @ObservedObject private var coordinator = WatchTogetherCoordinator.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var showingList = false

    private func initials(_ name: String) -> String {
        String(name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first))
            .uppercased(with: localization.locale)
    }

    private func avatar(_ person: WatchTogetherParticipantSnapshot) -> some View {
        Text(initials(person.name))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(person.isLocal ? Color.blue : Color.gray))
            .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1.5))
            .opacity(person.isReconnecting ? 0.5 : 1)
            .accessibilityLabel(person.name)
    }

    var body: some View {
        Group {
            if !coordinator.visibleParticipants.isEmpty {
                Button { showingList = true } label: {
                    HStack(spacing: -6) {
                        ForEach(coordinator.visibleParticipants.prefix(4)) { avatar($0) }
                        if coordinator.visibleParticipants.count > 4 {
                            Text("+\(coordinator.visibleParticipants.count - 4)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.black.opacity(0.75)))
                        }
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Participants"))
                .accessibilityIdentifier("player.watchTogether.participants")
                .sheet(isPresented: $showingList) {
                    NavigationStack {
                        List(coordinator.visibleParticipants) { person in
                            HStack(spacing: 12) {
                                avatar(person)
                                Text(person.name)
                                Spacer()
                                if person.isLocal { Text("You").foregroundStyle(.secondary) }
                                if person.isReconnecting { Text("Reconnecting…").foregroundStyle(.secondary) }
                            }
                        }
                        .navigationTitle("Participants")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingList = false } } }
                    }
                    .environment(\.locale, localization.locale)
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .environment(\.locale, localization.locale)
    }
}
#endif
