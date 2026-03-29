import SwiftUI

struct TabSelector: View {
    @Binding var selectedTab: ResultTab
    var tabs: [ResultTab] = ResultTab.allCases.filter { $0 != .chat }
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.filter { $0 != .chat }) { tab in
                Button {
                    Haptics.selection()
                    withAnimation(Theme.Animation.smooth) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.label)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Theme.Colors.accent : Theme.Colors.textTertiary)

                        ZStack {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Theme.Colors.accent)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "tabUnderline", in: animation)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}
