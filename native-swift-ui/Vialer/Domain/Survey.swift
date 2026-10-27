import Foundation

enum SurveyId: String {
    case appRating = "app-rating"
    case messagingApps = "messaging-apps"
}

struct SurveyQuestion: Identifiable {
    let id: Int
    /// Short heading shown above the question, if the survey has one per question.
    var title: String?
    let phrase: String
    let answers: [String]
}

/// A multiple-choice survey. Changing a survey's questions after roll-out breaks comparison with
/// older results; use a new id instead.
struct Survey: Identifiable {
    let id: SurveyId
    let questions: [SurveyQuestion]
    /// Single-question surveys go straight to the question, as in the Flutter app.
    var skipIntro = false
    /// Replaces the generic "help us improve the app" intro when set.
    var intro: String?
    var disclaimer: String?

    static var appRating: Survey {
        let answers = ["veryBad", "bad", "okay", "good", "veryGood"].map { N("survey.appRating.answers.\($0)") }
        return Survey(
            id: .appRating,
            questions: [SurveyQuestion(id: 0, phrase: N("survey.appRating.question"), answers: answers)],
            skipIntro: true
        )
    }

    static func messagingApps(username: String) -> Survey {
        let strings = L10n.main.survey.messagingApps.self
        let personal = strings.personalWhatsApp.self
        let business = strings.businessWhatsApp.self
        return Survey(
            id: .messagingApps,
            questions: [
                SurveyQuestion(id: 0, title: personal.title, phrase: personal.description,
                               answers: [personal.option1, personal.option2, personal.option3, personal.option4, personal.option5]),
                SurveyQuestion(id: 1, title: business.title, phrase: business.description(appName: Brand.appName),
                               answers: [business.option1(appName: Brand.appName), business.option2, business.option3,
                                         business.option4, business.option5]),
            ],
            intro: strings.intro(username: username),
            disclaimer: strings.disclaimer
        )
    }
}
