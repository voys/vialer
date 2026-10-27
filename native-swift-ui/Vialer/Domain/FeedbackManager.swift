import Foundation
import Observation

enum CallProblem: String, CaseIterable, Identifiable {
    case oneWayAudio, noAudio, audioProblem, endedUnexpectedly, somethingElse
    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneWayAudio: return L10n.main.call.feedback.problem.oneWayAudio
        case .noAudio: return L10n.main.call.feedback.problem.noAudio
        case .audioProblem: return L10n.main.call.feedback.problem.audioProblem
        case .endedUnexpectedly: return L10n.main.call.feedback.problem.endedUnexpectedly
        case .somethingElse: return L10n.main.call.feedback.problem.somethingElse
        }
    }
}

enum CallAudioProblem: String, CaseIterable, Identifiable {
    case jitter, echo, crackling, robotic, tooQuiet, tooLoud
    var id: String { rawValue }

    var title: String {
        switch self {
        case .jitter: return L10n.main.call.feedback.audioProblems.jitter
        case .echo: return L10n.main.call.feedback.audioProblems.echo
        case .crackling: return L10n.main.call.feedback.audioProblems.crackling
        case .robotic: return L10n.main.call.feedback.audioProblems.robotic
        case .tooQuiet: return L10n.main.call.feedback.audioProblems.tooQuiet
        case .tooLoud: return L10n.main.call.feedback.audioProblems.tooLoud
        }
    }
}

/// A finished call the user is asked to rate.
struct CallToRate: Identifiable {
    let id = UUID()
    let call: CallSnapshot.CallInfo
    let usedRoutes: Set<AudioRoute>
}

/// Post-call ratings and the periodic app-rating survey, with the Flutter app's trigger rules.
@MainActor
@Observable
final class FeedbackManager {
    var callToRate: CallToRate?
    var surveyToShow: Survey?

    private weak var session: SessionManager?
    private let store = LocalStore.shared

    private static let callRatingChancePercent = 15
    private static let daysBetweenCallRatings = 7.0
    private static let surveyActionsRequired = 20
    private static let daysBetweenSurveys = 28.0
    private static let surveyChancePercent = 50

    func bind(session: SessionManager) { self.session = session }

    // MARK: Call rating

    func callEnded(_ call: CallSnapshot.CallInfo, usedRoutes: Set<AudioRoute>) {
        incrementSurveyActionCount()
        guard call.duration >= 1, shouldRequestCallRating() else { return }
        callToRate = CallToRate(call: call, usedRoutes: usedRoutes)
    }

    private func shouldRequestCallRating() -> Bool {
        guard Int.random(in: 0...100) <= Self.callRatingChancePercent else { return false }
        if let last: Date = store.get(.lastCallRatingAskedTime),
           Date().timeIntervalSince(last) < Self.daysBetweenCallRatings * 86_400 {
            return false
        }
        store.set(Date(), for: .lastCallRatingAskedTime)
        return true
    }

    func submitCallRating(_ rated: CallToRate, rating: Int, problem: CallProblem?, audioProblems: [CallAudioProblem]) {
        var properties: [String: Any] = [
            "rating": rating,
            "mos": rated.call.mos,
            "duration": rated.call.duration,
            "direction": rated.call.isInbound ? "inbound" : "outbound",
            "bluetooth-used": rated.usedRoutes.contains(.bluetooth),
            "phone-used": rated.usedRoutes.contains(.phone),
            "speaker-used": rated.usedRoutes.contains(.speaker),
            "problem": problem?.rawValue ?? false,
        ]
        for audioProblem in CallAudioProblem.allCases {
            properties[audioProblem.rawValue] = audioProblems.contains(audioProblem)
        }
        Metrics.track("voip-call-rated", properties)
    }

    // MARK: Surveys

    private func incrementSurveyActionCount() {
        let count: Int = store.get(.appRatingSurveyActionCount) ?? 0
        store.set(count + 1, for: .appRatingSurveyActionCount)
    }

    /// Called when the main screen appears, never during a call. Only the app rating survey has a
    /// trigger; the Flutter app never wired one up for the messaging-apps survey, so neither does this.
    func checkSurveys(isInCall: Bool) {
        guard !isInCall, surveyToShow == nil, session?.settings.showSurveys == true else { return }
        if shouldShowAppRatingSurvey() {
            store.set(Date(), for: .appRatingSurveyShownTime)
            store.set(0, for: .appRatingSurveyActionCount)
            AppLog.info("App rating survey triggered")
            surveyToShow = .appRating
        }
    }

    private func shouldShowAppRatingSurvey() -> Bool {
        let count: Int = store.get(.appRatingSurveyActionCount) ?? 0
        guard count >= Self.surveyActionsRequired else { return false }
        if let last: Date = store.get(.appRatingSurveyShownTime),
           Date().timeIntervalSince(last) < Self.daysBetweenSurveys * 86_400 {
            return false
        }
        return Int.random(in: 0...100) <= Self.surveyChancePercent
    }

    /// Answers are indexed by question id; a missing answer is reported as null.
    func submitSurvey(_ survey: Survey, answers: [Int: Int]) {
        var properties: [String: Any]
        switch survey.id {
        case .appRating:
            properties = ["rating": answers[0].map { $0 + 1 } ?? NSNull()]
        case .messagingApps:
            properties = [
                "language": Locale.current.language.languageCode?.identifier ?? "en",
                "trigger": "on-app-launch",
            ]
            for question in survey.questions {
                properties["question-\(question.id)"] = answers[question.id] ?? NSNull()
            }
        }
        Metrics.track("\(survey.id.rawValue)-survey", properties)
    }

    func setDontShowSurveysAgain(_ value: Bool) {
        session?.settings.showSurveys = !value
    }
}
