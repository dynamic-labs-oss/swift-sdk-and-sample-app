import SwiftUI
import DynamicSDKSwift

struct StellarSendBalanceScreen: View {
  let wallet: BaseWallet

  @State private var recipientAddress: String = ""
  @State private var amount: String = "0.01"
  @State private var tokenAddress: String = ""
  @State private var hash: String?
  @State private var errorMessage: String?
  @State private var isLoading: Bool = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        InfoCard(
          title: "Send Balance",
          content: "Send XLM to a recipient address. Provide an asset in CODE:ISSUER form to send a non-native asset.",
          copyable: false
        )

        TextFieldWithLabel(
          label: "Recipient Address",
          placeholder: "G...",
          text: $recipientAddress
        )

        TextFieldWithLabel(
          label: "Amount",
          placeholder: "0.01",
          text: $amount,
          keyboardType: .decimalPad
        )

        TextFieldWithLabel(
          label: "Asset (optional, CODE:ISSUER)",
          placeholder: "USDC:GA5Z...",
          text: $tokenAddress
        )

        PrimaryButton(
          title: isLoading ? "Sending..." : "Send",
          action: sendBalance,
          isLoading: isLoading,
          isDisabled: !isFormValid
        )

        if let error = errorMessage {
          ErrorMessageView(message: error)
        }

        if let txHash = hash {
          InfoCard(title: "Hash", content: txHash)
          SuccessMessageView(message: "Balance sent successfully!")
        }
      }
      .padding()
    }
    .navigationTitle("Send Balance")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var isFormValid: Bool {
    let trimmedAddress = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let amountValue = Double(amount)
    return !trimmedAddress.isEmpty && amountValue != nil && amountValue! > 0
  }

  private func sendBalance() {
    guard let walletId = wallet.id else { return }
    isLoading = true
    errorMessage = nil
    hash = nil

    let trimmedToken = tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)

    Task {
      do {
        let txHash = try await DynamicSDK.instance().stellar.sendBalance(
          walletId: walletId,
          toAddress: recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines),
          amount: amount.trimmingCharacters(in: .whitespacesAndNewlines),
          tokenAddress: trimmedToken.isEmpty ? nil : trimmedToken
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
