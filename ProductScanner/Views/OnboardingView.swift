import SwiftUI

/// First-launch screen: asks the user which allergens to watch for before they
/// start scanning. The choice is persisted (see `AllergyProfileStore`), so this
/// screen only ever shows once — later changes go through `AllergyProfileView`.
struct OnboardingView: View {
    @Binding var selected: Set<Allergen>
    var onFinish: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Welcome to SafeBite")
                        .font(.largeTitle.bold())
                    Text("Pick the allergens you want to watch for. We'll flag them every time you scan a product — you can change this anytime from your profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 32)
                .padding(.bottom, 20)

                List {
                    ForEach(Allergen.allCases) { allergen in
                        Toggle(isOn: Binding(
                            get: { selected.contains(allergen) },
                            set: { isOn in
                                if isOn { selected.insert(allergen) } else { selected.remove(allergen) }
                            }
                        )) {
                            Label {
                                Text(allergen.displayName)
                            } icon: {
                                Text(allergen.icon)
                            }
                        }
                        .tint(.red)
                    }
                }
                .listStyle(.insetGrouped)

                Button(action: onFinish) {
                    Text(selected.isEmpty ? "Skip for now" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                Text("SafeBite helps you spot likely allergens but can't guarantee a product is safe — database entries and label scans can be incomplete or wrong. Always check the physical packaging yourself.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }
        }
    }
}

#Preview {
    OnboardingView(selected: .constant([.milk, .gluten]), onFinish: {})
}
