import AppKit
import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var viewModel: SearchPanelViewModel
    @FocusState private var queryFocused: Bool
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(spacing: 10) {
            TextField("Switch window...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.textBackgroundColor).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .focused($queryFocused)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, ranked in
                            SearchResultRow(
                                icon: viewModel.icon(for: ranked),
                                appName: ranked.window.ownerName,
                                title: ranked.window.displayTitle,
                                isSelected: index == viewModel.selectedIndex,
                                isHovered: hoveredIndex == index
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
                            }
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                viewModel.commitSelection()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 420)
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    guard viewModel.results.indices.contains(newIndex) else { return }
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(viewModel.results[newIndex].window.id, anchor: .center)
                    }
                }
                .onChange(of: viewModel.results.map(\.window.id)) { _, _ in
                    guard viewModel.results.indices.contains(viewModel.selectedIndex) else { return }
                    proxy.scrollTo(viewModel.results[viewModel.selectedIndex].window.id, anchor: .center)
                }
            }
        }
        .padding(12)
        .frame(width: 720)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                queryFocused = true
            }
        }
    }
}

private struct SearchResultRow: View {
    let icon: NSImage
    let appName: String
    let title: String
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)

            Text("\(appName)  \(title)")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : (isHovered ? Color.white.opacity(0.08) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
