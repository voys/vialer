import SwiftUI
import StoreKit

/// Intro → questions → thank you, mirroring the Flutter survey dialog. A positive app rating also
/// asks for an App Store review.
struct SurveyView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    let survey: Survey

    private enum Stage: Equatable { case intro, question(Int), thanks }

    @State private var stage: Stage
    @State private var answers: [Int: Int] = [:]
    @State private var dontAskAgain = false

    init(survey: Survey) {
        self.survey = survey
        _stage = State(initialValue: survey.skipIntro ? .question(0) : .intro)
    }

    private var strings: L10n.main.survey.Type { L10n.main.survey.self }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch stage {
                    case .intro: intro
                    case .question(let index): question(at: index)
                    case .thanks: thanks
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                if stage != .thanks {
                    ToolbarItem(placement: .cancellationAction) { Button(strings.button.skip) { dismiss() } }
                }
            }
        }
        .presentationDetents(survey.skipIntro ? [.fraction(0.75), .large] : [.large])
        .interactiveDismissDisabled(stage != .thanks && !survey.skipIntro)
    }

    // MARK: Stages

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity)
            Text(strings.helpUs.title).font(.title2.bold()).frame(maxWidth: .infinity)
            Text(survey.intro ?? strings.helpUs.content(questionCount: survey.questions.count))
            if let disclaimer = survey.disclaimer {
                Text(disclaimer).font(.footnote).foregroundStyle(Theme.infoText)
            }
            Toggle(strings.helpUs.dontAskAgain, isOn: $dontAskAgain).font(.subheadline)
            Button(survey.intro == nil ? L10n.generic.button.yes : strings.button.participate) {
                container.feedback.setDontShowSurveysAgain(dontAskAgain)
                stage = .question(0)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(survey.intro == nil ? L10n.generic.button.noThanks : strings.button.notInterested) {
                container.feedback.setDontShowSurveysAgain(dontAskAgain)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
    }

    @ViewBuilder
    private func question(at index: Int) -> some View {
        let question = survey.questions[index]
        let isLast = index == survey.questions.count - 1
        if survey.questions.count > 1 {
            Text(strings.question.title(current: index + 1, total: survey.questions.count))
                .font(.subheadline.bold())
                .foregroundStyle(Theme.primary)
        }
        if let title = question.title { Text(title).font(.headline) }
        Text(question.phrase).font(survey.questions.count > 1 ? .body : .title2.bold())
        ForEach(Array(question.answers.enumerated()), id: \.offset) { offset, answer in
            Button {
                answers[question.id] = answers[question.id] == offset ? nil : offset
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: answers[question.id] == offset ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(Theme.primary)
                    Text(answer).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
        if survey.skipIntro {
            Toggle(strings.helpUs.dontAskAgain, isOn: $dontAskAgain).font(.subheadline)
        }
        HStack {
            if survey.questions.count > 1 {
                Button(L10n.generic.button.previous) { stage = .question(index - 1) }
                    .disabled(index == 0)
            }
            Spacer()
            Button(isLast ? strings.button.finish : L10n.generic.button.next) {
                if isLast { finish() } else { stage = .question(index + 1) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(answers[question.id] == nil)
        }
        .padding(.top, 8)
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.thumbsup.fill").font(.system(size: 48)).foregroundStyle(Theme.primary)
            Text(survey.id == .appRating ? strings.thankYou.title : strings.finished.title).font(.title2.bold())
            Text(survey.id == .appRating ? strings.thankYou.content : strings.finished.description)
                .foregroundStyle(Theme.infoText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }

    private func finish() {
        if survey.skipIntro { container.feedback.setDontShowSurveysAgain(dontAskAgain) }
        container.feedback.submitSurvey(survey, answers: answers)
        if survey.id == .appRating, let answer = answers[0], answer + 1 > 3 { requestReview() }
        stage = .thanks
    }
}
