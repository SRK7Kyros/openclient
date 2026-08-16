import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var shareText = ""
    private var attachments: [OpenClientShareAttachment] = []
    private var servers: [OpenClientShareSavedServer] = []
    private var selectedServer: OpenClientShareSavedServer?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { await loadSharedContent() }
    }

    private func configureView() {
        view.backgroundColor = .systemGroupedBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = String(localized: "Share in OpenClient")
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.text = String(localized: "Step 1: Choose a connection. Step 2 opens the new chat sheet so you can pick any project and send.")
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        summaryLabel.text = String(localized: "Preparing share...")
        summaryLabel.textAlignment = .center
        summaryLabel.font = .preferredFont(forTextStyle: .headline)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.numberOfLines = 0

        activityIndicator.startAnimating()
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.addArrangedSubview(summaryLabel)
        stackView.addArrangedSubview(activityIndicator)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    @MainActor
    private func renderActions() {
        resetStack()
        activityIndicator.stopAnimating()
        titleLabel.text = String(localized: "Share in OpenClient")
        subtitleLabel.text = String(localized: "Step 1: Choose a connection. Step 2 opens the new chat sheet so you can pick any project and send.")
        summaryLabel.text = summaryText

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.addArrangedSubview(summaryLabel)

        servers = OpenClientSharePayloadStore.recentSavedServers()
        let sectionLabel = makeSectionLabel("CHOOSE CONNECTION")
        stackView.addArrangedSubview(sectionLabel)
        if servers.isEmpty {
            addConnectionCard(
                title: String(localized: "Open OpenClient"),
                subtitle: String(localized: "Pick a connection in the app, then choose a project."),
                iconName: "square.and.arrow.up"
            ) { [weak self] in
                self?.renderNewChatStep(server: nil)
            }
        } else {
            for server in servers {
                addConnectionCard(
                    title: server.displayName,
                    subtitle: server.baseURL,
                    iconName: server.iconName ?? "server.rack"
                ) { [weak self] in
                    self?.renderNewChatStep(server: server)
                }
            }
        }

        addCancelButton()
    }

    @MainActor
    private func renderNewChatStep(server: OpenClientShareSavedServer?) {
        selectedServer = server
        resetStack()

        titleLabel.text = String(localized: "New Chat")
        subtitleLabel.text = String(localized: "Step 2: Review what will be sent. OpenClient will open the new chat sheet next so you can choose any project.")
        summaryLabel.text = server.map { String(localized: "Using \($0.displayName)") } ?? String(localized: "Using OpenClient")

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.addArrangedSubview(summaryLabel)
        stackView.addArrangedSubview(makeSharedContentPreview())

        let continueButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Continue to Project Picker")
        configuration.baseBackgroundColor = view.tintColor
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        continueButton.configuration = configuration
        continueButton.layer.cornerRadius = 15
        continueButton.addAction(UIAction { [weak self] _ in
            self?.openOpenClient(server: self?.selectedServer)
        }, for: .touchUpInside)
        stackView.addArrangedSubview(continueButton)

        let backButton = UIButton(type: .system)
        backButton.setTitle(String(localized: "Back"), for: .normal)
        backButton.addAction(UIAction { [weak self] _ in
            self?.renderActions()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(backButton)
    }

    private func resetStack() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeSharedContentPreview() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous

        let title = UILabel()
        title.text = String(localized: "Shared Content")
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true

        let body = UILabel()
        let trimmed = shareText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if attachments.isEmpty {
                body.text = String(localized: "No text or image was found.")
            } else if attachments.count == 1 {
                body.text = String(localized: "\(attachments.count) image attached.")
            } else {
                body.text = String(localized: "\(attachments.count) images attached.")
            }
        } else if attachments.isEmpty {
            body.text = trimmed
        } else if attachments.count == 1 {
            body.text = String(localized: "\(trimmed)\n\n\(attachments.count) image attached.")
        } else {
            body.text = String(localized: "\(trimmed)\n\n\(attachments.count) images attached.")
        }
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.textColor = .secondaryLabel
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 6

        let stack = UIStackView(arrangedSubviews: [title, body])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private var summaryText: String {
        if attachments.isEmpty {
            return shareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Share to OpenClient")
                : String(localized: "Share text to OpenClient")
        }
        if attachments.count == 1 {
            return String(localized: "Share \(attachments.count) image to OpenClient")
        }
        return String(localized: "Share \(attachments.count) images to OpenClient")
    }

    private func makeSectionLabel(_ text: LocalizedStringResource) -> UILabel {
        let label = UILabel()
        label.text = String(localized: text)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func addConnectionCard(title: String, subtitle: String, iconName: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.18 : 0.08
        button.layer.shadowRadius = 14
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let iconView = UIImageView(image: UIImage(systemName: iconName) ?? UIImage(systemName: "server.rack"))
        iconView.tintColor = view.tintColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.backgroundColor = view.tintColor.withAlphaComponent(0.14)
        iconContainer.layer.cornerRadius = 16
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 3

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        let row = UIStackView(arrangedSubviews: [iconContainer, labels, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 54),
            iconContainer.heightAnchor.constraint(equalToConstant: 54),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: button.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -14)
        ])

        button.accessibilityLabel = String(localized: "Share in OpenClient with \(title)")
        stackView.addArrangedSubview(button)
    }

    private func addCancelButton() {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "Cancel"), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }, for: .touchUpInside)
        stackView.addArrangedSubview(button)
    }

    private func loadSharedContent() async {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            await MainActor.run { renderActions() }
            return
        }

        var textItems: [String] = []
        var loadedAttachments: [OpenClientShareAttachment] = []
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let text = await loadText(from: provider) {
                    textItems.append(text)
                }
                if let attachment = await loadImageAttachment(from: provider) {
                    loadedAttachments.append(attachment)
                }
            }
        }

        await MainActor.run {
            shareText = textItems.joined(separator: "\n")
            attachments = loadedAttachments
            renderActions()
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier)?.stringValue
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let value = await loadItem(from: provider, typeIdentifier: UTType.url.identifier) {
            return value.stringValue
        }
        return nil
    }

    private func loadImageAttachment(from provider: NSItemProvider) async -> OpenClientShareAttachment? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              let value = await loadItem(from: provider, typeIdentifier: UTType.image.identifier) else {
            return nil
        }

        let data: Data?
        var mime = "image/jpeg"
        if case let .url(url) = value {
            data = try? Data(contentsOf: url)
            mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        } else if case let .data(rawData) = value {
            data = rawData
        } else if case let .string(string) = value, let url = URL(string: string) {
            data = try? Data(contentsOf: url)
            mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        } else {
            return nil
        }

        guard let data, !data.isEmpty else { return nil }
        let filename = "shared-image-\(UUID().uuidString.prefix(8)).\(mime == "image/png" ? "png" : "jpg")"
        return OpenClientShareAttachment(filename: filename, mime: mime, dataURL: "data:\(mime);base64,\(data.base64EncodedString())")
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> LoadedShareItem? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: .string(string))
                } else if let url = item as? URL {
                    continuation.resume(returning: .url(url))
                } else if let data = item as? Data {
                    continuation.resume(returning: .data(data))
                } else if let image = item as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.9) {
                    continuation.resume(returning: .data(data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func openOpenClient(server: OpenClientShareSavedServer?) {
        let payloadID = UUID().uuidString
        let payload = OpenClientSharePayload(id: payloadID, serverID: server?.recentServerID, text: shareText, attachments: attachments)
        do {
            try OpenClientSharePayloadStore.save(payload)
            var components = URLComponents()
            components.scheme = "openclient"
            components.host = "share"
            components.queryItems = [URLQueryItem(name: "id", value: payloadID)]
            if let server {
                components.queryItems?.append(URLQueryItem(name: "server", value: server.recentServerID))
            }
            guard let url = components.url else { throw CocoaError(.fileWriteInvalidFileName) }
            extensionContext?.open(url) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        } catch {
            summaryLabel.text = error.localizedDescription
        }
    }
}

private enum LoadedShareItem: Sendable {
    case string(String)
    case data(Data)
    case url(URL)

    var stringValue: String? {
        switch self {
        case let .string(string):
            return string
        case let .url(url):
            return url.absoluteString
        case let .data(data):
            return String(data: data, encoding: .utf8)
        }
    }
}
