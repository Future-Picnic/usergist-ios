import SwiftUI
import UIKit
import XCTest
@testable import UserGistFeedback

/// Opt-in visual review: renders the real renderers off-screen to PNGs.
/// Run with `TEST_RUNNER_UG_SNAPSHOT_DIR=/tmp/dir xcodebuild test ...`.
/// Skipped by default; these are review images, not pixel assertions.
@MainActor
final class SurfaceSnapshotTests: XCTestCase {
    private static let portrait = CGSize(width: 402, height: 874)
    private static let landscape = CGSize(width: 874, height: 402)
    /// Landscape height left above a software keyboard (approximation).
    private static let landscapeKeyboard = CGSize(width: 874, height: 196)

    private static let themes: [(String, PromptTheme?)] = [
        ("default", nil),
        ("violet", PromptTheme(colors: .init(primary: "#7C3AED", background: "#FAF5FF", text: "#3B1764",
                                             subtext: "#6D5A7F", border: "#E9D5FF"), radius: 20)),
        ("midnight", PromptTheme(colors: .init(primary: "#5EEAD4", background: "#111827", text: "#F3F4F6",
                                               subtext: "#9CA3AF", border: "#374151"), radius: 16)),
        ("sunflower", PromptTheme(colors: .init(primary: "#FACC15", background: "#FFFFFF", text: "#1C1917",
                                                subtext: "#78716C", border: "#E7E5E4"), radius: 12))
    ]

