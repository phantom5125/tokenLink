import SwiftUI
import TokenLinkCore
import TokenLinkProviders

struct TokenizerLabView: View {
  @Bindable var model: AppModel
  @State private var session = TokenizerFingerprintSession(
    credentials: KeychainVault(),
    client: TokenizerProbeClient(http: URLSessionHTTPClient()))
  @State private var accountID: UUID?
  @State private var modelID = ""
  @State private var inputError: String?

  private var accounts: [ProviderAccount] {
    model.configuration.accounts.filter {
      $0.enabled && [.kimi, .minimax, .glm, .openrouter, .deepseek].contains($0.provider)
    }
  }

  private var selectedAccount: ProviderAccount? {
    accounts.first { $0.id == accountID } ?? accounts.first
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(label("Tokenizer comparison", "Tokenizer 对比", "トークナイザー比較"))
          .font(.largeTitle.bold())
        Text(
          label(
            "Compare an endpoint's reported input-token counts with published reference profiles. A close match suggests a similar tokenizer and request wrapper; it cannot verify the underlying model or its weights.",
            "将端点返回的输入 token 数与公开参考指纹比较。接近只说明分词与请求包装相似，不能证实底层模型或权重。",
            "入力トークン数を公開された参照値と比較します。近さは分割方式とリクエスト形式の類似を示すだけで、モデルや重みの証明にはなりません。")
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 14) {
          Text(label("Manual probe", "手动探测", "手動測定"))
            .font(.headline)
          Text(
            label(
              "Clicking Run sends 30 fixed public texts to the selected provider with at most one output token per request. This can consume plan quota or incur API charges. Keys stay in Keychain; counts stay in memory.",
              "点击运行后，会向所选厂商发送 30 条固定公开文本，每次最多生成 1 个 token；可能消耗套餐额度或产生 API 费用。密钥留在钥匙串，计数只保存在内存。",
              "実行すると固定の公開文30件を送信し、出力は各回最大1トークンです。利用枠の消費やAPI料金が発生する場合があります。鍵はキーチェーンに、計数はメモリ内に留まります。")
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          if accounts.isEmpty {
            Text(
              label(
                "Enable Kimi, MiniMax, GLM, OpenRouter, or DeepSeek and save an API key in Providers first.",
                "请先在「额度源」启用 Kimi、MiniMax、GLM、OpenRouter 或 DeepSeek 并保存 API key。",
                "プロバイダーでKimi、MiniMax、GLM、OpenRouter、DeepSeekを有効にし、APIキーを保存してください。")
            )
            .foregroundStyle(.secondary)
          } else {
            Picker(label("Account", "账户", "アカウント"), selection: $accountID) {
              ForEach(accounts) { account in
                Text("\(ProviderRegistry.displayName(for: account.provider)) · \(account.label)")
                  .tag(account.id as UUID?)
              }
            }
            .disabled(session.isRunning)
            TextField(label("Model ID", "模型 ID", "モデルID"), text: $modelID)
              .textFieldStyle(.roundedBorder)
              .disabled(session.isRunning)
            HStack {
              Button(label("Run comparison", "运行对比", "比較を実行")) { start() }
                .disabled(session.isRunning || modelID.trimmingCharacters(in: .whitespaces).isEmpty)
              if session.isRunning {
                Button(label("Cancel", "取消", "キャンセル")) { session.cancel() }
                ProgressView(value: Double(session.completed), total: 30)
                  .frame(maxWidth: 160)
                Text("\(session.completed)/30").monospacedDigit()
              }
            }
          }
          if let inputError { Text(inputError).foregroundStyle(.red) }
          if let failure = session.failure {
            Text(failureText(failure)).foregroundStyle(.red)
          }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))

        if !session.matches.isEmpty {
          results
        }
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .navigationTitle(label("Tokenizer comparison", "Tokenizer 对比", "トークナイザー比較"))
    .onAppear {
      if accountID == nil, let account = accounts.first {
        accountID = account.id
        modelID = defaultModel(for: account.provider)
      }
    }
    .onChange(of: accountID) { _, newValue in
      if let account = accounts.first(where: { $0.id == newValue }) {
        modelID = defaultModel(for: account.provider)
      }
    }
  }

