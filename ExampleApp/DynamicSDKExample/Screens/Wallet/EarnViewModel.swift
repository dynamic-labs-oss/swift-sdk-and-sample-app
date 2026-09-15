import Foundation
import DynamicSDKSwift

@MainActor
class EarnViewModel: ObservableObject {
  private let wallet: BaseWallet

  @Published var vaults: [EarnVaultSummary] = []
  @Published var selectedVault: EarnVaultDetails?
  @Published var position: EarnVaultPosition?
  @Published var rewards: [EarnVaultReward] = []
  @Published var amount: String = ""
  @Published var isLoadingVaults = false
  @Published var isLoadingVault = false
  @Published var isExecuting = false
  @Published var errorMessage: String?
  @Published var stepMessage: String?
  @Published var transactionHash: String?

  init(wallet: BaseWallet) {
    self.wallet = wallet
  }

  var canSubmitAmount: Bool {
    let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
  }

  func loadVaults() {
    isLoadingVaults = true
    errorMessage = nil

    Task {
      do {
        let sdk = try requireSdk()
        vaults = try await sdk.earn.getVaults()
      } catch {
        errorMessage = describe(error)
      }

      isLoadingVaults = false
    }
  }

  func selectVault(_ vault: EarnVaultSummary) {
    isLoadingVault = true
    errorMessage = nil
    transactionHash = nil
    stepMessage = nil
    position = nil
    rewards = []
    amount = ""

    Task {
      do {
        let sdk = try requireSdk()
        selectedVault = try await sdk.earn.getVaultDetails(
          vaultId: vault.vaultId
        )
        await loadPositionAndRewards(vaultId: vault.vaultId, sdk: sdk)
      } catch {
        errorMessage = describe(error)
      }

      isLoadingVault = false
    }
  }

  func clearSelection() {
    selectedVault = nil
    position = nil
    rewards = []
    amount = ""
    errorMessage = nil
    stepMessage = nil
    transactionHash = nil
  }

  func deposit() {
    guard let vault = selectedVault else { return }

    run { sdk in
      try await sdk.earn.deposit(
        vaultId: vault.vaultId,
        ownerAddress: self.wallet.address,
        amount: self.amount.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
  }

  func withdraw() {
    guard let vault = selectedVault else { return }

    run { sdk in
      try await sdk.earn.withdraw(
        vaultId: vault.vaultId,
        ownerAddress: self.wallet.address,
        amount: self.amount.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
  }

  func claim() {
    guard let vault = selectedVault else { return }

    run { sdk in
      try await sdk.earn.claim(
        vaultId: vault.vaultId,
        ownerAddress: self.wallet.address
      )
    }
  }

  /// Requests a payload with `requestPayload`, then signs and broadcasts it,
  /// reporting each step so the UI can show what the wallet is doing.
  private func run(
    requestPayload: @escaping (DynamicSDK) async throws -> EarnVaultActionResponse
  ) {
    isExecuting = true
    errorMessage = nil
    transactionHash = nil
    stepMessage = "Preparing the transaction…"

    Task {
      do {
        let sdk = try requireSdk()
        let action = try await requestPayload(sdk)

        let hash = try await sdk.earn.execute(
          payload: action.signingPayload,
          wallet: wallet,
          onStepChange: { [weak self] step in
            Task { @MainActor in
              self?.stepMessage = self?.label(for: step)
            }
          }
        )

        transactionHash = hash
        stepMessage = nil

        if let vaultId = selectedVault?.vaultId {
          await loadPositionAndRewards(vaultId: vaultId, sdk: sdk)
        }
      } catch {
        errorMessage = describe(error)
        stepMessage = nil
      }

      isExecuting = false
    }
  }

  private func loadPositionAndRewards(vaultId: String, sdk: DynamicSDK) async {
    do {
      position = try await sdk.earn.getVaultPosition(
        vaultId: vaultId,
        ownerAddress: wallet.address
      )
      rewards = try await sdk.earn.getVaultRewards(
        vaultId: vaultId,
        ownerAddress: wallet.address
      )
    } catch {
      errorMessage = describe(error)
    }
  }

  private func label(for step: EarnExecutionStep) -> String {
    switch step {
    case .approval:
      return "Approving the vault to move your tokens…"
    case .transaction:
      return "Sending the vault transaction…"
    }
  }

  private func requireSdk() throws -> DynamicSDK {
    guard let sdk = DynamicSDK.shared else {
      throw NSError(
        domain: "EarnViewModel",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "SDK not initialized"]
      )
    }

    return sdk
  }

  /// Reads the message an Earn failure carries directly, so the reason reaches
  /// the user once rather than wrapped in another sentence.
  private func describe(_ error: Error) -> String {
    if let earnError = error as? EarnError {
      return earnError.message
    }

    return error.localizedDescription
  }
}
