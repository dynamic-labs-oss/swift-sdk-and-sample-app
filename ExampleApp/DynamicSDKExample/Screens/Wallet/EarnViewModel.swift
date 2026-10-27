import Foundation
import DynamicSDKSwift

/// Raw-unit helpers for the Earn screen. Amounts from the API are integer
/// strings (they can exceed `Int.max`), so formatting works on the digits
/// rather than going through `Double`.
enum EarnUnits {
  /// Formats `raw` base units with `decimals` decimals, truncating (never
  /// rounding up) to `maxFractionDigits`. Returns `raw` unchanged when it is
  /// not an integer string.
  static func format(
    _ raw: String,
    decimals: Int,
    maxFractionDigits: Int = 6
  ) -> String {
    var digits = raw
    var sign = ""
    if digits.hasPrefix("-") {
      sign = "-"
      digits.removeFirst()
    }
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
      decimals >= 0
    else {
      return raw
    }

    if digits.count <= decimals {
      digits = String(repeating: "0", count: decimals - digits.count + 1) + digits
    }

    let split = digits.index(digits.endIndex, offsetBy: -decimals)
    let integerPart = String(digits[..<split])
    var fraction = String(digits[split...].prefix(maxFractionDigits))
    while fraction.hasSuffix("0") {
      fraction.removeLast()
    }

    if fraction.isEmpty {
      if isZero(raw) { return "0" }
      let isTruncatedToZero = integerPart.allSatisfy { $0 == "0" } && decimals > 0
      if isTruncatedToZero {
        return sign.isEmpty ? "<0.\(String(repeating: "0", count: maxFractionDigits - 1))1" : "~0"
      }
      return sign + integerPart
    }
    return "\(sign)\(integerPart).\(fraction)"
  }

  static func isZero(_ raw: String) -> Bool {
    let digits = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
    return !digits.isEmpty && digits.allSatisfy { $0 == "0" }
  }

  /// Whether `text` is a positive plain decimal ("1", "0.5") with no more
  /// fractional digits than the asset supports. Comma separators, signs and
  /// exponents are rejected.
  static func isValidAmount(_ text: String, decimals: Int) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = parts.first, !whole.isEmpty else {
      return false
    }
    let all = parts.joined()
    guard all.allSatisfy({ $0.isASCII && $0.isNumber }), !isZero(all) else {
      return false
    }
    if parts.count == 2 {
      return !parts[1].isEmpty && parts[1].count <= decimals
    }
    return true
  }
}

enum EarnTab: String, CaseIterable {
  case vaults = "Vaults"
  case positions = "My positions"
}

/// One vault the wallet holds a non-zero position in.
struct EarnPositionRow: Identifiable {
  let vault: EarnVaultDetails
  let position: EarnVaultPosition
  let earnings: EarnVaultEarnings?

  var id: String { vault.vaultId }
}

@MainActor
class EarnViewModel: ObservableObject {
  private let wallet: BaseWallet

  @Published var vaults: [EarnVaultSummary] = []
  @Published var selectedVault: EarnVaultDetails?
  @Published var position: EarnVaultPosition?
  @Published var rewards: [EarnVaultReward] = []
  @Published var performance: EarnVaultPerformance?
  @Published var earnings: EarnEarnings?
  @Published var sponsored = true
  @Published var tab: EarnTab = .vaults
  @Published var positions: [EarnPositionRow] = []
  @Published var isLoadingPositions = false
  @Published var positionsSkipped = 0
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

  /// The chain family a vault must be on to be usable with this wallet, as the
  /// API names it ("EVM", "SOL"). A Solana vault cannot take an EVM wallet's
  /// address or signature, and the reverse.
  var walletChainName: String {
    wallet.chain.uppercased()
  }

  /// Keeps only the vaults on the wallet's chain family.
  private func vaultsForWallet(_ all: [EarnVaultSummary]) -> [EarnVaultSummary] {
    all.filter { $0.chainName.rawValue == walletChainName }
  }

  var canSubmitAmount: Bool {
    guard let vault = selectedVault else { return false }
    let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    return EarnUnits.isValidAmount(trimmed, decimals: vault.assetDecimals)
  }

  /// Hint shown under the amount field while the typed amount is not usable.
  var amountHint: String? {
    guard let vault = selectedVault else { return nil }
    let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !canSubmitAmount else { return nil }
    return "Enter a positive number with up to \(vault.assetDecimals) decimals, using \".\" as the separator."
  }

  func loadVaults() {
    isLoadingVaults = true
    errorMessage = nil

    Task {
      do {
        let sdk = try requireSdk()
        vaults = vaultsForWallet(try await sdk.earn.getVaults())
      } catch {
        errorMessage = describe(error)
      }

      isLoadingVaults = false
    }
  }

