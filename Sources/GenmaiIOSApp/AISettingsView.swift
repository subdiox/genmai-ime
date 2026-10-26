// The AI conversion settings of the iOS app (not in Mozc): the macOS AI tab's settings and model management (the
// same `ConfigDialogModel` state and `AIStrings`) in an iOS form. The models go into the shared profile, where the
// keyboard extension loads the selected one; it picks the change up when it appears (RELOAD through
// `ToolCommandQueue`).

#if os(iOS)
  import GenmaiClient
  import GenmaiGUI
  import SwiftUI

  struct AISettingsView: View {
    @Bindable var model: ConfigDialogModel

    var body: some View {
      Form {
        Section {
          Toggle(AIStrings.text(.enable), isOn: $model.aiValues.enabled)
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: AIStrings.text(.explanation))
            Text(verbatim: AppStrings.text(.aiFullAccess))
          }
        }
        Section {
          Picker(AIStrings.text(.size), selection: $model.aiValues.modelSize) {
            ForEach(AIModelSize.allCases, id: \.self) { size in
              Text(verbatim: AIStrings.sizeName(size)).tag(size)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Text(verbatim: AIStrings.text(.size))
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: AIStrings.text(.sizeNote))
            if !model.aiModelStatus().isFound {
              Label(AIStrings.text(.selectedMissing), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
          }
        }
        Section {
          ForEach(AIModelSize.allCases, id: \.self) { size in
            IOSModelRow(model: model, size: size)
          }
        } header: {
          Text(verbatim: AIStrings.text(.sectionModel))
        }
      }
      .navigationTitle(AIStrings.text(.sectionAI))
      .refreshable {
        model.refreshAIModelStatus()
        await model.checkLatestAIModels(force: true)
      }
      .task { await model.checkLatestAIModels() }
    }
  }

  /// One model: installed version and size, in use, download / update with progress, removal (swipe or button).
  private struct IOSModelRow: View {
    let model: ConfigDialogModel
    let size: AIModelSize

    var body: some View {
      let status = model.aiModelStatus(size)
      let installing = model.aiModelInstallSize == size && model.aiModelInstall.isRunning
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(verbatim: AIStrings.rowTitle(size))
                .font(.headline)
              if model.aiValues.modelSize == size {
                Text(verbatim: AIStrings.text(.inUse))
                  .font(.caption)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 1)
                  .background(.tint.opacity(0.15), in: .capsule)
              }
            }
            Text(verbatim: AIStrings.rowStatus(status, diskSize: model.aiModelDiskSizes[size]))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: status.isFound ? "checkmark.circle.fill" : "icloud.and.arrow.down")
            .foregroundStyle(status.isFound ? .green : .secondary)
            .accessibilityHidden(true)
        }
        if installing, case .running(let phase) = model.aiModelInstall {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: AIStrings.installPhase(phase))
              .font(.subheadline)
              .monospacedDigit()
            if case .downloading(let received, let total) = phase {
              ProgressView(value: Double(received), total: Double(max(total, 1)))
            } else {
              ProgressView()
                .progressViewStyle(.linear)
            }
            Button(AIStrings.text(.cancel), role: .cancel) { model.cancelAIModelInstall() }
              .buttonStyle(.borderless)
          }
        } else {
          latest(status)
          if model.aiModelInstallSize == size, case .failed(let message) = model.aiModelInstall {
            Text(verbatim: String(format: AIStrings.text(.installFailed), message))
              .font(.footnote)
              .foregroundStyle(.red)
          }
          if status.isFound {
            Button(AIStrings.text(.remove), role: .destructive) { model.removeAIModel(size) }
              .buttonStyle(.borderless)
              .disabled(model.aiModelInstall.isRunning)
          }
        }
      }
      .padding(.vertical, 4)
    }

    @ViewBuilder
    private func latest(_ status: AIModelStatus) -> some View {
      switch model.aiModelLatest[size] ?? .unknown {
      case .unknown, .checking:
        HStack(spacing: 8) {
          ProgressView()
          Text(verbatim: AIStrings.text(.checkingLatest))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      case .failed(let message):
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: String(format: AIStrings.text(.latestFailed), message))
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button(AIStrings.text(.retry)) {
            Task { await model.checkLatestAIModel(size, force: true) }
          }
          .buttonStyle(.borderless)
        }
      case .available(let release):
        if status.needsInstall(release) {
          VStack(alignment: .leading, spacing: 4) {
            Button(AIStrings.releaseText(status.isFound ? .update : .download, release)) {
              model.installAIModel(size)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.aiModelInstall.isRunning)
            Text(verbatim: AIStrings.downloadNote(release))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(verbatim: AIStrings.releaseText(.modelUpToDate, release))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
#endif
