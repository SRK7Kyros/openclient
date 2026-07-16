import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

indirect enum StablePickerMenuElement: Equatable, Identifiable {
    case action(id: String, title: String, systemImage: String?, isSelected: Bool)
    case submenu(id: String, title: String, children: [StablePickerMenuElement])
    case inline(id: String, title: String?, children: [StablePickerMenuElement])

    var id: String {
        switch self {
        case let .action(id, _, _, _), let .submenu(id, _, _), let .inline(id, _, _):
            id
        }
    }
}

struct StablePickerMenu<Label: View>: View {
    let elements: [StablePickerMenuElement]
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String?
    let onSelect: (String) -> Void
    let label: Label

    init(
        elements: [StablePickerMenuElement],
        accessibilityLabel: String,
        accessibilityValue: String,
        accessibilityIdentifier: String? = nil,
        onSelect: @escaping (String) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.elements = elements
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        #if canImport(UIKit)
        label
            .allowsHitTesting(false)
            .overlay {
                StableUIKitMenuHost(
                    elements: elements,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifier: accessibilityIdentifier,
                    onSelect: onSelect
                )
            }
        #else
        Menu {
            ForEach(flattenedActions) { action in
                Button {
                    onSelect(action.id)
                } label: {
                    if action.isSelected {
                        Label(action.title, systemImage: "checkmark")
                    } else if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
            }
        } label: {
            label
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        #endif
    }

    private var flattenedActions: [StablePickerMenuAction] {
        elements.flatMap { flatten($0) }
    }

    private func flatten(_ element: StablePickerMenuElement) -> [StablePickerMenuAction] {
        switch element {
        case let .action(id, title, systemImage, isSelected):
            [StablePickerMenuAction(id: id, title: title, systemImage: systemImage, isSelected: isSelected)]
        case let .submenu(_, _, children), let .inline(_, _, children):
            children.flatMap { flatten($0) }
        }
    }
}

private struct StablePickerMenuAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let isSelected: Bool
}

#if canImport(UIKit)
@MainActor
final class StableUIKitMenuCoordinator {
    var onSelect: (String) -> Void
    private(set) var elements: [StablePickerMenuElement] = []

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    func menuIfChanged(for elements: [StablePickerMenuElement]) -> UIMenu? {
        guard elements != self.elements else { return nil }
        self.elements = elements
        let deferred = UIDeferredMenuElement { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            completion(self.makeMenuElements(elements))
        }
        return UIMenu(children: [deferred])
    }

    private func makeMenuElements(_ elements: [StablePickerMenuElement]) -> [UIMenuElement] {
        elements.map { element in
            switch element {
            case let .action(id, title, systemImage, isSelected):
                return UIAction(
                    title: title,
                    image: systemImage.flatMap(UIImage.init(systemName:)),
                    state: isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.onSelect(id)
                }

            case let .submenu(_, title, children):
                return UIMenu(title: title, children: makeMenuElements(children))

            case let .inline(_, title, children):
                return UIMenu(
                    title: title ?? "",
                    options: .displayInline,
                    children: makeMenuElements(children)
                )
            }
        }
    }
}

private struct StableUIKitMenuHost: UIViewRepresentable {
    let elements: [StablePickerMenuElement]
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String?
    let onSelect: (String) -> Void

    func makeCoordinator() -> StableUIKitMenuCoordinator {
        StableUIKitMenuCoordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.accessibilityTraits = .button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue
        button.accessibilityIdentifier = accessibilityIdentifier
        if let menu = context.coordinator.menuIfChanged(for: elements) {
            button.menu = menu
        }
    }
}
#endif
