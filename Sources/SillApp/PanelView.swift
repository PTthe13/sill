import SillCore
import SwiftUI

/// The detail band. Vertical edges get a card; horizontal edges get a bar that
/// sizes itself to its content, so the footer is never clipped.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    private var secondary: Color { .white.opacity(model.material.secondaryTextAlpha) }
    private var border: Color { .white.opacity(model.material.borderAlpha) }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            // A full-width bar keeps its content in a readable column rather
            // than stretching a process row across the whole screen.
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }

    @ViewBuilder private var content: some View {
        if model.isHorizontal { bar } else { card }
    }

    /// Left and right edges: a narrow card, read top to bottom.
    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            headline
            tiles
            Divider().overlay(border)
            processList
            Divider().overlay(border)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Top and bottom edges: one line of glass across the band, with the
    /// groups spread along it rather than stretched or huddled in the middle.
    private var bar: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                headline
                tiles
            }
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 18)
            processList.frame(maxWidth: 400)
            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 6) {
                ForEach(footerItems, id: \.self) { Text($0) }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The judgement first, at a size worth reading across a desk; what the
    /// wave encodes underneath it, as reference.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.headroomTitle)
                .font(.system(size: 17, weight: .medium))
                .kerning(-0.2)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.encodingLine)
                .font(.system(size: 12.5))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var footerItems: [String] {
        [model.batteryText, model.spanText].compactMap { $0 }
    }

    /// Reduce Transparency gets a deliberate solid fill, not a system guess.
    @ViewBuilder private var background: some View {
        if model.reduceTransparency {
            Color(red: 0.07, green: 0.08, blue: 0.09)
        } else {
            Color.black.opacity(model.material == .clear ? 0.32 : 0.54)
        }
    }

    /// Six readings: two across on the narrow card, six across on the bar.
    /// Network and disk carry both directions, because "2.4 down" and
    /// "0.3 up" answer different questions.
    private var tiles: some View {
        // Three across on the bar: six would fit the width on paper and squeeze
        // every label into two broken lines in practice.
        let columns = 3
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                        count: columns), spacing: 10) {
            tile("CPU", "\(model.cpuPercent.roundedInt)%")
            tile("Memory", model.memoryText)
            tile("GPU", model.gpuText)
            tile("Free", model.diskText)
            tile("Net MB/s", "\(model.networkDown) ↓", secondary: "\(model.networkUp) ↑")
            tile("Disk MB/s", "\(model.diskRead) ↓", secondary: "\(model.diskWrite) ↑")
        }
    }

    /// `secondary` is the second direction on a two-way reading — read under
    /// written, down under up — at a size that keeps the tile one glance.
    private func tile(_ label: String, _ value: String,
                      secondary secondLine: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(secondary)
            Text(value)
                .font(.system(size: 23, weight: .medium))
                .monospacedDigit()
                .kerning(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let secondLine {
                Text(secondLine)
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15,
                                                                   style: .continuous))
    }

    /// Always four rows, so the panel's height doesn't change under the
    /// pointer as readings arrive.
    private var rows: [ProcessUsage?] {
        let rows = model.processes.prefix(PanelModel.processRowCount).map { Optional($0) }
        return rows + Array(repeating: nil, count: PanelModel.processRowCount - rows.count)
    }

    @ViewBuilder private var processList: some View {
        let peak = max(model.processes.first?.cpuPercent ?? 1, 1)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let process = row ?? ProcessUsage(pid: 0, name: "—", cpuPercent: 0)
                HStack(spacing: 10) {
                    Text(process.name)
                        .font(.system(size: 13.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Capsule()
                        .fill(color(forLoad: process.cpuPercent * 2.4))
                        .frame(width: max(4, 60 * process.cpuPercent / peak), height: 5)
                        .opacity(row == nil ? 0 : 1)
                    Text(row == nil ? "" : String(format: "%.1f%%", process.cpuPercent))
                        .font(.system(size: 13.5, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }
                .opacity(row == nil ? 0.45 : 1)
                .padding(.vertical, 5)
            }
        }
    }

    private func color(forLoad value: Double) -> Color {
        let stop = model.ramp.stop(forLoad: value)
        return Color(.sRGB, red: stop.red, green: stop.green, blue: stop.blue,
                     opacity: stop.alpha)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ForEach(Array(footerItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { Spacer(minLength: 6) }
                Text(item)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}
