// The uninstaller window (replaces mozc/src/mac/Uninstaller/{English,Japanese}.lproj/Dialogs.xib, 3.35.6354):
// the app icon with a status badge, a title and an explanation, the items that will be removed, and the buttons
// of the current phase at the bottom right.

import AppKit
import SwiftUI

struct UninstallerView: View {
  let controller: UninstallerController

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      UninstallerHeader(controller: controller)
      if controller.phase != .succeeded {
        RemoveItemList(items: controller.items, strings: controller.strings)
          .padding(.top, 16)
        if (controller.phase == .confirm || controller.phase == .removing) && !controller.userData.isEmpty {
          UserDataSection(controller: controller)
            .padding(.top, 16)
        }
      }
      UninstallerFooter(controller: controller)
        .padding(.top, 20)
    }
    .padding(.horizontal, 24)
    .padding(.top, 28)
    .padding(.bottom, 20)
    .frame(width: 480)
    .animation(.default, value: controller.phase)
    .navigationTitle(controller.strings.windowTitle)
  }
}

private struct UninstallerHeader: View {
  let controller: UninstallerController

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      AppIcon(icon: controller.icon, phase: controller.phase)
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.title2.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        Text(message)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var title: String {
    let strings = controller.strings
    switch controller.phase {
    case .confirm, .removing: return strings.confirmTitle
    case .succeeded: return strings.succeededTitle
    case .failed: return strings.failedTitle
    }
  }

  private var message: String {
    let strings = controller.strings
    switch controller.phase {
    case .confirm, .removing: return strings.confirmMessage(needsAuthorization: controller.needsAuthorization)
    case .succeeded: return strings.succeededMessage
    case .failed(.authorization): return strings.authorizationFailedMessage
    case .failed(.removal): return strings.removalFailedMessage
    }
  }
}

/// The app icon, badged with the outcome once there is one.
private struct AppIcon: View {
  let icon: NSImage
  let phase: UninstallerController.Phase

  var body: some View {
    Image(nsImage: icon)
      .resizable()
      .interpolation(.high)
      .frame(width: 64, height: 64)
      .overlay(alignment: .bottomTrailing) {
        badge
          .font(.system(size: 22))
          .symbolRenderingMode(.palette)
          .background(.background, in: .circle)
          .offset(x: 4, y: 4)
          .transition(.scale.combined(with: .opacity))
      }
      .accessibilityHidden(true)
  }

  @ViewBuilder private var badge: some View {
    switch phase {
    case .confirm, .removing:
      EmptyView()
    case .succeeded:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green)
    case .failed:
      Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white, .orange)
    }
  }
}

private struct RemoveItemList: View {
  let items: [RemoveItem]
  let strings: UninstallerStrings

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element) { index, item in
        if index > 0 {
          Divider().padding(.leading, 44)
        }
        RemoveItemRow(item: item, name: strings.itemName(item.kind))
      }
    }
    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    .overlay(.separator, in: .rect(cornerRadius: 10).stroke(lineWidth: 0.5))
  }
}

/// The user's data, each kind with a check box: removed too when checked.
private struct UserDataSection: View {
  @Bindable var controller: UninstallerController

  var body: some View {
    let strings = controller.strings
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.alsoRemove)
        .font(.headline)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(controller.userData.enumerated()), id: \.element) { index, item in
          if index > 0 {
            Divider().padding(.leading, 36)
          }
          UserDataRow(item: item, strings: strings, isOn: binding(item.kind))
        }
      }
      .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
      .overlay(.separator, in: .rect(cornerRadius: 10).stroke(lineWidth: 0.5))
      .disabled(controller.isBusy)
      Label(strings.keptNote, systemImage: "info.circle")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func binding(_ kind: UserDataKind) -> Binding<Bool> {
    Binding {
      controller.selectedUserData.contains(kind)
    } set: { isOn in
      if isOn {
        controller.selectedUserData.insert(kind)
      } else {
        controller.selectedUserData.remove(kind)
      }
    }
  }
}

private struct UserDataRow: View {
  let item: UserDataItem
  let strings: UninstallerStrings
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 1) {
        Text(strings.userDataName(item.kind))
        Text(verbatim: strings.userDataDetail(item.kind) + " · " + item.size.formatted(.byteCount(style: .file)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.leading, 4)
    }
    .toggleStyle(.checkbox)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RemoveItemRow: View {
  let item: RemoveItem
  let name: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "keyboard")
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(name)
        Text(verbatim: item.displayPath)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }
}

private struct UninstallerFooter: View {
  let controller: UninstallerController

  var body: some View {
    let strings = controller.strings
    HStack(spacing: 12) {
      if controller.isBusy {
        ProgressView()
          .controlSize(.small)
        Text(strings.removing)
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      Spacer(minLength: 0)
      switch controller.phase {
      case .confirm, .removing:
        if !controller.isBusy {
          Button(strings.cancel, action: controller.close)
            .keyboardShortcut(.cancelAction)
        }
        Button(strings.uninstall, role: .destructive, action: uninstall)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(.red)
      case .succeeded:
        Button(strings.later, action: controller.close)
          .keyboardShortcut(.cancelAction)
        Button(strings.logOutNow, action: controller.logOutNow)
          .keyboardShortcut(.defaultAction)
      case .failed:
        Button(strings.quit, action: controller.close)
          .keyboardShortcut(.cancelAction)
        Button(strings.tryAgain, action: uninstall)
          .keyboardShortcut(.defaultAction)
      }
    }
    .controlSize(.large)
    .disabled(controller.isBusy)
  }

  private func uninstall() {
    Task { await controller.uninstall() }
  }
}
