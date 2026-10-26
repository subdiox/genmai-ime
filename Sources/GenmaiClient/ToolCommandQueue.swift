// Not in Mozc. On iOS there is no DistributedNotificationCenter: the Genmai app and the keyboard extension are
// separate processes that share only the app group container. The app queues its reload requests ("reload",
// "clear_user_history", "clear_user_prediction") in `<profile>/tool_commands`, one per line, and the keyboard
// takes them when it appears (the keyboard is never visible while the app changes its settings, except in the
// app's own text fields, where the next appearance is soon enough).

import Foundation
import GenmaiBase

public enum ToolCommandQueue {
  static let fileName = "tool_commands"

  static var path: String { FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), fileName) }

  /// Appends `command` to the queue. A command already queued is not queued twice.
  public static func post(_ command: String) {
    var commands = read()
    guard !commands.contains(command) else { return }
    commands.append(command)
    do {
      try Data(commands.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
      GenmaiLog.error("Cannot queue the tool command \(command): \(error)")
    }
  }

  /// Returns the queued commands in the order they were posted and empties the queue.
  public static func take() -> [String] {
    let commands = read()
    if !commands.isEmpty {
      try? FileManager.default.removeItem(atPath: path)
    }
    return commands
  }

  private static func read() -> [String] {
    guard let data = FileManager.default.contents(atPath: path) else { return [] }
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
  }
}