    private var outputDir: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["UG_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set UG_SNAPSHOT_DIR to render review snapshots")
        }
        outputDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    // MARK: Feedback sheet

    func testFeedbackSheets() throws {
        let questions: [(String, Question)] = [
            ("text", .shortText(.init(id: "t", title: "What almost stopped you today?", subtitle: nil,
                                      imageUrl: nil, placeholder: "Tell us in a sentence or two", maxLength: 280))),
            ("nps", .nps(.init(id: "n", title: "How likely are you to recommend us to a friend?", subtitle: nil,
                               imageUrl: nil, followUp: "What is the main reason for your score?",
                               lowLabel: nil, highLabel: nil))),
            ("choice", .multipleChoice(.init(id: "c", title: "What should we work on next?", subtitle: nil,
                                             imageUrl: nil, options: [
                                                .init(id: "search", label: "Better search"),
                                                .init(id: "offline", label: "Offline access"),
                                                .init(id: "sync", label: "Sync across devices")
                                             ], multiSelect: true))),
            ("stars", .rating(.init(id: "r", title: "How was checkout?", subtitle: "Tap a star",
                                    imageUrl: nil, scale: 5, display: .stars, lowLabel: nil, highLabel: nil)))
        ]
        for (themeName, server) in Self.themes {
            let theme = ThemeResolver.resolve(server: server, override: nil)
            for (name, question) in questions {
                for (orientation, size) in [("portrait", Self.portrait), ("landscape", Self.landscape),
                                            ("landscape-kb", Self.landscapeKeyboard)] {
                    if orientation == "landscape-kb" && name != "text" { continue }
                    let view = PromptView(prompt: ClientPrompt(id: "p", questions: [question], theme: nil),
                                          theme: theme, onFinish: { _ in })
                    try render(sheet: view, theme: theme, size: size, select: name == "nps" ? 10 : nil,
                               name: "feedback-\(name)-\(themeName)-\(orientation)")
                }
            }
        }
    }

    private func render(sheet view: PromptView, theme: ResolvedTheme, size: CGSize, select: Int?, name: String) throws {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let root = UIViewController()
        root.view.backgroundColor = UIColor(white: 0.9, alpha: 1)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let sheet = UIView()
        sheet.backgroundColor = theme.background
        sheet.layer.cornerRadius = theme.radius
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.clipsToBounds = true
        let scrim = UIView(frame: root.view.bounds)
        scrim.backgroundColor = theme.scrim
        root.view.addSubview(scrim)
        root.view.addSubview(sheet)
        sheet.addSubview(view)
        view.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: 10))
        view.layoutIfNeeded()
        // Package tests have no UIApplication to dispatch control actions.
        if let select, let nps = descendants(of: view, type: NpsQuestionView.self).first,
           let cell = descendants(of: nps, type: UIButton.self)
            .first(where: { $0.accessibilityLabel?.hasPrefix("Score \(select)") == true }),
           let action = cell.actions(forTarget: nps, forControlEvent: .touchUpInside)?.first {
            nps.perform(NSSelectorFromString(action), with: cell)
        }
        let height = view.preferredHeight(forWidth: size.width)
        let frame = PromptSheetLayout.frame(containerBounds: root.view.bounds, safeTop: 0,
                                            requestedHeight: height, keyboardOverlap: 0)
        sheet.frame = frame
        view.frame = sheet.bounds
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try save(window: window, name: name)
    }

    // MARK: In-app messages

    func testInAppMessages() throws {
        let formats = ["modal", "slideup", "modal_full"]
        for (themeName, server) in Self.themes where themeName != "default" {
            let theme = ThemeResolver.resolve(server: server, override: nil)
            for format in formats {
                for stress in [false, true] {
                    let ctas = stress
                        ? #"[{"label":"Start sharing lists with your family and friends","action":"dismiss"},{"label":"Remind me about this next week","action":"dismiss"}]"#
                        : #"[{"label":"Try shared lists","action":"dismiss"},{"label":"Not now","action":"dismiss"}]"#
                    let body = stress
                        ? String(repeating: "Invite anyone to a list and see changes as they happen. ", count: 6)
                        : "Invite anyone to a list and see changes as they happen."
                    let json = """
                    {"messageId":"m","eventName":"e","format":"\(format)","title":"Shared lists are here",
                     "body":"\(body)","backdropEnabled":true,"ctas":\(ctas)}
                    """
                    let message = try JSONDecoder().decode(ArmedInAppMessage.self, from: Data(json.utf8))
                    for (orientation, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                        let controller = InAppMessageController(message: message, theme: theme,
                                                                onDismiss: { _ in }, onCta: { _, _ in })
                        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                        window.rootViewController = controller
                        window.makeKeyAndVisible()
                        controller.view.frame = window.bounds
                        controller.view.setNeedsLayout()
                        controller.view.layoutIfNeeded()
                        try save(window: window, name: "inapp-\(format)\(stress ? "-long" : "")-\(themeName)-\(orientation)")
                        window.isHidden = true
                    }
                }
            }
        }
    }

    // MARK: Survey

    func testSurveys() throws {
        let flowJSON = """
        {"startQuestionId":"role","progressStyle":"bar","backNavigation":true,"branches":[],
         "questions":[
          {"id":"role","type":"single_choice","title":"How do you mostly use the app?","required":true,
           "options":[{"id":"work","label":"For work"},{"id":"personal","label":"For personal projects"},
                      {"id":"both","label":"A bit of both"}]},
          {"id":"score","type":"nps","title":"How likely are you to recommend us?"},
          {"id":"details","type":"long_text","title":"What would make it better?","placeholder":"Tell us more",
           "maxLength":500}
         ]}
        """
        let flow = try JSONDecoder().decode(SurveyFlow.self, from: Data(flowJSON.utf8))
        let storage = try Storage(writeKeyHash: "snapshot-" + UUID().uuidString)
        let store = SurveyStore(storage: storage, logger: UserGistLogger(debug: false),
                                queue: DispatchQueue(label: "snapshot-survey"))
        for (themeName, server) in Self.themes {
            let theme = ThemeResolver.resolve(server: server, override: nil)
            for questionId in ["role", "score", "details", "end"] {
                for (orientation, size) in [("portrait", Self.portrait), ("landscape", Self.landscape),
                                            ("landscape-kb", Self.landscapeKeyboard)] {
                    if orientation == "landscape-kb" && questionId != "details" { continue }
                    let model = NativeSurveyViewModel(
                        flow: flow, surveyId: "s", attemptId: "a", store: store,
                        resume: nil, onProgress: { _, _, _ in }, onComplete: { _, _, done in done(true) })
                    if questionId == "end" {
                        model.isComplete = true
                        model.currentQuestionId = nil
                    } else {
                        // Reach later steps through real answers so Back history
                        // exists and the header shows Back leading, Close trailing.
                        if questionId != "role" { model.select(.string("work"), autoAdvance: true) }
                        if questionId == "details" { model.select(.int(10), autoAdvance: true) }
                        model.currentQuestionId = questionId
                        if questionId == "score" { model.answers["score"] = .int(10) }
                    }
                    let view = NativeSurveyView(
                        viewModel: model,
                        endScreen: SurveyEndScreen(headline: "Thanks for helping", body: "Your answers shape what we build next.",
                                                   cta: nil, followUp: nil),
                        theme: theme, onClose: {}, onAbandon: { _ in })
                    try renderHosted(AnyView(view), theme: theme, size: size,
                                     name: "survey-\(questionId)-\(themeName)-\(orientation)")
                }
            }
        }
    }

    // MARK: Helpers

    private func renderHosted(_ view: AnyView, theme: ResolvedTheme, size: CGSize, name: String) throws {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = theme.background
        host.overrideUserInterfaceStyle = theme.interfaceStyle
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try save(window: window, name: name)
    }

    private func save(window: UIWindow, name: String) throws {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        // Hostless test bundles have no screen, so drawHierarchy is blank;
        // render the layer tree directly.
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: outputDir.appendingPathComponent("\(name).png"))
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
