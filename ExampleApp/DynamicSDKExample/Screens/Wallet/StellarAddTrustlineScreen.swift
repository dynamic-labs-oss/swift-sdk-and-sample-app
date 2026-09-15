import SwiftUI
import DynamicSDKSwift

struct StellarAddTrustlineScreen: View {
  let wallet: BaseWallet

  @State private var assetCode: String = ""
  @State private var assetIssuer: String = ""
  @State private var limit: String = ""
  @State private var hash: String?
  @State private var errorMessage: String?
  @State private var isLoading: Bool = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        InfoCard(
          title: "Add Trustline",
          content: "Add a trustline so this account can hold a non-native Stellar asset.",
          copyable: false
        )

        TextFieldWithLabel(
          label: "Asset Code",
          placeholder: "USDC",
          text: $assetCode
        )

        TextFieldWithLabel(
          label: "Asset Issuer",
          placeholder: "G...",
          text: $assetIssuer
        )

        TextFieldWithLabel(
          label: "Limit (optional)",
          placeholder: "1000000",
          text: $limit,
          keyboardType: .decimalPad
        )

        PrimaryButton(
          title: isLoading ? "Adding..." : "Add Trustline",
          action: addTrustline,
          isLoading: isLoading,
          isDisabled: !isFormValid
        )

        if let error = errorMessage {
          ErrorMessageView(message: error)
        }

        if let txHash = hash {
          InfoCard(title: "Hash", content: txHash)
          SuccessMessageView(message: "Trustline added successfully!")
        }
      }
      .padding()
    }
    .navigationTitle("Add Trustline")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var isFormValid: Bool {
    let trimmedCode = assetCode.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedIssuer = assetIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedCode.isEmpty && !trimmedIssuer.isEmpty
  }

  private func addTrustline() {
    guard let walletId = wallet.id else { return }
    isLoading = true
    errorMessage = nil
    hash = nil

    let trimmedLimit = limit.trimmingCharacters(in: .whitespacesAndNewlines)

    Task {
      do {
        let txHash = try await DynamicSDK.instance().stellar.addTrustline(
          walletId: walletId,
          assetCode: assetCode.trimmingCharacters(in: .whitespacesAndNewlines),
          assetIssuer: assetIssuer.trimmingCharacters(in: .whitespacesAndNewlines),
          limit: trimmedLimit.isEmpty ? nil : trimmedLimit
        )

        await MainActor.run {
          hash = txHash
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }
}
