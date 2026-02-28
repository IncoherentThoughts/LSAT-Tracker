import SwiftUI

enum Tab: Int, CaseIterable {
    case settings = 0
    case timer    = 1
    case stats    = 2

    var icon: String {
        switch self {
        case .settings: return "person"
        case .timer:    return "circle.fill"
        case .stats:    return "chart.bar.fill"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .timer

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .settings: SettingsView()
                case .timer:    TimerView()
                case .stats:    StatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomNavBar(selectedTab: $selectedTab)
        }
        .background(Color.eggshell.ignoresSafeArea())
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Bottom Nav Bar

private struct BottomNavBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(alignment: .center) {
            NavButton(tab: .stats, selectedTab: $selectedTab)
            Spacer()
            NavButton(tab: .timer, selectedTab: $selectedTab)
            Spacer()
            NavButton(tab: .settings, selectedTab: $selectedTab)
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            Color.toffeeBrown
                .shadow(color: .toffeeBrown.opacity(0.4), radius: 16, y: -6)
        )
    }
}

private struct NavButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTab = tab
            }
        } label: {
            if tab == .timer {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.rosyCopper : Color.eggshell.opacity(0.25))
                        .frame(width: 48, height: 48)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isSelected ? .eggshell : .lightBronze)
                }
            } else {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .rosyCopper : .lightBronze)
                    .frame(width: 48, height: 48)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
        .environment(TimerManager())
        .environment(StudyStore())
}
