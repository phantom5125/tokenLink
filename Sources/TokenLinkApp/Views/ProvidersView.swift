import SwiftUI
import TokenLinkCore
import TokenLinkProviders

struct ProvidersView: View {
  @Bindable var model: AppModel
  @State private var replacementKeys: [UUID: String] = [:]
  @State private var keyHints: [UUID: String] = [:]
  @State private var newAccountLabels: [ProviderID: String] = [:]
  @State private var newAccountKeys: [ProviderID: String] = [:]
  @State private var addAccountExpanded: Set<ProviderID> = []
  @State private var codexPath = ""
  @State private var message: String?
  @State private var showingClaudeAuthorization = false
  @State private var showingLegacyMigration = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text(model.text(.providersTitle))
            .font(.largeTitle.bold())
          Text(model.text(.providersSubtitle))
            .foregroundStyle(.secondary)
        }

        if model.configurationRestartRequired {
          Label(
            model.text(.providersRestartBanner),
            systemImage: "arrow.clockwise.circle"
          )
          .font(.subheadline)
          .foregroundStyle(.orange)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }

        if !model.configuration.legacyKeychainMigrationCompleted {
          legacyCredentialMigrationBanner
        }

        ForEach(ProviderRegistry.quotaProviderIDs, id: \.self) { provider in
          providerSection(provider)
        }

        VStack(alignment: .leading, spacing: 5) {
          Text(model.text(.providersCostTitle))
            .font(.title2.bold())
          Text(model.text(.providersCostSubtitle))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        ForEach(ProviderRegistry.authoritativeCostProviderIDs, id: \.self) { provider in
          costProviderSection(provider)
        }

        if let message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(28)
      .frame(maxWidth: 820, alignment: .leading)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .navigationTitle(model.text(.providersTitle))
    .task {
      codexPath = model.configuration.codexPath ?? ""
      await model.refreshCredentialStates()
      await loadKeyHints()
    }
    .alert(
      model.text(.providersClaudeAuthorizationTitle),
      isPresented: $showingClaudeAuthorization
    ) {
      Button(model.text(.actionCancel), role: .cancel) {}
      Button(model.text(.actionContinue)) { authorizeClaudeCredential() }
    } message: {
      Text(model.text(.providersClaudeAuthorizationExplanation))
    }
    .alert(
      model.text(.providersLegacyMigrationAuthorizationTitle),
      isPresented: $showingLegacyMigration
    ) {
      Button(model.text(.actionCancel), role: .cancel) {}
      Button(model.text(.actionContinue)) { migrateLegacyCredentials() }
    } message: {
      Text(model.text(.providersLegacyMigrationAuthorizationExplanation))
    }
  }

  private var legacyCredentialMigrationBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(
        model.text(.providersLegacyMigrationTitle),
        systemImage: "key.horizontal.fill"
      )
      .font(.headline)
      Text(model.text(.providersLegacyMigrationNote))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack {
        Button(model.text(.providersLegacyMigrationAction)) {
          showingLegacyMigration = true
        }
        .disabled(model.isMigratingLegacyCredentials)
        Button(model.text(.providersLegacyMigrationDismiss)) {
          do {
            try model.dismissLegacyCredentialMigration()
          } catch {
            message = error.localizedDescription
          }
        }
        .buttonStyle(.link)
        .disabled(model.isMigratingLegacyCredentials)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private func costProviderSection(_ provider: ProviderID) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        ProviderMark(provider: provider, size: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(AppModel.displayName(for: provider))
            .font(.headline)
          Text(model.text(.providersCostBadge))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Toggle(
          model.text(.providersEnabled),
          isOn: Binding(
            get: { model.configuration.enabledProviders.contains(provider) },
            set: { enabled in
              do { try model.setProvider(provider, enabled: enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }

      Divider()
      let group = model.costAccountGroups.first { $0.provider == provider }
      ForEach(group?.accounts ?? []) { account in
        accountRow(account)
        if account.id != group?.accounts.last?.id {
          Divider()
        }
      }
      costCredentialHelp(provider)
      addAccountSection(provider)
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  @ViewBuilder
  private func costCredentialHelp(_ provider: ProviderID) -> some View {
    switch provider {
    case .openrouter:
      Text(model.text(.providersOpenRouterCostNote))
        .font(.caption)
        .foregroundStyle(.secondary)
      Link(
        model.text(.providersGetKey),
        destination: URL(string: "https://openrouter.ai/settings/keys")!
      )
      .font(.caption)
    case .deepseek:
      Text(model.text(.providersDeepSeekCostNote))
        .font(.caption)
        .foregroundStyle(.secondary)
      Link(
        model.text(.providersGetKey),
        destination: URL(string: "https://platform.deepseek.com/api_keys")!
      )
      .font(.caption)
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private func providerSection(_ provider: ProviderID) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        ProviderMark(provider: provider, size: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(AppModel.displayName(for: provider))
            .font(.headline)
          Text(model.text(subtitleKey(provider)))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Toggle(
          model.text(.providersEnabled),
          isOn: Binding(
            get: { model.configuration.enabledProviders.contains(provider) },
            set: { enabled in
              do { try model.setProvider(provider, enabled: enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }

      Divider()

      if provider == .codex {
        codexSection
      } else if provider == .claude {
        claudeSection
      } else {
        let group = model.accountGroups.first { $0.provider == provider }
        ForEach(group?.accounts ?? []) { account in
          accountRow(account)
          if account.id != group?.accounts.last?.id {
            Divider()
          }
        }
        regionPicker(provider)
        keyHelpLink(provider)
        if provider == .kimi {
          Text(model.text(.providersKimiCLINote))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        addAccountSection(provider)
      }
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private var codexSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledContent(model.text(.providersCodexExecutable)) {
        HStack {
          TextField(model.text(.providersCodexPathPlaceholder), text: $codexPath)
            .textFieldStyle(.roundedBorder)
          Button(model.text(.actionSave)) {
            do {
              try model.setCodexPath(codexPath)
              message = model.text(.providersKeySaved)
                .replacingOccurrences(of: "%@", with: "Codex path")
            } catch { message = error.localizedDescription }
          }
        }
        .frame(maxWidth: 460)
      }
      Text(model.text(.providersCodexNote))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  /// Claude is read-only: the credential comes from the Claude Code CLI's
  /// Keychain item or `CLAUDE_CODE_OAUTH_TOKEN`, never from a pasted key.
  private var claudeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let account = model.accountGroups.first(where: { $0.provider == .claude })?
        .accounts.first
      {
        LabeledContent(model.text(.providersCredential)) {
          credentialStatus(account)
        }
      }
      if !model.configuration.enabledProviders.contains(.claude) {
        Label(model.text(.providersClaudeEnableFirst), systemImage: "power")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else if model.configuration.claudeCredentialAccessAuthorized {
        HStack(spacing: 10) {
          Label(
            model.text(.providersClaudeAuthorized),
            systemImage: "checkmark.shield.fill"
          )
          .foregroundStyle(.green)
          Spacer()
          Button(model.text(.providersClaudeStopUsing), role: .destructive) {
            stopUsingClaudeCredential()
          }
          .disabled(model.isAuthorizingClaudeCredential)
        }
        .font(.subheadline)
      } else {
        Button {
          showingClaudeAuthorization = true
        } label: {
          Label(model.text(.providersClaudeAuthorize), systemImage: "key.fill")
        }
        .disabled(model.isAuthorizingClaudeCredential)
      }
      Text(model.text(.providersClaudeNote))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func accountRow(_ account: AccountRow) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(account.label)
          .font(.subheadline.weight(.semibold))
        if account.isDefault {
          Text(model.text(.providersDefaultBadge))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
        }
        Spacer()
        credentialStatus(account)
        if !account.isDefault {
          Button(model.text(.providersDeleteAccount), role: .destructive) {
            removeAccount(account)
          }
          .font(.caption)
        }
      }

      LabeledContent(model.text(.providersReplaceKey)) {
        HStack {
          SecureField(
            model.text(.providersKeyPlaceholder),
            text: Binding(
              get: { replacementKeys[account.id, default: ""] },
              set: { replacementKeys[account.id] = $0 })
          )
          .textFieldStyle(.roundedBorder)
          Button(model.text(.actionSave)) { saveKey(account) }
            .disabled(replacementKeys[account.id, default: ""].isEmpty)
          Button(model.text(.actionDelete), role: .destructive) { deleteKey(account) }
        }
        .frame(maxWidth: 460)
      }
    }
  }

  @ViewBuilder
  private func credentialStatus(_ account: AccountRow) -> some View {
    let configured = model.credentialConfiguredByAccount[account.id] == true
    HStack(spacing: 6) {
      Image(systemName: configured ? "checkmark.circle.fill" : "circle.dashed")
        .foregroundStyle(configured ? .green : .secondary)
      Text(
        configured
          ? model.text(.providersConfigured) : model.text(.providersNotConfigured)
      )
      .foregroundStyle(.secondary)
      if configured {
        if let hint = keyHints[account.id] {
          Text(hint)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        if let source = model.credentialSourceByAccount[account.id] {
          Text("· \(sourceText(source))")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .font(.subheadline)
  }

  @ViewBuilder
  private func keyHelpLink(_ provider: ProviderID) -> some View {
    if let spec = ProviderRegistry.spec(for: provider) {
      let region: String? =
        switch provider {
        case .minimax: model.configuration.miniMaxRegion.rawValue
        case .glm: model.configuration.glmRegion.rawValue
        default: nil
        }
      Link(model.text(.providersGetKey), destination: spec.keyHelpURL(region))
        .font(.caption)
    }
  }

  @ViewBuilder
  private func addAccountSection(_ provider: ProviderID) -> some View {
    if addAccountExpanded.contains(provider) {
      VStack(alignment: .leading, spacing: 10) {
        Text(model.text(.providersAddAccountNote))
          .font(.caption)
          .foregroundStyle(.secondary)
        LabeledContent(model.text(.providersAccountLabel)) {
          TextField(
            model.text(.providersAccountLabelPlaceholder),
            text: Binding(
              get: { newAccountLabels[provider, default: ""] },
              set: { newAccountLabels[provider] = $0 })
          )
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 240)
        }
        LabeledContent("API Key") {
          HStack {
            SecureField(
              model.text(.providersKeyPlaceholder),
              text: Binding(
                get: { newAccountKeys[provider, default: ""] },
                set: { newAccountKeys[provider] = $0 })
            )
            .textFieldStyle(.roundedBorder)
            Button(model.text(.actionSave)) { addAccount(provider) }
              .disabled(newAccountKeys[provider, default: ""].isEmpty)
          }
          .frame(maxWidth: 460)
        }
      }
      .padding(12)
      .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    } else {
      Button {
        addAccountExpanded.insert(provider)
      } label: {
        Label(model.text(.providersAddAccount), systemImage: "plus.circle")
          .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func regionPicker(_ provider: ProviderID) -> some View {
    if provider == .minimax {
      LabeledContent(model.text(.providersRegion)) {
        Picker(
          model.text(.providersRegion),
          selection: Binding(
            get: { model.configuration.miniMaxRegion },
            set: { region in try? model.setMiniMaxRegion(region) })
        ) {
          Text(model.text(.regionGlobal)).tag(MiniMaxRegion.global)
          Text(model.text(.regionChina)).tag(MiniMaxRegion.china)
        }
        .labelsHidden()
        .frame(width: 180)
      }
    } else if provider == .glm {
      LabeledContent(model.text(.providersRegion)) {
        Picker(
          model.text(.providersRegion),
          selection: Binding(
            get: { model.configuration.glmRegion },
            set: { region in try? model.setGLMRegion(region) })
        ) {
          Text(model.text(.regionGlobalZAI)).tag(GLMRegion.global)
          Text(model.text(.regionChinaBigModel)).tag(GLMRegion.china)
        }
        .labelsHidden()
        .frame(width: 180)
      }
    }
  }

  private func saveKey(_ account: AccountRow) {
    let value = replacementKeys[account.id, default: ""]
    Task {
      do {
        try await model.setAPIKey(value, for: account.id)
        replacementKeys[account.id] = ""
        message = String(
          format: model.text(.providersKeySaved), AppModel.displayName(for: account.provider))
        await loadKeyHints()
      } catch { message = error.localizedDescription }
    }
  }

  private func deleteKey(_ account: AccountRow) {
    Task {
      do {
        try await model.setAPIKey("", for: account.id)
        replacementKeys[account.id] = ""
        message = String(
          format: model.text(.providersKeyDeleted), AppModel.displayName(for: account.provider))
        await loadKeyHints()
      } catch { message = error.localizedDescription }
    }
  }

  private func addAccount(_ provider: ProviderID) {
    Task {
      do {
        let account = try model.addAccount(
          provider: provider, label: newAccountLabels[provider, default: ""])
        let key = newAccountKeys[provider, default: ""]
        try await model.setAPIKey(key, for: account.id)
        newAccountLabels[provider] = ""
        newAccountKeys[provider] = ""
        addAccountExpanded.remove(provider)
        message = String(format: model.text(.providersAccountAdded), account.label)
        await loadKeyHints()
      } catch { message = error.localizedDescription }
    }
  }

  private func removeAccount(_ account: AccountRow) {
    Task {
      do {
        try await model.removeAccount(id: account.id)
        message = String(format: model.text(.providersAccountRemoved), account.label)
        await loadKeyHints()
      } catch { message = error.localizedDescription }
    }
  }

  private func authorizeClaudeCredential() {
    Task {
      do {
        try await model.authorizeClaudeCredentialAccess()
        message = model.text(.providersClaudeAuthorizationSucceeded)
      } catch {
        message = error.localizedDescription
      }
    }
  }

  private func stopUsingClaudeCredential() {
    Task {
      do {
        try await model.stopUsingClaudeCredential()
        message = model.text(.providersClaudeStopped)
      } catch {
        message = error.localizedDescription
      }
    }
  }

  private func migrateLegacyCredentials() {
    Task {
      do {
        let count = try await model.migrateLegacyCredentials()
        message =
          count == 0
          ? model.text(.providersLegacyMigrationNone)
          : String(format: model.text(.providersLegacyMigrationSucceeded), count)
        await loadKeyHints()
      } catch {
        message = error.localizedDescription
      }
    }
  }

  private func loadKeyHints() async {
    var hints: [UUID: String] = [:]
    for group in model.accountGroups + model.costAccountGroups {
      for account in group.accounts {
        hints[account.id] = await model.keyHint(for: account.id)
      }
    }
    keyHints = hints
  }

  private func sourceText(_ source: CredentialSource) -> String {
    switch source {
    case .apiKey: model.text(.sourceKeychain)
    case .cliCredential: model.text(.sourceCLI)
    case .environmentVariable: model.text(.sourceEnvironment)
    case .localAppServer: model.text(.subtitleCodex)
    }
  }

  private func subtitleKey(_ provider: ProviderID) -> L10n.Key {
    switch provider {
    case .codex: .subtitleCodex
    case .kimi: .subtitleKimi
    case .minimax: .subtitleMinimax
    case .glm: .subtitleGLM
    case .claude: .subtitleClaude
    case .openrouter, .deepseek: .providersSubtitle
    }
  }
}
