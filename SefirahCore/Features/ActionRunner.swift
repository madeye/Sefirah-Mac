import Foundation

public enum PowerActionKind: String, Codable, Sendable {
    case lock = "Lock"
    case logOff = "LogOff"
    case sleep = "Sleep"
    case hibernate = "Hibernate"
    case restart = "Restart"
    case shutdown = "Shutdown"
}

public struct ActionExecution: Equatable, Sendable {
    public var kind: String
    public var command: String
    public var arguments: [String]

    public init(kind: String, command: String, arguments: [String] = []) {
        self.kind = kind
        self.command = command
        self.arguments = arguments
    }
}

/// Resolves a desktop action to an OS invocation. Execution of `Process` lives in the app.
public enum ActionRunner {
    public static func plan(_ item: ActionItem) -> ActionExecution {
        switch item.actionId.lowercased() {
        case "link":
            let url = item.settings["url"] ?? item.settings["Url"] ?? ""
            return ActionExecution(kind: "link", command: "open", arguments: [url])
        case "run":
            let path = item.settings["path"] ?? item.settings["Path"] ?? ""
            let args = (item.settings["arguments"] ?? item.settings["Arguments"] ?? "")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            return ActionExecution(kind: "run", command: path, arguments: args)
        case "power":
            let raw = item.settings["powerKind"] ?? item.settings["PowerKind"] ?? "Sleep"
            let kind = PowerActionKind(rawValue: raw) ?? .sleep
            return powerPlan(kind)
        default:
            return ActionExecution(kind: "unknown", command: "", arguments: [])
        }
    }

    public static func handleIncoming(_ action: ActionInfo, catalog: [ActionItem]) -> ActionExecution? {
        guard let item = catalog.first(where: { $0.id == action.actionId || $0.name == action.actionName }) else {
            return nil
        }
        return plan(item)
    }

    public static func actionList(from items: [ActionItem]) -> ActionList {
        ActionList(
            actions: items.map {
                ActionInfo(
                    actionId: $0.id,
                    actionName: $0.name.isEmpty ? $0.actionId : $0.name,
                    icon: $0.icon,
                    askForConfirmation: $0.askForConfirmation
                )
            }
        )
    }

    private static func powerPlan(_ kind: PowerActionKind) -> ActionExecution {
        switch kind {
        case .lock:
            return ActionExecution(
                kind: "power",
                command: "/usr/bin/osascript",
                arguments: [
                    "-e",
                    "tell application \"System Events\" to keystroke \"q\" using {control down, command down}",
                ]
            )
        case .sleep:
            return ActionExecution(kind: "power", command: "/usr/bin/pmset", arguments: ["sleepnow"])
        case .restart:
            return ActionExecution(kind: "power", command: "/sbin/shutdown", arguments: ["-r", "now"])
        case .shutdown:
            return ActionExecution(kind: "power", command: "/sbin/shutdown", arguments: ["-h", "now"])
        case .logOff:
            return ActionExecution(kind: "power", command: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to log out"])
        case .hibernate:
            return ActionExecution(kind: "power", command: "", arguments: [])
        }
    }
}