  /// Looks up the wallet's position in every vault and keeps the non-zero
  /// ones. Vaults whose lookup fails (for example vaults on a chain the
  /// wallet's address does not exist on) are counted in `positionsSkipped`
  /// instead of failing the whole tab.
  func loadPositions() {
    isLoadingPositions = true
    errorMessage = nil
    positionsSkipped = 0

    Task {
      do {
        let sdk = try requireSdk()
        if vaults.isEmpty {
          vaults = vaultsForWallet(try await sdk.earn.getVaults())
        }

        let address = wallet.address
        let lookups = await withTaskGroup(
          of: (EarnVaultSummary, EarnVaultPosition?).self
        ) { group in
          for vault in vaults {
            group.addTask {
              let position = try? await sdk.earn.getVaultPosition(
                vaultId: vault.vaultId,
                ownerAddress: address
              )
              return (vault, position)
            }
          }

          var results: [(EarnVaultSummary, EarnVaultPosition?)] = []
          for await result in group {
            results.append(result)
          }
          return results
        }

        positionsSkipped = lookups.filter { $0.1 == nil }.count
        let held = lookups.compactMap { entry -> (EarnVaultSummary, EarnVaultPosition)? in
          guard let position = entry.1, !EarnUnits.isZero(position.assets) else {
            return nil
          }
          return (entry.0, position)
        }

        var earningsByVault: [String: EarnVaultEarnings] = [:]
        for chainId in Set(held.map { $0.0.chainId }) {
          guard
            let earnings = try? await sdk.earn.getEarnings(
              chainId: chainId,
              ownerAddress: address
            )
          else { continue }
          for entry in earnings.vaults {
            if let vaultId = entry.vaultId {
              earningsByVault[vaultId] = entry
            }
          }
        }

        var rows: [EarnPositionRow] = []
        for (summary, position) in held {
          guard
            let details = try? await sdk.earn.getVaultDetails(
              vaultId: summary.vaultId
            )
          else {
            positionsSkipped += 1
            continue
          }
          rows.append(
            EarnPositionRow(
              vault: details,
              position: position,
              earnings: earningsByVault[summary.vaultId]
            )
          )
        }

        positions = rows.sorted {
          ($0.vault.chainId, $0.vault.assetSymbol) < ($1.vault.chainId, $1.vault.assetSymbol)
        }
      } catch {
        errorMessage = describe(error)
      }

      isLoadingPositions = false
    }
  }

  func openVault(id vaultId: String) {
    guard let summary = vaults.first(where: { $0.vaultId == vaultId }) else {
      return
    }
    tab = .vaults
    selectVault(summary)
  }

  func selectVault(_ vault: EarnVaultSummary) {
    isLoadingVault = true
    errorMessage = nil
    transactionHash = nil
    stepMessage = nil
    position = nil
    rewards = []
    performance = nil
    earnings = nil
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
    performance = nil
    earnings = nil
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
          sponsored: sponsored,
          onStepChange: { [weak self] step in
            Task { @MainActor in
              self?.stepMessage = self?.label(for: step)
            }
          },
          onTransactionStepChange: { [weak self] step in
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
      performance = try await sdk.earn.getVaultPerformance(
        vaultId: vaultId,
        ownerAddress: wallet.address
      )

      // The earnings endpoint is Morpho-indexed and EVM-only (it rejects a
      // Solana owner address with a 400), so it is optional here rather than
      // failing the whole vault view.
      if let chainId = selectedVault?.chainId {
        earnings = try? await sdk.earn.getEarnings(
          chainId: chainId,
          ownerAddress: wallet.address
        )
      }
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

  private func label(for step: EarnTransactionStepChange) -> String {
    let position = "Transaction \(step.ordinal + 1) of \(step.total)"
    guard let label = step.label, !label.isEmpty else {
      return "\(position)…"
    }
    return "\(position): \(label)…"
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
      if earnError.nothingToClaim {
        return "Nothing to claim: no reward campaign covers this vault, or everything is already claimed."
      }
      return earnError.message
    }

    if let decodingError = error as? DecodingError {
      return "Decoding failed: \(describe(decodingError))"
    }

    return error.localizedDescription
  }

  private func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
      let keys = context.codingPath.map(\.stringValue).joined(separator: ".")
      return "\(keys.isEmpty ? "<root>" : keys): \(context.debugDescription)"
    }

    switch error {
    case .typeMismatch(let type, let context):
      return "type mismatch (\(type)) at \(path(context))"
    case .valueNotFound(let type, let context):
      return "value not found (\(type)) at \(path(context))"
    case .keyNotFound(let key, let context):
      return "missing key \(key.stringValue) at \(path(context))"
    case .dataCorrupted(let context):
      return "data corrupted at \(path(context))"
    @unknown default:
      return String(describing: error)
    }
  }
}
