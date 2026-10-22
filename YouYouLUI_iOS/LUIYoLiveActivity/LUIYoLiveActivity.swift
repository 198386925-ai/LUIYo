import ActivityKit
import SwiftUI
import WidgetKit

/// Widget bundle for the LUIYo app: today it carries exactly one
/// widget — the update-download Live Activity. The bundle itself
/// must compile for the project's deployment target, so the
/// iOS 16.1 activity widget is availability-gated inside.
@main
struct LUIYoLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            UpdateDownloadActivityWidget()
        }
    }
}

@available(iOS 16.1, *)
struct UpdateDownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UpdateActivityAttributes.self) { context in
            UpdateActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.appName, systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(percent(of: context.state))%")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("更新 \(context.attributes.appName) \(context.attributes.versionLabel)")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                        HStack {
                            Text(context.state.statusText)
                            Spacer()
                            if !context.state.bytesLine.isEmpty {
                                Text(context.state.bytesLine)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
            } compactTrailing: {
                Text("\(percent(of: context.state))%")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Text("\(percent(of: context.state))%")
                    .font(.caption2.monospacedDigit())
            }
        }
    }

    fileprivate func percent(of state: UpdateActivityAttributes.ContentState) -> Int {
        Int((state.progress * 100).rounded())
    }
}

/// Lock-screen / banner presentation: icon, title line, progress
/// bar with percentage and the byte-progress line.
@available(iOS 16.1, *)
struct UpdateActivityLockScreenView: View {
    let context: ActivityViewContext<UpdateActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                Text("更新 \(context.attributes.appName) \(context.attributes.versionLabel)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(Int((context.state.progress * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: context.state.progress)
            HStack {
                Text(context.state.statusText)
                Spacer()
                if !context.state.bytesLine.isEmpty {
                    Text(context.state.bytesLine)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.35))
        .activitySystemActionForegroundColor(Color.white)
    }
}
