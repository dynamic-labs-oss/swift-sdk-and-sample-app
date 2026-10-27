import SwiftUI
import DynamicSDKSwift

struct EarnScreen: View {
  let wallet: BaseWallet
  @StateObject private var vm: EarnViewModel

  init(wallet: BaseWallet) {
    self.wallet = wallet
    self._vm = StateObject(wrappedValue: EarnViewModel(wallet: wallet))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let vault = vm.selectedVault {
          vaultDetail(vault)
        } else {
          Picker("View", selection: $vm.tab) {
            ForEach(EarnTab.allCases, id: \.self) { tab in
              Text(tab.rawValue).tag(tab)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)

          switch vm.tab {
          case .vaults:
            vaultList
          case .positions:
            positionsList
          }
        }

        if let step = vm.stepMessage {
          EarnStatusCard(icon: "clock.fill", message: step, color: .blue)
            .padding(.horizontal)
        }

        if let hash = vm.transactionHash {
          EarnStatusCard(
            icon: "checkmark.circle.fill",
            message: "Transaction: \(hash)",
            color: .green
          )
          .padding(.horizontal)
        }

        if let error = vm.errorMessage {
          EarnStatusCard(
            icon: "exclamationmark.circle.fill",
            message: error,
            color: .red
          )
          .padding(.horizontal)
        }

        Spacer(minLength: 20)
      }
      .padding(.vertical)
    }
    .navigationTitle("Earn")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if vm.vaults.isEmpty {
        vm.loadVaults()
      }
    }
    .onChange(of: vm.tab) { tab in
      if tab == .positions {
        vm.loadPositions()
      }
    }
  }

  private var positionsList: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your positions")
        .font(.headline)
        .padding(.horizontal)

      if vm.isLoadingPositions {
        ProgressView()
          .frame(maxWidth: .infinity)
      }

      if vm.positions.isEmpty && !vm.isLoadingPositions {
        Text("You have no positions in any vault.")
          .foregroundColor(.secondary)
          .padding(.horizontal)
      }

      ForEach(vm.positions) { row in
        Button(action: { vm.openVault(id: row.vault.vaultId) }) {
          PositionRow(row: row)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
      }

      if vm.positionsSkipped > 0 {
        Text("\(vm.positionsSkipped) vault(s) could not be checked for this wallet.")
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.horizontal)
      }
    }
  }

  private var vaultList: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(vm.walletChainName) vaults")
        .font(.headline)
        .padding(.horizontal)

      if vm.isLoadingVaults {
        ProgressView()
          .frame(maxWidth: .infinity)
      }

      if vm.vaults.isEmpty && !vm.isLoadingVaults {
        Text("No \(vm.walletChainName) vaults are available for this environment.")
          .foregroundColor(.secondary)
          .padding(.horizontal)
      }

      ForEach(vm.vaults, id: \.vaultId) { vault in
        Button(action: { vm.selectVault(vault) }) {
          VaultRow(vault: vault)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
      }
    }
  }

  private func vaultDetail(_ vault: EarnVaultDetails) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Button(action: { vm.clearSelection() }) {
        HStack {
          Image(systemName: "chevron.left")
          Text("All vaults")
        }
      }
      .padding(.horizontal)

      VStack(alignment: .leading, spacing: 6) {
        Text("\(vault.assetSymbol) · \(vault.curator)")
          .font(.title3)
          .fontWeight(.bold)

        Text("Chain ID: \(vault.chainId)")
          .font(.caption)
          .foregroundColor(.secondary)

        Text("Vault: \(vault.contractAddress)")
          .font(.caption)
          .monospaced()
          .foregroundColor(.secondary)

        if let netApy = vault.netApy {
          Text("Net APY: \(netApy * 100, specifier: "%.2f")%")
            .font(.subheadline)
        }
      }
      .padding(.horizontal)

      if vm.isLoadingVault {
        ProgressView()
          .frame(maxWidth: .infinity)
      }

      if let position = vm.position {
        VStack(alignment: .leading, spacing: 4) {
          Text("Your position")
            .font(.headline)
          Text("Shares: \(position.shares) (raw)")
            .font(.caption)
            .monospaced()
          Text("Assets: \(EarnUnits.format(position.assets, decimals: vault.assetDecimals)) \(vault.assetSymbol)")
            .font(.caption)
            .monospaced()
        }
        .padding(.horizontal)
      }

      if !vm.rewards.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Rewards")
            .font(.headline)

          ForEach(vm.rewards, id: \.tokenAddress) { reward in
            Text("\(EarnUnits.format(reward.accrued, decimals: reward.tokenDecimals)) \(reward.tokenSymbol)")
              .font(.caption)
              .monospaced()
          }
        }
        .padding(.horizontal)
      }

      if let performance = vm.performance {
        VStack(alignment: .leading, spacing: 4) {
          Text("Performance")
            .font(.headline)
          Text("Net earnings: \(EarnUnits.format(performance.netEarningsAssets, decimals: vault.assetDecimals)) \(vault.assetSymbol)")
            .font(.caption)
            .monospaced()
          if let returnOnCapital = performance.returnOnCapital {
            Text("Return on capital: \(returnOnCapital * 100, specifier: "%.2f")%")
              .font(.caption)
              .monospaced()
          }
        }
        .padding(.horizontal)
      }

      if let earnings = vm.earnings {
        VStack(alignment: .leading, spacing: 4) {
          Text("Earnings across vaults")
            .font(.headline)
          Text("Assets: \(earnings.totalAssetsUsd, specifier: "%.2f") USD")
            .font(.caption)
            .monospaced()
          Text("P&L: \(earnings.totalPnlUsd, specifier: "%.2f") USD")
            .font(.caption)
            .monospaced()
        }
        .padding(.horizontal)
      }

      Toggle("Gas sponsored", isOn: $vm.sponsored)
        .padding(.horizontal)

      VStack(alignment: .leading, spacing: 8) {
        Text("Amount in \(vault.assetSymbol)")
          .font(.subheadline)
          .fontWeight(.medium)

        TextField("e.g. 0.01", text: $vm.amount)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .keyboardType(.decimalPad)

        if let hint = vm.amountHint {
          Text(hint)
            .font(.caption)
            .foregroundColor(.red)
        }
      }
      .padding(.horizontal)

      VStack(spacing: 8) {
        EarnActionButton(
          title: "Deposit",
          isEnabled: vm.canSubmitAmount && !vm.isExecuting,
          action: { vm.deposit() }
        )

        EarnActionButton(
          title: "Withdraw",
          isEnabled: vm.canSubmitAmount && !vm.isExecuting,
          action: { vm.withdraw() }
        )

        EarnActionButton(
          title: "Claim rewards",
          isEnabled: !vm.isExecuting,
          action: { vm.claim() }
        )
      }
      .padding(.horizontal)
    }
  }
}