  private var results: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(label("Closest reference profiles", "最接近的参考指纹", "近い参照プロファイル"))
        .font(.headline)
      if let probedTarget = session.probedTarget {
        Text(probedTarget).font(.subheadline.monospaced()).foregroundStyle(.secondary)
      }
      Text(
        label(
          "Similarity is the share of probes whose count difference equals the most common fixed offset. This is diagnostic, not a model identity verdict. Routing, hidden prompts, templates, and usage accounting can change the result.",
          "相似度是扣除最常见固定偏移后，计数差一致的测试项占比。它仅供诊断，不能判定模型身份；路由、隐藏提示词、模板和计费口径都会影响结果。",
          "類似度は最頻の固定差分に一致する測定の割合です。モデル同定ではありません。経路、隠れた指示、テンプレート、計数方式で変動します。")
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      Text(
        "\(session.observations.compactMap { $0 }.count)/30 "
          + label("valid counts", "有效计数", "有効な計数")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      ForEach(Array(session.matches.prefix(5)), id: \.model) { match in
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(match.differences.enumerated()), id: \.offset) { index, difference in
              HStack(alignment: .firstTextBaseline) {
                Text("#\(index + 1)").frame(width: 32, alignment: .leading)
                Text(promptPreview(index)).lineLimit(1).frame(
                  maxWidth: .infinity, alignment: .leading)
                Text(countText(index, difference: difference))
                  .monospacedDigit()
              }
              .font(.caption)
            }
          }
          .padding(.top, 8)
        } label: {
          HStack {
            Text(match.model).font(.subheadline.weight(.medium))
            Spacer()
            Text(match.score.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
              .monospacedDigit()
            if let offset = match.modeOffset {
              Text("Δ\(offset >= 0 ? "+" : "")\(offset)")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
      }
      if session.matches.allSatisfy({ $0.score == nil }) {
        Text(
          label(
            "Too few valid or varied counts to score (requires 20 valid, 80% coverage, and five distinct counts).",
            "有效或有区分度的计数不足，无法评分（至少 20 条有效、80% 覆盖及 5 个不同计数）。",
            "有効または多様な計数が不足しています（20件、80%のカバー率、5種類の計数が必要）。")
        )
        .foregroundStyle(.orange)
      }
      Link(
        label("Reference data and method", "参考数据与方法", "参照データと手法"),
        destination: URL(string: "https://github.com/ictchenbo/which-llm")!
      )
      .font(.caption)
      Text(session.referenceSummary)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private func start() {
    inputError = nil
    guard let account = selectedAccount else { return }
    do {
      let target = try TokenizerProbeTarget(
        provider: account.provider, model: modelID,
        miniMaxRegion: model.configuration.miniMaxRegion,
        glmRegion: model.configuration.glmRegion)
      let credentialAccount = KeychainVault.keychainAccountName(
        provider: account.provider, accountID: account.id,
        isDefault: model.configuration.isDefaultAccount(account))
      session.start(credentialAccount: credentialAccount, target: target)
    } catch {
      inputError = label("Enter a valid model ID.", "请输入有效的模型 ID。", "有効なモデルIDを入力してください。")
    }
  }

  private func promptPreview(_ index: Int) -> String {
    guard session.prompts.indices.contains(index) else { return "" }
    return String(session.prompts[index].replacingOccurrences(of: "\n", with: " ↵ ").prefix(72))
  }

  private func countText(_ index: Int, difference: Int?) -> String {
    guard session.observations.indices.contains(index),
      let observed = session.observations[index], let difference
    else { return "—" }
    return "\(observed) → \(observed + difference)  (Δ \(difference >= 0 ? "+" : "")\(difference))"
  }

  private func defaultModel(for provider: ProviderID) -> String {
    switch provider {
    case .kimi: "k3"
    case .minimax: "MiniMax-M2.7"
    case .glm: "glm-4.6"
    case .openrouter: "openai/gpt-5.4-nano"
    case .deepseek: "deepseek-chat"
    case .codex, .claude: ""
    }
  }

  private func failureText(_ failure: TokenizerFingerprintSession.Failure) -> String {
    switch failure {
    case .catalog: label("Reference data unavailable.", "参考数据不可用。", "参照データを読み込めません。")
    case .missingKey:
      label("No saved API key for this account.", "此账户没有已保存的 API key。", "このアカウントに保存済みのAPIキーがありません。")
    case .invalidModel: label("Invalid model ID.", "模型 ID 无效。", "モデルIDが無効です。")
    case .http(let code):
      label(
        "Provider returned HTTP \(code). Check the key, model ID and quota.",
        "厂商返回 HTTP \(code)。请检查 key、模型 ID 和额度。", "HTTP \(code) が返されました。キー、モデルID、利用枠を確認してください。")
    case .network:
      label(
        "Probe failed. No response data was saved.", "探测失败，未保存响应内容。", "測定に失敗しました。応答内容は保存していません。")
    case .cancelled: label("Probe cancelled.", "探测已取消。", "測定を中止しました。")
    }
  }

  private func label(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch model.currentLanguage {
    case .english: english
    case .simplifiedChinese: chinese
    case .japanese: japanese
    }
  }
}
