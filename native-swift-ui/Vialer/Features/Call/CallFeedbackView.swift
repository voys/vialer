import SwiftUI

/// Star rating → (problem → audio problems) → thank you. Mirrors the Flutter CallFeedback stages.
struct CallFeedbackView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let rated: CallToRate

    private enum Stage { case rate, problem, audioProblems, thanks }
    private static let positiveThreshold = 4

    @State private var stage: Stage = .rate
    @State private var rating = 0
    @State private var problem: CallProblem?
    @State private var audioProblems: Set<CallAudioProblem> = []

    private var strings: L10n.main.call.feedback.Type { L10n.main.call.feedback.self }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch stage {
                case .rate: rateStage
                case .problem: problemStage
                case .audioProblems: audioStage
                case .thanks: thanksStage
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage != .thanks {
                    ToolbarItem(placement: .cancellationAction) { Button(strings.written.dismiss) { dismiss() } }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var rateStage: some View {
        VStack(spacing: 20) {
            Text(strings.rating.title).font(.title2.bold()).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        if star >= Self.positiveThreshold { finish() } else { stage = .problem }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.primary)
                    }
                    .accessibilityLabel(starLabel(star))
                }
            }
            HStack {
                Text(strings.rating.lowerLabel)
                Spacer()
                Text(strings.rating.upperLabel)
            }
            .font(.caption)
            .foregroundStyle(Theme.infoText)
            .padding(.horizontal, 8)
        }
    }

    private func starLabel(_ star: Int) -> String {
        let s = strings.rating.semantics.self
        switch star {
        case 1: return s.firstStar
        case 2: return s.secondStar
        case 3: return s.thirdStar
        case 4: return s.fourthStar
        default: return s.fifthStar
        }
    }

    private var problemStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.problem.title).font(.title2.bold())
            ForEach(CallProblem.allCases) { option in
                Button {
                    problem = option
                    if option == .audioProblem { stage = .audioProblems } else { finish() }
                } label: {
                    HStack {
                        Text(option.title).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.grey4)
                    }
                    .padding(12)
                    .background(Theme.grey7)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius))
                }
            }
        }
    }

    private var audioStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.audioProblems.title).font(.title2.bold())
            ForEach(CallAudioProblem.allCases) { option in
                Button {
                    if audioProblems.contains(option) { audioProblems.remove(option) } else { audioProblems.insert(option) }
                } label: {
                    HStack {
                        Image(systemName: audioProblems.contains(option) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(Theme.primary)
                        Text(option.title).foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
            Button(strings.audioProblems.done) { finish() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(audioProblems.isEmpty)
        }
    }

    private var thanksStage: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.thumbsup.fill").font(.system(size: 48)).foregroundStyle(Theme.primary)
            Text(strings.written.title).font(.title2.bold())
            Text(N("call.feedback.thanks.message")).foregroundStyle(Theme.infoText)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    private func finish() {
        container.feedback.submitCallRating(rated, rating: rating, problem: problem, audioProblems: Array(audioProblems))
        stage = .thanks
    }
}