struct VaultRow: View {
  let vault: EarnVaultSummary

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(vault.assetSymbol) · \(vault.curator)")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        Text("Chain ID: \(vault.chainId)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if let netApy = vault.netApy {
        Text("\(netApy * 100, specifier: "%.2f")%")
          .font(.subheadline)
          .foregroundColor(.blue)
      }

      Image(systemName: "chevron.right")
        .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

struct PositionRow: View {
  let row: EarnPositionRow

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(row.vault.assetSymbol) · \(row.vault.curator)")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        Text("Chain ID: \(row.vault.chainId)")
          .font(.caption)
          .foregroundColor(.secondary)

        Text("\(EarnUnits.format(row.position.assets, decimals: row.vault.assetDecimals)) \(row.vault.assetSymbol)")
          .font(.caption)
          .monospaced()
          .foregroundColor(.primary)

        if let earnings = row.earnings {
          if let pnlUsd = earnings.pnlUsd {
            Text("P&L: \(pnlUsd, specifier: "%.2f") USD")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          if let roe = earnings.roe {
            Text("Return: \(roe * 100, specifier: "%.2f")%")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        if let assetsUsd = row.earnings?.assetsUsd {
          Text("$\(assetsUsd, specifier: "%.2f")")
            .font(.subheadline)
            .foregroundColor(.blue)
        }
        if let netApy = row.vault.netApy {
          Text("\(netApy * 100, specifier: "%.2f")% APY")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Image(systemName: "chevron.right")
        .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

struct EarnActionButton: View {
  let title: String
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .frame(maxWidth: .infinity)
        .padding()
        .background(isEnabled ? Color.blue : Color.blue.opacity(0.4))
        .foregroundColor(.white)
        .cornerRadius(12)
    }
    .disabled(!isEnabled)
  }
}

struct EarnStatusCard: View {
  let icon: String
  let message: String
  let color: Color

  var body: some View {
    HStack(alignment: .top) {
      Image(systemName: icon)
        .foregroundColor(color)

      Text(message)
        .font(.caption)
        .foregroundColor(color)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.1))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(color.opacity(0.3), lineWidth: 1)
    )
  }
}
