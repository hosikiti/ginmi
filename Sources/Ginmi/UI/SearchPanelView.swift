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
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            VStack(spacing: 6) {
                                if shouldShowInstalledAppsSeparator(before: index) {
                                    SearchResultsSeparator(title: "Installed Applications")
                                }

                                SearchResultRow(
                                    icon: viewModel.icon(for: result),
                                    appName: result.rowAppName,
                                    title: result.rowTitle,
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
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 420)
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    guard viewModel.results.indices.contains(newIndex) else { return }
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(viewModel.results[newIndex].id, anchor: .center)
                    }
                }
                .onChange(of: viewModel.results.map(\.id)) { _, _ in
                    guard viewModel.results.indices.contains(viewModel.selectedIndex) else { return }
                    proxy.scrollTo(viewModel.results[viewModel.selectedIndex].id, anchor: .center)
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

    private func shouldShowInstalledAppsSeparator(before index: Int) -> Bool {
        guard viewModel.results.indices.contains(index) else { return false }
        guard case .app = viewModel.results[index].kind else { return false }
        guard index > 0 else { return false }
        guard case .window = viewModel.results[index - 1].kind else { return false }
        return true
    }
}

private struct SearchResultsSeparator: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
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

            Text(rowText)
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

    private var rowText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return appName }
        return "\(appName)  \(trimmedTitle)"
    }
}
