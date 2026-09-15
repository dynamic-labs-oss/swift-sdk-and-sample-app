import SwiftUI
import DynamicSDKSwift

struct StellarSignTransactionScreen: View {
  let wallet: BaseWallet

  @State private var transactionXdr: String = ""
  @State private var signedXdr: String?
  @State private var errorMessage: String?
  @State private var isLoading: Bool = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        InfoCard(
          title: "Stellar Sign Transaction",
          content: "Sign a base64-encoded Stellar transaction envelope XDR.",
          copyable: false
        )

        TextFieldWithLabel(
          label: "Transaction XDR",
          placeholder: "AAAA...",
          text: $transactionXdr
        )

        PrimaryButton(
          title: isLoading ? "Signing..." : "Sign Transaction",
          action: signTransaction,
          isLoading: isLoading,
          isDisabled: transactionXdr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        if let error = errorMessage {
          ErrorMessageView(message: error)
        }

        if let signed = signedXdr {
          InfoCard(
            title: "Signed Transaction XDR",
            content: signed
          )
          SuccessMessageView(message: "Transaction signed successfully!")
        }
      }
      .padding()
    }
    .navigationTitle("Stellar Sign Transaction")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func signTransaction() {
    guard let walletId = wallet.id else { return }
    isLoading = true
    errorMessage = nil
    signedXdr = nil

    Task {
      do {
        let result = try await DynamicSDK.instance().stellar.signTransaction(
          walletId: walletId,
          transactionXdr: transactionXdr.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        await MainActor.run {
          signedXdr = result
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
