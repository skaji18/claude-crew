# Parent Session Guide — Detailed Processing Flow

このドキュメントは親セッションの詳細な処理フローを定義する。
概要は `CLAUDE.md` を参照。

## 処理フロー

人間からタスクを受けたら、以下の4フェーズで処理する。

### コミット準備

フレームワークファイルへの変更を追跡するため、cmd開始時にベースコミットを記録する:

1. 現在のHEADをベースコミットとして取得する:
   ```bash
   git rev-parse HEAD
   ```
2. execution_log.yaml のトップレベルに `base_commit: {hash}` を記録する

### Pre-Action Gate（必須）

タスク受領後、コミット準備の後、ファイル操作の前に以下を確認する:

**Q1: 例外条件に該当するか？**
→ Phase 1 例外条件（6項目）を確認。該当する場合のみ Phase 1 省略手順へ。
  ただし省略手順でも worker への委譲は必須（親の直接 Edit/Write は禁止）。

**Q2: 入力ソースは何か？**
→ Plan mode の出力、他セッションからの転送、ユーザーの直接指示、
  いずれの場合も request.md に書き出して Phase 1 に渡す。
  ※ 既に詳細な計画が存在していても、Phase 1（decomposer）は省略不可。

**Q3: 自分（親）が Edit/Write を使おうとしていないか？**
→ YES の場合、STOP。execution_log.yaml 以外のファイルを
  親が直接編集してはならない。worker に委譲する。

### フェーズ1: 分解（Decompose）

**Phase instructions**: If `config.yaml: phase_instructions.decompose` is non-empty, append its content to the decomposer prompt.

1. `work/cmd_xxx/` ディレクトリを作成する（xxxは連番）:
   ```bash
   ./scripts/new_cmd.sh
   ```
   - スクリプト内部でmkdirのアトミック性 + 最大5回リトライにより衝突を回避
   - 成功時は `cmd_NNN` を標準出力に返す
   - `new_cmd.sh` は `scripts/merge_config.py` を呼び出し、`config.yaml` と `local/config.yaml`（存在する場合）をマージした結果を `work/cmd_NNN/config.yaml` に出力する
   - 以降のcmd内での設定参照は `work/cmd_NNN/config.yaml` を使用する（ルートの `config.yaml` は直接参照しない）
2. 人間の依頼内容を `work/cmd_xxx/request.md` に書く
3. 分解役サブエージェントを起動する:
   - テンプレートパス（TEMPLATE_PATH）: `templates/decomposer.md`
   - 入力パス（REQUEST_PATH）: `work/cmd_xxx/request.md`
   - 出力パス（PLAN_PATH）: `work/cmd_xxx/plan.md`
   - タスク出力先（TASKS_DIR）: `work/cmd_xxx/tasks/`
   - prompt に TEMPLATE_PATH + 上記3パスを明記する（テンプレートの内容は含めない）
4. 結果: `work/cmd_xxx/plan.md` にタスク分解結果が書かれる
   - 各サブタスクが `work/cmd_xxx/tasks/task_N.md` として生成される
   - **Phase A 最適化（W4）**: decomposer は `work/cmd_xxx/wave_plan.json` も生成する
     - 存在する場合、Phase 2 で wave_plan.json を使用してWave構築効率を向上
     - 存在しない場合、従来通り plan.md を解析してWaveを構築（後方互換性）

### Phase 1.5: Plan Validation (Optional, W1)

If `config.yaml: plan_validation` is `true`, validate the plan before execution:

#### Step 1: Launch Plan Reviewer

Use Task tool to launch a validation sub-agent:
- **Persona**: worker_reviewer
- **Model**: haiku (fast validation, max_turns: 10)
- **Prompt**:
  ```
  TEMPLATE_PATH: templates/worker_reviewer.md

  Review the execution plan against the original request.

  INPUT_FILES:
  - REQUEST_PATH: {request.md path}
  - PLAN_PATH: {plan.md path}

  OUTPUT: {work_dir}/plan_review.md

  Your review MUST end with one of:
  - APPROVE: Plan accurately implements the request
  - APPROVE-WITH-NOTES: Plan is acceptable but has minor issues (list them)
  - REJECT: Plan has critical flaws (explain specifically)

  Focus on:
  - Does the plan address all requirements in the request?
  - Are task dependencies logical?
  - Are output paths unambiguous?
  - Is the scope reasonable (check for scope_warning in plan.md)?
  ```

#### Step 2: Read Review Result

Read `plan_review.md` and check the final verdict line.

#### Step 3: Decision Logic

- **APPROVE** or **APPROVE-WITH-NOTES**: Proceed to Phase 2
  - If APPROVE-WITH-NOTES, include notes in execution log metadata

- **REJECT**: Re-run decomposer with feedback (one retry max)
  1. Append reviewer feedback to request.md (in-memory, not file modification)
  2. Re-run Phase 1 with augmented request
  3. Read new plan.md
  4. Proceed to Phase 2 regardless of second result (no infinite loop)

#### Step 4: Logging

Record in execution_log.yaml:
```yaml
plan_validation:
  enabled: true
  verdict: "APPROVE" | "APPROVE-WITH-NOTES" | "REJECT"
  retry_occurred: false | true
  notes: "reviewer notes if any"
```

**Important**: If plan_validation is false in config, skip Phase 1.5 entirely and proceed directly to Phase 2.

### フェーズ2: 実行（Execute）

**Phase instructions**: If `config.yaml: phase_instructions.execute` is non-empty, append its content to all worker prompts.

#### Secretary 委譲判定（Phase C）

Phase 2 開始時に、以下の条件をチェックする:

```
IF config.yaml: secretary.enabled == true
   AND "phase2_wave_construct" in config.yaml: secretary.delegate_phases
   AND task_count >= config.yaml: secretary.min_tasks_for_delegation
THEN:
  → Secretary 委譲フロー（以下）を実行
ELSE:
  → 従来の Wave 構築フロー（既存フロー）を実行
```

#### Secretary 委譲フロー（Phase C）

secretary.enabled が true で phase2_wave_construct が delegate_phases に含まれている場合:

1. **Secretary リクエストの作成**:
   - ファイルパス: `work/cmd_xxx/secretary_request.md`
   - 内容:
     ```yaml
     OPERATION: phase2_wave_construct
     WORK_DIR: work/cmd_xxx/
     PLAN_PATH: work/cmd_xxx/plan.md
     WAVE_PLAN_JSON_PATH: work/cmd_xxx/wave_plan.json
     ```

2. **Secretary サブエージェントの起動**:
   - テンプレートパス（TEMPLATE_PATH）: `templates/secretary.md`
   - 入力ファイル: `work/cmd_xxx/secretary_request.md`
   - 出力ファイル: `work/cmd_xxx/secretary_response.md`
   - モデル: `config.yaml: secretary.model`（デフォルト: haiku）
   - max_turns: `config.yaml: secretary.max_turns`（デフォルト: 10）
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）

3. **Secretary 応答の確認**:
   - `work/cmd_xxx/secretary_response.md` の先頭30行を Read で読み、YAMLフロントマターを確認
   - `validation.status: passed` の場合 → ステップ 4 へ
   - `validation.status: failed` または `status: failure` の場合 → ステップ 5（フォールバック）へ

4. **Secretary 成功時の処理**:
   - `work/cmd_xxx/secretary_response.md` から波割り当て YAML を読む（構造:下例参照）
   - **バリデーション層**: 各 Wave N について、そこに含まれるタスクの `depends_on` リストを確認する:
     - plan.md または wave_plan.json から各タスクの依存リストを取得
     - タスク T が Wave N に属する場合、T の `depends_on` リストのタスクがすべて Wave 1〜N-1 に含まれるか確認
     - 1つでも Wave N 以降に含まれるタスクがあれば **バリデーション失敗** → ステップ 5 へ
   - バリデーション成功の場合:
     - Secretary の Wave 割り当てを採用し、以下の構造として保持:
       ```yaml
       waves:
         - wave: 1
           tasks: [1, 3]
           depends_on_wave: []
         - wave: 2
           tasks: [2, 5]
           depends_on_wave: [1]
       ```
     - ステップ 1（従来の Wave 並列実行）に進む（以降は通常通り）

5. **フォールバック処理**:
   - IF `config.yaml: secretary.fallback_on_failure == true`:
     - ログに警告を出力: `⚠️ Secretary failed for Phase 2 wave construction, falling back to direct parsing`
     - 従来の Wave 構築フロー（以下）を実行
   - ELSE:
     - ログにエラーを出力: `❌ Secretary failed for Phase 2 and fallback is disabled`
     - Phase 2 を中止し、エラーで Phase 3 へ進まない

#### 従来の Wave 構築フロー（Wave Construction Fallback）

secretary.enabled が false または delegation に失敗した場合（フォールバック）、以下の手順で直接 Wave を構築する:

1. **phase A 最適化（W4）: wave_plan.json を優先的に読み込む**（Plan.md パース最小化）:
   - `work/cmd_xxx/wave_plan.json` が存在し有効な JSON か確認する
   - **存在する場合**:
     - JSON の `waves` 配列から Wave グループを直接抽出
     - 各 Wave の `tasks` 配列からタスク ID、persona、model、depends_on を取得
     - 手順2（従来の依存関係グラフ構築）をスキップし、JSON 構造をそのまま使用
   - **存在しない/無効な場合**:
     - フォールバック: `work/cmd_xxx/plan.md` のタスク一覧を従来通り読み込む
     - 手順2 に進む

   **Wave 構築の詳細（JSON ソース時）**:
   - JSON スキーマの `waves` 配列の順序が Wave 実行順序となる
   - 各 Wave 内の `tasks` 配列からタスク情報を抽出して並列実行リストを構築

2. **plan.md ベース Wave 構築（wave_plan.json がない場合のフォールバック）**:

   a. `work/cmd_xxx/plan.md` のタスク一覧を確認する（親はファイルパスだけ確認）
   - 確認する情報: タスク数、各タスクのファイルパス、Depends On列（依存関係）、Persona、Model
   - **タスクの詳細内容（Description等）は読まない**（パス受け渡し係原則）

   b. **依存関係グラフに基づきタスクをグループ化する**:
   - `Depends On` が `-`（依存なし）のタスクを **Wave 1** としてグループ化
   - Wave 1 のタスクに依存するタスクを **Wave 2** としてグループ化
   - 以降、依存元が全て処理済みのタスクを次の Wave にグループ化（全タスク割当まで繰り返し）
   - **Wave割り当ては `Depends On` 列のみから計算せよ。plan.md の `## Execution Order` セクションは参照用であり、Wave割り当ての正データではない。** `Execution Order` と `Depends On` 列が矛盾する場合（例: `Depends On: -` のタスクがWave 2以降に配置されている場合）、`Depends On` 列を正とし、そのタスクをWave 1に含める。

4. **Wave を並列実行する**:
   - **進捗メッセージ**: Wave 実行開始時にユーザーに通知する（ETA付き）
     - 例: `Wave 1/3: 3 tasks running (~2 min est.)`
     - ETA が算出不可の場合: `Wave 1/3: 3 tasks running`
   - 各タスクに対して実働サブエージェントを起動する:
     - テンプレートパス（TEMPLATE_PATH）: `templates/worker_xxx.md` からタスクに適したものを選択
     - 入力パス: `work/cmd_xxx/tasks/task_N.md`
     - 出力パス: `work/cmd_xxx/results/result_N.md`
     - prompt に TEMPLATE_PATH + 入出力パスを含める（テンプレートの内容は含めない）
   - **独立したタスクは1メッセージ内で複数の Task tool 呼び出しを行い並列実行する**

   #### Wave進捗メッセージの ETA 計算

   Wave の推定所要時間を算出する方法:

   1. **stats.sh データが利用可能な場合**（10+ 実行ログ）:
      - `bash scripts/stats.sh` を実行し、ペルソナ別の平均実行時間を抽出
      - 現在の Wave に属する各タスクについて、そのペルソナの平均時間を合計
      - 合計を `config.yaml: max_parallel` で除算し、Wave の推定所要時間を算出

   2. **データ不足の場合**（<10 ログ）:
      - フォールバック推定値を使用:
        - researcher: 60秒
        - writer: 90秒
        - coder: 120秒
        - reviewer: 45秒
      - 各タスクのペルソナで推定値を合計
      - 合計を `max_parallel` で除算

   3. **人間が読みやすい形式に丸める**:
      - < 90秒: "~1 min"
      - 90-150秒: "~2 min"
      - > 150秒: "~N min" (最も近い分に四捨五入)

   **エッジケース**:
   - ETA が算出不可（stats データなし、フォールバック不可）: ETA 句を省略、Wave メッセージのみ

5. **Wave 完了確認 → 次の Wave へ進む**:
   a. 現在の Wave の全タスクが完了したら、`results/` 内の result_N.md 存在をチェック
   b. 各resultファイルを `./scripts/validate_result.sh RESULT_PATH PERSONA` で検証する:
      - JSON結果の `status` が `"fail"` → リトライ対象
      - JSON結果の `status` が `"pass"` + `issues` あり → execution_log.yaml の `metadata_issues` に記録
      - JSON結果の `status` が `"pass"` + `issues` なし → 完了

   c. **Phase A 最適化（W4）: JSON メタデータフィールドで判定（result ファイル読み込み最小化）**:
      - `validate_result.sh` の JSON 出力に以下の新しいフィールドが含まれている:
        - `result_status`: result ファイルの YAML frontmatter から抽出された status フィールド
        - `result_quality`: result ファイルの YAML frontmatter から抽出された quality フィールド
        - `result_completeness`: result ファイルの YAML frontmatter から抽出された completeness フィールド
      - **これらのフィールドが存在する場合**、result ファイルの内容を読む必要なく、JSON メタデータのみで判定を完結できる:
        - `result_status: "success"` → 完了とみなす
        - `result_status: "partial"` または `result_status: "failure"` → リトライ対象
      - **フィールドが存在しない場合**（フォールバック）: 従来通り Read (limit=20) でメタデータヘッダーを読み、status/quality/completeness を確認

   d. **メタデータバリデーション**: JSON フィールドまたは手順 c の読み込みで得た YAML frontmatter の必須3項目を検証する:
      - **status**: 欠落時 → `status: failure` として扱う（品質不明のため安全側に倒す）
      - **quality**: 欠落時 → `quality: YELLOW` を付与（品質不明のため）
      - **completeness**: 欠落時 → `completeness: 0` として扱う
      - 検証結果を execution_log.yaml の該当タスクの `metadata_issues` に記録する（例: `quality missing, defaulted to YELLOW`）
      - 3項目全て存在する場合は検証パス。`metadata_issues` は空リスト `[]` のまま

   e. 欠落またはstatus=failure/partialの場合は該当タスクをリトライ（最大 `config.yaml: max_retries` 回）

   f. **部分結果の転送**: リトライ上限に達したタスクがある場合:
      - 該当タスクの result を `status: failure` として記録する（result ファイルが未生成の場合、親が最小限の failure result を生成する）
      - Phase 3（集約）に進む際、aggregator の prompt に `FAILED_TASKS: [N, M]` を追記する
      - aggregator はこれらのタスクの結果が欠落していることを前提に統合を行う
   g. **カスケード障害検出**: Wave N-1 で失敗したタスクに依存する Wave N のタスクがある場合:
      - 依存元タスクが failure/partial の場合、依存先タスクを自動スキップする
      - スキップされたタスクは execution_log.yaml に `status: skipped` + `error: "dependency task_M failed"` として記録する
      - スキップされたタスクの result は生成しない（aggregator に FAILED_TASKS として通知される）
   h. 全resultがstatus=success（またはリトライ上限に達した）ら、次のWaveを並列実行
   i. **依存元が未完了のタスクは絶対に実行しない**
   j. 全 Wave が完了するまで繰り返す

6. **Wave 実行管理**:
   - **Wave 完了時の進捗メッセージ**: 結果サマリをユーザーに通知する
     - 例: `Wave 1/3 完了 (3/3 success)`

7. 結果: `work/cmd_xxx/results/result_N.md` に各タスクの成果が書かれる
   - **全Wave完了時の進捗メッセージ**: 全体サマリをユーザーに通知する
     - 例: `Phase 2 完了: 5/5 タスク success`

8. **タイムアウト処理**: worker が `config.yaml: worker_max_turns` に到達した場合:
   a. execution_log.yaml の該当タスクに `status: timeout` として記録する
   b. 該当タスクをリトライ対象とする（最大 `config.yaml: max_retries` 回）
   c. リトライ上限到達時: result を `status: partial` として記録し、次の Wave へ進む

9. **最終検証**: 全Waveの完了後、以下を実行する:
   a. `work/cmd_xxx/results/` ディレクトリ内のファイル一覧を取得（Glob tool使用）
   b. plan.md のタスク一覧と照合し、以下を確認:
      - 欠落している result_N.md がないか
      - 各resultを `./scripts/validate_result.sh RESULT_PATH PERSONA` で検証し、メタデータヘッダーで status が "success" であるか
      - 手順4.5d のメタデータバリデーションを適用し、欠落フィールドにはデフォルト値を付与する
   c. 欠落がある場合: フェーズ2のリトライフローに従い再実行する。上限到達時は欠落を report.md に記録して次フェーズへ進む

10. **失敗サマリ出力**: Phase 2 完了時に failure/partial タスクが存在する場合、以下の構造化メッセージをユーザーに出力する:
   ```
   ⚠️ Phase 2 completed with failures:
   - Task N ({persona}): {status} — {error summary}
   - Task M ({persona}): {status} — {error summary}
   Action: {次のアクション — 再分解/集約続行/手動介入}
   ```
   - failure タスクがある場合でも Phase 3 に進む（aggregator が部分結果を統合する）
   - 50%以上が failure の場合のみフィードバックループを起動する

11. **実行時間チェック**: `config.yaml: max_cmd_duration_sec` が設定されている場合:
   - cmd 開始時刻（execution_log.yaml の `started`）からの経過時間を計算する
   - 閾値を超えた場合、ユーザーに警告を出力する: `⚠️ cmd_NNN has exceeded max duration (${elapsed}s > ${max}s)`
   - 警告のみ。実行を中断しない

### フィードバックループ（品質不足時の再分解）

全Wave完了・最終検証後、partial/failure のタスクが全体の50%以上の場合、decomposerを再起動して失敗タスクのみ再分解する（plan_retry.md として生成）。再分解→再実行は**1回限り**。2回目も50%以上失敗なら、そのまま集約フェーズに進み report.md に記録する。

### フェーズ3: 集約（Aggregate）

**Phase instructions**: If `config.yaml: phase_instructions.aggregate` is non-empty, append its content to the aggregator prompt.

#### Secretary Delegation 判定（Phase B）

Phase 3 開始時に、以下の条件をチェックする:

```
IF config.yaml: secretary.enabled == true
   AND "phase3_report" in config.yaml: secretary.delegate_phases
   AND task_count >= config.yaml: secretary.min_tasks_for_delegation
THEN:
  → Secretary 委譲フロー（以下）を実行
ELSE:
  → 従来の集約フロー（既存フロー）を実行
```

#### Secretary Delegation フロー（Phase B）

secretary.enabled が true で phase3_report が delegate_phases に含まれている場合:

1. **Secretary リクエストの作成**:
   - ファイルパス: `work/cmd_xxx/secretary_request.md`
   - 内容:
     ```yaml
     OPERATION: phase3_report
     RESULTS_DIR: work/cmd_xxx/results/
     PLAN_PATH: work/cmd_xxx/plan.md
     REPORT_PATH: work/cmd_xxx/report.md
     REPORT_SUMMARY_PATH: work/cmd_xxx/report_summary.md
     ```

2. **Secretary サブエージェントの起動**:
   - テンプレートパス（TEMPLATE_PATH）: `templates/secretary.md`
   - 入力ファイル: `work/cmd_xxx/secretary_request.md`
   - 出力ファイル: `work/cmd_xxx/secretary_response.md`
   - モデル: `config.yaml: secretary.model`（デフォルト: haiku）
   - max_turns: `config.yaml: secretary.max_turns`（デフォルト: 10）
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）

3. **Secretary 応答の確認**:
   - `work/cmd_xxx/secretary_response.md` の先頭30行を Read で読み、YAMLフロントマターを確認
   - `status: success` の場合 → ステップ 4 へ
   - `status: failure` の場合 → ステップ 5（フォールバック）へ

4. **Secretary 成功時の処理**:
   - `work/cmd_xxx/report_summary.md` が生成されているか確認
   - 生成されている場合:
     - 親は `work/cmd_xxx/report_summary.md` を読み、人間に報告する
     - Memory MCP 候補は `work/cmd_xxx/report.md` に記録されたまま保持する（Phase 4 完了後に一括提示）
     - Phase 3 完了
   - 生成されていない場合 → ステップ 5（フォールバック）へ

5. **フォールバック処理**:
   - IF `config.yaml: secretary.fallback_on_failure == true`:
     - ログに警告を出力: `⚠️ Secretary failed for Phase 3, falling back to aggregator`
     - 従来の集約フロー（以下）を実行
   - ELSE:
     - ログにエラーを出力: `❌ Secretary failed for Phase 3 and fallback is disabled`
     - Phase 3 を中止し、エラーで Phase 4 へ進まない

#### 従来の集約フロー（Aggregator）

secretary.enabled が false または delegation に失敗した場合（フォールバック）、以下の手順で直接 aggregator を実行:

1. 集約役サブエージェントを起動する:
   - テンプレートパス（TEMPLATE_PATH）: `templates/aggregator.md`
   - 入力パス（RESULTS_DIR）: `work/cmd_xxx/results/`
   - 計画パス（PLAN_PATH）: `work/cmd_xxx/plan.md`
   - 出力パス（REPORT_PATH）: `work/cmd_xxx/report.md`
   - 要約出力パス（REPORT_SUMMARY_PATH）: `work/cmd_xxx/report_summary.md`
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）

2. 結果: `work/cmd_xxx/report.md`（詳細版）と `work/cmd_xxx/report_summary.md`（要約版、≤50行）に最終報告が書かれる

3. 親は `work/cmd_xxx/report_summary.md` を読み、人間に報告する（詳細版 report.md は原則読まない）

4. Memory MCP 候補は report.md に記録されたまま保持する（Phase 4 完了後に一括提示）

### フェーズ4: 回顧（Retrospect）

**Phase instructions**: If `config.yaml: phase_instructions.retrospect` is non-empty, append its content to the retrospector prompt.

Phase 3 完了後、cmd の結果を振り返り、失敗からは改善提案を、成功からはスキル化提案を生成する。
`config.yaml` の `retrospect.enabled` が `false` の場合、Phase 4 を完全スキップする。

#### モード判定

1. `config.yaml` の `retrospect.enabled` を確認する。`false` なら Phase 4 を完全スキップし、人間への報告に進む
2. `work/cmd_xxx/report_summary.md` の先頭20行を Read で読み、YAMLフロントマターを取得する
3. 以下のいずれかに該当すれば **fullモード**（失敗分析＋成功分析）で起動する:
   - `status` が `failure` または `partial`
   - `quality` が `RED`
   - `quality` が `YELLOW` かつ `completeness` < 80
   - `failed_tasks` が1件以上
4. 上記に該当しなければ **lightモード**（成功パターン分析のみ）で起動する

**手動トリガー**: 人間が「このcmdを振り返れ」等と明示的に指示した場合、モード判定に関係なく **fullモード** で強制起動する。

#### retrospector サブエージェントの起動

1. テンプレートパス（TEMPLATE_PATH）: `templates/retrospector.md`
2. 以下のパスとモードを prompt に明記する（テンプレートの内容は含めない）:
   - `WORK_DIR`: `work/cmd_xxx/`
   - `REPORT_PATH`: `work/cmd_xxx/report.md`
   - `RETROSPECTIVE_PATH`: `work/cmd_xxx/retrospective.md`
   - `MODE`: `full` または `light`（モード判定の結果）
3. サブエージェントを起動する（model: `config.yaml` の `retrospect.model`）
4. 結果: `work/cmd_xxx/retrospective.md` に改善提案書が書かれる

#### retrospective.md のメタデータ確認

retrospector 完了後、親セッションは `work/cmd_xxx/retrospective.md` の先頭20行を Read でメタデータを確認する:

- `improvements_accepted` > 0 の場合: 改善提案あり
- `skills_accepted` > 0 の場合: スキル化提案あり
- 両方 0 の場合: 「構造的な改善点・スキル化候補は見つかりませんでした」と報告する

#### LP Flush (Phase 4 スキップ時)

Phase 4 がスキップされた場合（`retrospect.enabled: false` または手動スキップ）、
かつ `lp_system.enabled: true` かつ `lp_system.collect_signals: true` の場合、
LP 処理のみ軽量サブエージェントで実行する:

1. LP Flush サブエージェントを起動する:
   - テンプレートパス: `templates/lp_flush.md`
   - Model: haiku
   - max_turns: 15
   - Input: WORK_DIR, RESULTS_DIR
   - Output: `{WORK_DIR}/lp_flush_output.md`

2. LP Flush 出力のメタデータ（先頭20行）を Read で確認する

3. LP 候補が存在する場合:
   - 一括承認フローに含めて提示する（Phase 4 経由と同じフォーマット）

4. Signal log 更新が存在する場合:
   - haiku サブエージェントに MCP 書き込みを委譲する（既存承認フローと同様）

5. execution_log.yaml に記録する:
   ```yaml
   lp_flush:
     triggered: true
     source: "phase4_skip"
     candidates_generated: N
     signal_updates: M
   ```

#### Secretary Delegation 判定（Phase D）

retrospector 完了後（または LP Flush 完了後）、retrospective.md を読む前に以下の条件をチェックする:

```
IF config.yaml: secretary.enabled == true
   AND "phase4_approval_format" in config.yaml: secretary.delegate_phases
THEN:
  → Secretary 委譲フロー（以下）を実行
ELSE:
  → 従来の承認フロー（後述）を実行
```

#### Secretary Approval Formatting (Phase D)

secretary.enabled が true で phase4_approval_format が delegate_phases に含まれている場合:

1. **Secretary リクエストの作成**:
   - ファイルパス: `work/cmd_xxx/secretary_request.md`
   - 内容:
     ```yaml
     OPERATION: phase4_approval_format
     RETROSPECTIVE_PATH: work/cmd_xxx/retrospective.md
     REPORT_PATH: work/cmd_xxx/report.md
     MAX_OUTPUT_LINES: 100
     ```

2. **Secretary サブエージェントの起動**:
   - テンプレートパス（TEMPLATE_PATH）: `templates/secretary.md`
   - 入力ファイル: `work/cmd_xxx/secretary_request.md`
   - 出力ファイル: `work/cmd_xxx/secretary_response.md`
   - モデル: `config.yaml: secretary.model`（デフォルト: haiku）
   - max_turns: `config.yaml: secretary.max_turns`（デフォルト: 10）
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）

3. **Secretary 応答の確認**:
   - `work/cmd_xxx/secretary_response.md` の先頭30行を Read で読み、YAMLフロントマターを確認
   - `status: success` の場合 → ステップ 4 へ
   - `status: failure` の場合 → ステップ 5（フォールバック）へ

4. **Secretary 成功時の処理**:
   - `work/cmd_xxx/secretary_response.md` の本文（YAMLフロントマター後）を読む（≤100行）
   - Secretary が生成した整形済み提案テキストをユーザーに提示
   - 提案にはEvidenceフィールドを**そのまま含める**（要約なし）
   - 各提案に「詳細は retrospective.md を参照」のリンクを付与
   - ユーザーが一括で承認/却下を判断（後続ステップは従来の承認フローと同じ）

5. **フォールバック処理**:
   - IF `config.yaml: secretary.fallback_on_failure == true`:
     - ログに警告を出力: `⚠️ Secretary failed for Phase 4 approval formatting, reading retrospective.md directly`
     - 従来の承認フロー（以下）を実行
   - ELSE:
     - ログにエラーを出力: `❌ Secretary failed for Phase 4 and fallback is disabled`
     - Phase 4 を中止し、エラーで人間への報告に進まない

### Phase 4 完了後: 一括承認フロー（従来フロー）

Phase 4 完了後（または Phase 4 スキップ時は LP Flush 完了後）、以下の候補を**一括で**ユーザーに提示する:

1. **改善提案一覧**: retrospective.md の改善提案セクション（Phase 4 の出力）
2. **スキル提案一覧**: retrospective.md のスキル化提案セクション（Phase 4 の出力）
3. **知識候補一覧（統合）**: report.md + retrospective.md の Memory MCP 候補 + LP 候補を統合
   - Memory MCP 候補: report.md の「## Memory MCP追加候補（統合）」セクション + retrospective.md の「## Knowledge Candidates」の MCP 部分
   - LP 候補: retrospective.md の「## Knowledge Candidates」の LP 部分（LP-NNN および LP-UPD-NNN）
   - 重複を除去して優先度順（HIGH/MEDIUM/LOW）に一覧化

ユーザーが一括で承認/却下を判断する。承認された候補のみ処理する:

#### 知識候補の提示順序

**優先度ルール**:
1. **HIGH 優先**: カウンタ >= 4.0、クロスクラスタ補強、高頻度タスクタイプへの適用
2. **MEDIUM 優先**: カウンタ 3.0-3.9、既存知識の補強、中頻度タスクタイプへの適用
3. **LOW 優先**: カウンタギリギリ（3.0）、狭いスコープ、低頻度タスクタイプへの適用

**バッチ制限**:
- 1回の承認フローで提示する LP 候補は最大3件まで（優先度順にソート）
- Memory MCP 候補は従来通り全件提示（ただし retrospector が max_candidates_per_cmd で制限済み）

#### 初回LP候補の特別処理（オンボーディング）

初めてLP候補が生成された場合（`lp:_internal:metadata` が存在しないか `total_lp_count: 0` の場合）、候補提示の前に以下の説明を表示する:

```
### 学習済み好み（Learned Preferences）について

これは、あなたの作業パターンから学習した「好み」を記録する機能です。
例えば、毎回「TypeScriptで」と指定している場合、次回から自動的にTypeScriptを選ぶようになります。

- **任意機能**: 無効化はいつでも可能です（config.yaml で lp_system.enabled: false）
- **透明性**: 全ての学習は承認後にのみ記録されます
- **変更可能**: 後から見直し・削除が可能です

以下、今回学習した候補を提示します。
```

#### LP候補の提示フォーマット

**重要**: LP候補は技術的なYAMLフォーマットではなく、自然言語で提示する。

**新規LP候補（LP-NNN）**:
```
### LP-001: [トピック名]（優先度: HIGH）

**学習内容**:
「[what] の要約を自然言語で」

**根拠**:
[evidence を自然言語で。カウンタ値とシグナルタイプの概要]
例: 「3回の独立したセッションで同様のパターンを観測（修正指示2回、後付け要求1回）」

**適用場面**:
[scope を自然言語で]
例: 「コード修正タスク全般」

**AI の行動変化**:
[action を自然言語で]
例: 「バグ修正時、テストファイルも自動的に更新します」

**品質チェック**: PASS（正確性・安全性・完全性を損ねません）

承認しますか？ [Y/n/edit]
```

**LP更新候補（LP-UPD-NNN）**:
```
### LP-UPD-001: [トピック名] の更新（優先度: MEDIUM）

**既存の学習内容**:
[現在のLP観測を自然言語で]

**更新理由**:
[N 回の矛盾シグナルを検出した旨を説明]
例: 「最近3回のセッションで異なるパターンが観測されました」

**提案する変更**:
- [ ] 完全置換（以前の好みから変化した場合）
- [ ] 条件追加（文脈依存の場合。例: "Pythonプロジェクトでは〜、TypeScriptプロジェクトでは〜"）
- [ ] 廃止（もはや適用すべきでない場合）

**新しい学習内容**:
[新しい観測内容を自然言語で]

承認しますか？ [Y/n/keep-existing]
```

#### Rejection Memory Storage

When user rejects retrospector proposals:

1. Identify the rejection category:
   - Template modification proposals → `workflow:rejected_proposal:template_modification`
   - Skill proposals → `workflow:rejected_proposal:skill`
   - Improvement proposals → `workflow:rejected_proposal:improvement`

2. Store Memory MCP entity:
   ```
   mcp__memory__create_entities({
     entities: [{
       name: "workflow:rejected_proposal:{category}",
       entityType: "rejection_memory",
       observations: [
         "Rejected on {date} in {cmd_id}",
         "Proposal type: {description}",
         "Reason: {user's stated reason if any}"
       ]
     }]
   })
   ```

3. This prevents retrospector from repeatedly proposing the same category in future cmds.

**Note**: Rejection memory storage is optional. Only store if the user explicitly rejects a category of proposals (not individual proposals).

#### 承認された候補の処理

- **改善提案**: 承認された各改善に対して以下を実行:
  1. 対象ファイルに変更を適用する
  2. CHANGELOG.md の `## [Unreleased]` に適切なカテゴリ（Added/Changed/Fixed/Deprecated/Removed）でエントリを追加する
     - フォーマット: `- **{対象}** ({改善ID}) — {説明}`
  3. 変更ファイルと CHANGELOG.md をステージする:
     ```bash
     git add {変更ファイル} CHANGELOG.md
     ```
  4. Conventional Commits 形式でコミットする:
     ```bash
     git commit -m "$(cat <<'EOF'
     {type}({scope}): {description}

     Co-Authored-By: Claude <noreply@anthropic.com>
     EOF
     )"
     ```
  5. **コミットしない場合**: work/ 配下のみの変更、またはユーザーが却下した場合

  **type マッピング**:

  | 改善の種類 | type |
  |-----------|------|
  | 新機能追加 | `feat` |
  | 既存機能の変更・強化 | `feat` |
  | バグ修正 | `fix` |
  | リファクタリング | `refactor` |
  | ドキュメントのみ | `docs` |

  **scope**: 変更対象ディレクトリ（`templates`, `config`, `scripts`, `docs` 等）

- **スキル化提案**: スキル設計書を作成

- **知識候補（Memory MCP + LP）**: サブエージェント（haiku, max_turns=5）に委譲して処理
  1. Memory MCP 候補: `mcp__memory__create_entities` で追加
  2. LP 候補: `mcp__memory__create_entities` で追加（entityType: `learned_preference`）
  3. LP 更新候補: 既存エンティティへの observation 追加または置換
  4. LP 内部状態の更新（後述の LP System State Management セクション参照）

全ての適用結果を `execution_log.yaml` に記録する。

### LP System State Management

LP承認フロー中に親セッションが実行する内部状態管理操作:

#### Signal Log の更新

承認/却下された LP 候補に対応する signal log エントリを処理する:

1. **承認された LP 候補**:
   - `lp:_internal:signal_log` から該当トピックのエントリを削除（永続 LP エンティティに昇格したため）
   - サブエージェントに委譲して `mcp__memory__delete_observations` を実行

2. **却下された LP 候補**:
   - `lp:_internal:signal_log` から該当トピックのエントリを削除（カウンタリセット）
   - サブエージェントに委譲して `mcp__memory__delete_observations` を実行

3. **保留（ユーザーが判断を先送り）**:
   - Signal log をそのまま保持（次回以降のセッションで追加シグナルが蓄積可能）

**内部エンティティ更新の実行方法**:
```bash
# haiku サブエージェントに以下の prompt で委譲（max_turns: 5）
Prompt: |
  Update LP internal state in Memory MCP.

  Approved LP topics: [list of topics]
  Rejected LP topics: [list of topics]

  For each approved topic, delete the corresponding observation from lp:_internal:signal_log.
  For each rejected topic, delete the corresponding observation from lp:_internal:signal_log.

  Use mcp__memory__delete_observations tool.
```

#### Metadata の更新

承認された LP 候補の数に応じて `lp:_internal:metadata` を更新する:

1. **現在の LP 数を取得**:
   ```
   mcp__memory__search_nodes(query="lp:")
   ```
   - `lp:_internal:*` を除外してカウント

2. **LP 数上限チェック**:
   - 現在の LP 数 + 新規承認数 が `config.yaml: lp_system.lp_cap`（デフォルト: 40）を超える場合:
     - ユーザーに警告: 「LP数が上限に近づいています（現在 X/40）。古いLPの見直しを推奨します。」
     - 上限到達時: 承認フロー中に stale LP のプルーニングを提案

3. **Metadata エンティティの更新**:
   - サブエージェントに委譲して `mcp__memory__add_observations` または `mcp__memory__create_entities` を実行
   - 更新フィールド: `[total_lp_count] X`

**Metadata 更新の実行方法**:
```bash
# haiku サブエージェントに以下の prompt で委譲（max_turns: 5）
Prompt: |
  Update lp:_internal:metadata entity in Memory MCP.

  Current LP count: {count}
  LP cap: {cap}

  If lp:_internal:metadata exists, update the [total_lp_count] field.
  If it does not exist, create it with initial metadata.

  Use mcp__memory__add_observations or mcp__memory__create_entities as appropriate.
```

#### LP 数上限到達時のプルーニング

LP 数が上限（40）に到達した場合、ユーザーに古い LP の見直しを提案:

1. **Stale LP の抽出**:
   - 全 LP エンティティの observation から `[meta] Last reinforced: YYYY-MM-DD` を解析
   - Last reinforced が 60+ 日前、または 20+ セッション前の LP をリストアップ

2. **ユーザーへの提示**:
   ```
   LP数が上限に到達しました（40/40）。以下の古いLPの見直しをお勧めします:

   ### Stale LP Candidates (60+ days without reinforcement)
   - lp:defaults:language_choice: [last reinforced: 2025-12-01]
   - lp:judgment:readability_vs_performance: [last reinforced: 2025-11-20]

   削除しますか？ [Y/n/review-all]
   ```

3. **削除承認時**:
   - サブエージェントに委譲して `mcp__memory__delete_entities` を実行
   - Metadata の `[total_lp_count]` を更新

### Aggregate Profile Review (Milestone-Based)

When LP count crosses milestones (10, 20, 30), present **aggregate profile review** to user:

**Trigger detection**:
- After updating metadata, check if total_lp_count is in [10, 20, 30]

**Presentation format**:
```
### Aggregate Profile Review: You now have {N} learned preferences

**Purpose**: Review the overall "profile" created by individual LP approvals. Individual approvals ≠ awareness of aggregate pattern.

**Vocabulary (your term definitions)**: {list lp:vocabulary:* entities}
**Defaults (your repeated choices)**: {list lp:defaults:* entities}
**Avoidance (what you consistently reject)**: {list lp:avoid:* entities}
**Judgment patterns (your tradeoff priorities)**: {list lp:judgment:* entities}
**Communication style (how you prefer to interact)**: {list lp:communication:* entities}
**Task scope assumptions (what you expect included)**: {list lp:task_scope:* entities}

**Options**:
- [Keep all] - Continue with current profile
- [Review individually] - Go through each LP for potential deletion/edit
- [Clear all] - Delete all LPs and reset system

Choose: [keep/review/clear]
```

**Implementation**:
1. Query all LP entities: `mcp__memory__search_nodes(query="lp:")`
2. Exclude `lp:_internal:*` entities
3. Group by cluster
4. Present cluster-by-cluster summary (1-2 line summary per LP)
5. Handle user choice:
   - `keep`: Continue, no action
   - `review`: Iterate through LPs, offer delete/edit/keep per LP
   - `clear`: Execute reset_all workflow (see Section: Right-to-Forget Workflow)

### Right-to-Forget Workflow (reset_all)

When `config.yaml: lp_system.reset_all: true` is detected OR user requests "delete all LPs":

**Steps**:

1. **Detect trigger**:
   - Read `config.yaml` at session start
   - Check `lp_system.reset_all` value
   - OR user says: "delete all LPs", "reset LP system", "forget everything"

2. **Confirm with user** (if not already explicit):
   ```
   You requested deletion of all learned preferences. This will:
   - Delete all {N} LP entities (lp:vocabulary:*, lp:defaults:*, etc.)
   - Delete signal accumulation state (pending signals)
   - Delete LP system metadata
   - Disable LP system (lp_system.enabled: false)

   This cannot be undone. Proceed? [y/N]
   ```

3. **Execute deletion** (if confirmed):
   ```bash
   # Delegate to haiku subagent (max_turns: 5)
   Prompt: |
     Delete all LP system data from Memory MCP.

     Steps:
     1. Search for all lp:* entities: mcp__memory__search_nodes(query="lp:")
     2. Delete all LP entities (including lp:_internal:*): mcp__memory__delete_entities
     3. Confirm deletion count

     Return: Total entities deleted
   ```

4. **Update config.yaml**:
   ```yaml
   lp_system:
     enabled: false       # Disable system
     reset_all: false     # Reset flag (one-shot)
   ```

5. **Confirm to user**:
   ```
   Deleted {N} learned preferences
   Deleted internal state (signal_log, metadata)
   LP system disabled

   To re-enable: Set lp_system.enabled: true in config.yaml
   ```

### コミット履歴の確認

一括承認フロー完了後、cmd中に作成されたコミットをユーザーに表示する:

```bash
git log --oneline ${BASE_COMMIT}..HEAD
```

コミットがない場合（承認された改善が work/ 外のファイルを変更しなかった場合）は表示をスキップする。

## Phase Instructions Injection (F23)

`config.yaml: phase_instructions` に非空の文字列が含まれている場合、対応するフェーズプロンプトに追記する:

### Injection Points

- **Phase 1 (Decompose)**: `phase_instructions.decompose` を decomposer プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 2 (Execute)**: `phase_instructions.execute` を全 worker プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 3 (Aggregate)**: `phase_instructions.aggregate` を aggregator プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 4 (Retrospect)**: `phase_instructions.retrospect` を retrospector プロンプトの TEMPLATE_PATH 指示の後に追記

### Format

追加フェーズ指示は以下の形式で挿入する:

```
## Instructions
TEMPLATE_PATH: templates/decomposer.md
↑ このファイルを最初に Read し、指示に従え。

このフェーズの追加指示:
{phase_instructions.decompose}

## タスク固有情報
...
```

### Use Cases

- プロジェクト固有の制約（例: "vendor/ ディレクトリ内のファイルは絶対に変更しない"）
- ワークフロー設定（例: "機能実装時は必ずテストファイルも含める"）
- ドメイン別ガイドライン（例: "docs/standards.md の社内コーディング規約に従う"）
- セキュリティ要件（例: "API キーが含まれるファイルは絶対に修正しない"）

### 重要な注意

- Phase instructions は**追記される**（テンプレート指示に優先されない）
- テンプレートの指示がフェーズ指示より優先される
- 空文字列の場合、追記は行われない

## 親セッションの行動ルール

### 基本原則
- 人間からタスクを受けたら、まず `work/cmd_xxx/` ディレクトリを作成する
- cmd番号は連番管理。既存の最大番号 + 1 を使う（並列セッション時はmkdirアトミックリトライで衝突回避）
- **「パス受け渡し係」原則に従う**（詳細は下記「パス受け渡し係」原則の許容範囲を参照）
- サブエージェントの結果は「返り値」ではなく「ファイル」を正データとする
- フェーズ2完了後は必ずresultファイルの存在確認を行う（リトライはフェーズ2フローに従う）

### コンテキスト衛生

- **Wave完了メッセージ**: pass/fail のステータスとタスク数のみ報告する。validate_result.sh の JSON 出力全文をコンテキストに蓄積しない
  - Good: `Wave 1/3 完了 (3/3 success)`
  - Bad: `Wave 1 results: {"complete_marker": true, "line_count": 245, ...}`
- **result ファイル読み取り制限**: メタデータヘッダー（先頭20行）のみ読む。本文は絶対に読まない
- **execution_log.yaml 更新**: 各エントリは最小限のフィールドのみ。エラーメッセージは1行以内に要約する
- **進捗メッセージ**: 定型フォーマットを使い、自由文を避ける

### やってはいけないこと
- 「パス受け渡し係」原則に違反すること（ファイル経由で渡せ、コンテキストに読み込むな）
- 1つのサブエージェントに複数の独立タスクを詰め込むこと（分けて並列にせよ）

### 実行ログ

親セッションは `work/cmd_xxx/execution_log.yaml` を作成し、サブエージェントの実行記録を残す。

```yaml
cmd_id: cmd_xxx
started: "2026-02-07 10:00:00"
finished: null
status: running
base_commit: "cfa49a0"

tasks:
  - id: 1
    role: decomposer
    task: null
    model: sonnet
    started: "2026-02-07 10:00:00"
    finished: "2026-02-07 10:01:30"
    duration_sec: 90
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 2
    role: worker_coder
    task: task_1
    model: sonnet
    started: "2026-02-07 10:02:00"
    finished: "2026-02-07 10:05:00"
    duration_sec: 180
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 3
    role: worker_researcher
    task: task_2
    model: haiku
    started: "2026-02-07 10:02:00"
    finished: null
    duration_sec: null
    status: running
    error: null
    retries: 0
    metadata_issues: []
  - id: 4
    role: aggregator
    task: null
    model: sonnet
    started: "2026-02-07 10:06:00"
    finished: "2026-02-07 10:08:00"
    duration_sec: 120
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 5
    role: retrospector
    task: null
    model: sonnet
    started: "2026-02-07 10:08:30"
    finished: "2026-02-07 10:10:00"
    duration_sec: 90
    status: success
    error: null
    retries: 0
    metadata_issues: []
```

**記録タイミング**:
- サブエージェント起動時: `tasks` リストにエントリを追加し、`started` に現在時刻（`date '+%Y-%m-%d %H:%M:%S'`）を記録、`status` を `running` に設定
- サブエージェント完了時: `finished` に現在時刻を記録、`duration_sec` を計算（秒数）、`status` を `success`/`failure` に更新
- リトライ時: 同じエントリの `status` を `retrying` に更新し、`started` を新しい時刻に書き換え、`retries` をインクリメント
- メタデータバリデーション時: フェーズ2手順4dで必須項目の欠落や構造的品質問題を検出した場合、`metadata_issues` リストに記録する（例: `["quality missing, defaulted to YELLOW", "Sources section missing"]`）
- 全タスク完了時: トップレベルの `finished` に現在時刻を、`status` を `success`/`partial`/`failure` に更新

**Status の定義**:
- `pending`: タスクは定義されているが、まだ実行されていない（依存関係待ち）
- `running`: タスクが現在実行中
- `retrying`: タスクが失敗し、リトライ中
- `success`: タスクが正常に完了し、result ファイルが生成された
- `partial`: タスクが部分的に完了した（タイムアウト後のリトライ上限到達時など）
- `failure`: タスクが失敗し、リトライ上限に達した
- `timeout`: サブエージェントがターン上限（`config.yaml: worker_max_turns`）に到達した
- `skipped`: タスクの依存元が失敗したため、実行をスキップした

**タイムスタンプフォーマット**:
- `YYYY-MM-DD HH:MM:SS`（ローカルタイム使用）
- 未記録の場合は `null` を使用

### エラーハンドリング

サブエージェントが result ファイルを生成できなかった場合:
1. execution_log.yaml の該当タスクに `status: failure` と `error` に理由を記録する
2. フェーズ2のリトライフローに従う

### チェックポイント再開（中断復帰）

親セッションが中断後に再起動した場合、未完了のcmdを途中から再開できる:

1. `work/cmd_xxx/execution_log.yaml` を読み、各タスクの `status` を確認する
2. `status` が `success` のタスクはスキップする（対応するresultファイルの存在も確認）
3. 最初の未完了（`running`/`pending`/`failure`/`timeout`/`retrying`）タスクを含むWaveから実行を再開する
4. `running` だったタスクは result ファイルが存在すればスキップ、なければ再実行する
5. execution_log.yaml が存在しない場合は最初から実行する（通常フロー）

### フェーズ省略の判断基準

タスク規模に応じて、フェーズ1（分解）とフェーズ3（集約）の省略可否を判断する。

| サブタスク数 | 依存関係 | Phase 1（分解） | Phase 3（集約） |
|:----------:|:-------:|:--------------:|:--------------:|
| 1つ | なし | 必須 | 省略可 |
| 2つ | なし | 必須 | 任意 |
| 3つ以上 | なし | 必須 | 必須 |
| 任意 | あり | 必須 | 必須 |

- **必須**: decomposer/aggregator を必ず起動する
- **省略可**: aggregator を省略し、親が直接 report を生成してよい（Phase 1 は省略不可）
- **任意**: 親の判断で aggregator を省略可。ただし複数結果の統合が必要な場合は aggregator を使う

**Phase 1 例外条件**: 以下の場合に限り Phase 1 を省略してよい
- 1ファイル1箇所の typo修正（誤字脱字のみ）
- 既存ファイルへの1行追加・削除（新規実装・ロジック変更を含まない）
- `config.yaml` の単一値変更（version bump、閾値変更等）
- `execution_log.yaml` の更新
- 承認フローの実施（Memory MCP書き込み、改善提案のコミット等）
- ユーザーへの報告・説明のみ

上記例外を除き、**Phase 1 は必須**である。タスクが単純に見えても、decomposer を起動してタスク分解を行うこと。

Phase 1 省略時の手順（例外条件に該当する場合のみ）:
1. `work/cmd_xxx/request.md` に依頼を書く
2. 親が直接 `work/cmd_xxx/tasks/task_1.md` を作成する
3. フェーズ2（実行）に入り、実働サブエージェントで処理する
4. サブタスクが1つの場合、report.md は実働の result をそのまま人間に報告してよい
5. **Phase 3 省略時の report_summary.md 生成**: Phase 4（回顧）が有効な場合、親は result_N.md のメタデータヘッダー（先頭20行）から最小限の `report_summary.md` を生成する。フォーマット:
   ```markdown
   ---
   generated_by: "claude-crew v{version}"
   date: "YYYY-MM-DD"
   cmd_id: "cmd_NNN"
   status: {result の status}
   quality: {result の quality}
   completeness: {result の completeness}
   task_count: 1
   failed_tasks: []
   ---
   # Summary: cmd_NNN
   (Phase 3 skipped — single task)
   ```

## サブエージェント起動の標準パターン

### 共通設定
- **subagent_type**: 全サブエージェント共通で `"general-purpose"` を使用
- **model**: タスクの複雑度に応じて選択（デフォルト: `config.yaml: default_model`）:
  - `"haiku"`: 軽い作業（ファイル検索、単純な変換、フォーマット整形）
  - `"sonnet"`: 標準的な作業（コード実装、分析、レビュー）
  - `"opus"`: 複雑な判断（設計、アーキテクチャ決定、難度の高い実装）

### タイムアウト制御
- Task tool の `max_turns` パラメータで各サブエージェントのターン数を制限する
- デフォルト値: `config.yaml: worker_max_turns`（未指定時: 30ターン）
- タイムアウト到達時: execution_log.yaml に Status `timeout` として記録し、リトライ対象とする
- **注意**: Task tool に秒数ベースの timeout パラメータはない。ターン数（API往復回数）で制御する

### prompt の構成
```
## Instructions
TEMPLATE_PATH: templates/xxx.md
↑ このファイルを最初に Read し、指示に従え。

## タスク固有情報
- 入力ファイル: work/cmd_xxx/tasks/task_N.md を読め
- 出力ファイル: work/cmd_xxx/results/result_N.md に書け
- [追加の指示があればここに]
```

### 並列実行のルール
- 独立したタスクは**必ず1メッセージ内で複数の Task tool 呼び出し**を行う
- 同一ファイルへの並列書き込みは禁止（ファイルパスが重複しないよう設計する）
- **フォアグラウンド並列のみ使用する**。`run_in_background: true` は使用禁止（background Taskには既知のバグあり: MCP利用不可、output_file 0バイト、通知未発火）

### ポーリング禁止
- サブエージェントの output_file を Read/tail で繰り返し確認する行為（ポーリング）は禁止
- フォアグラウンド Task は完了時に自動的に結果を返すため、ポーリングは不要でありトークンの浪費となる
- 理由: background 実行を廃止したことにより、ポーリングが必要なケースは存在しない

## 「パス受け渡し係」原則の許容範囲

親セッションが取得してよい情報と取得してはいけない情報の境界を明確にする。

**親が取得してよい情報（メタデータ）:**
- タスク数（plan.md のテーブル行数）
- ファイルパス（RESULT_PATH、成果物パス）
- 依存関係グラフ（Depends On 列）
- タスク種別（Persona 列: researcher, writer, coder, reviewer）
- model推奨（Model 列: haiku, sonnet, opus）
- **report_summary.md の全内容**（≤50行の要約。親が人間への報告に使用する）
- **report.md の「## Memory MCP追加候補（統合）」セクション**（Memory MCP候補がある場合のみ。候補確認の例外的な読み取り）
- **resultファイルのメタデータヘッダー**（YAMLフロントマター形式、先頭20行以内）:
  - Status (success/partial/failure)
  - Quality Level (GREEN/YELLOW/RED)
  - Completeness (0-100%)
  - Errors / Warnings
  - Output files

**親が取得してはいけない情報（コンテンツ）:**
- タスクの詳細内容・本文（Description, Details 等）
- 実装方針・設計判断
- 中間結果の本文
- resultファイルの本文（メタデータヘッダー以降は読まない）

## Memory MCP活用

サブエージェントはタスク開始時に `mcp__memory__search_nodes` で関連知識を検索し、過去の知見を作業に活用する。

- **タイミング**: タスクファイル読了後、作業開始前に1回検索する
- **検索キーワード**: タスクの技術領域（例: `"python async"`）、プロジェクト名（例: `"project:shogun"`）、タスク種別（例: `"entityType:best_practice"`）
- **メモリが空でも正常動作する**。メモリは補助情報であり、見つからなければそのまま作業を進めてよい
- メモリの**検索**はサブエージェント側で行う。メモリへの**書き込み**は、一括承認フローで人間が承認した候補に限り、親セッションがサブエージェントに委譲して実行する

## 操作別ポリシー

### Permission System Overview

claude-crew uses a 3-layer permission control system to balance safety with usability:

**1. Settings Layer (Static Rules)**
- File: `.claude/settings.json`
- Purpose: Blanket allow/ask/deny patterns (fast, no computation)
- Examples: `Bash(ls*)` auto-approved, `Bash(rm -rf *)` auto-rejected

**2. Hook Layer (Dynamic Analysis)**
- Provided by: `permission-guard` plugin (`/plugin install permission-guard@skaji18-plugins`)
- Purpose: Context-aware validation with 8 validation phases
- Examples: Script containment checks, path verification, subcommand analysis

**3. Subcommand Configuration (Danger Pattern Blocking)**
- File: `.claude/permission-config.yaml`
- Purpose: Prevent dangerous subcommands even if parent command is in allow list
- Examples: `git:push`, `gh:pr:merge` → routed to dialog regardless of `git *`/`gh *` allow pattern

**Flow Summary**: deny patterns → allow patterns → hook validation (8 phases) → ask patterns → user dialog

#### 3-Layer Control Table

| Layer | File | Scope | Example |
|-------|------|-------|---------|
| **Static** | `.claude/settings.json` | Glob-based patterns | `allow: ["Bash(ls*)"]`, `deny: ["Bash(rm -rf *)"]` |
| **Dynamic** | `permission-guard` plugin | Syntax/path/containment checks | Phase 1-7 validation pipeline |
| **Subcommand** | `.claude/permission-config.yaml` | Dangerous subcommand blocking | `"git:push"`, `"gh:pr:merge"` |

### Phase 7B2: Subcommand Rejection (NEW in v1.0-rc)

**Problem**: Before cmd_053, patterns like `Bash(git *)` in allow list auto-approved dangerous operations:
- `git push` (forced pushes to main)
- `git reset --hard` (destructive changes)
- `git clean -f` (data loss)
- Similar issues with `gh *` pattern

**Solution** (cmd_053): Remove git/gh from allow list → route through hook → Phase 7B2 matches subcommand patterns in `.claude/permission-config.yaml`.

**How It Works**:
1. User invokes: `git push origin main`
2. Settings.json: `git *` NOT in allow list (removed in cmd_053)
3. Hook invoked: 8-phase validation
4. Phase 7B2: Extract subcommand `push` → check `"git:push"` in `subcommand_ask` → REJECT (show dialog)
5. Result: Dialog shown instead of auto-approval

**Dangerous Patterns Blocked** (from `.claude/permission-config.yaml: subcommand_ask`):
- `git:push` — Any git push operation
- `git:clean` — Discard tracked files
- `git:reset:--hard` — Force discard changes
- `git:checkout:.` — Discard all working changes
- `git:restore:.` — Restore all files (newer git)
- `gh:pr:merge` — Merge pull request
- `gh:repo:delete` — Delete repository
- `gh:repo:archive` — Archive repository
- `gh:release:delete` — Delete release

**Safe Commands Still Auto-Approved**:
- `git status`, `git log`, `git diff` (no subcommand match)
- `gh pr view`, `gh issue list` (no subcommand match)

### PermissionRequest Hook Implementation

**Provided by**: `permission-guard` plugin (`/plugin install permission-guard@skaji18-plugins`)

**Purpose**: Auto-approve project-local script execution and safe general commands while rejecting dangerous operations.

**8 Validation Phases**:

| Phase | Name | Purpose | Action if Failed |
|-------|------|---------|------------------|
| S0 | Null byte rejection | Guard against null byte injection | REJECT |
| 1 | Control character & tool_name validation | Ensure valid JSON and tool identifier | REJECT |
| 1.5 | Safe suffix stripping | Remove harmless output redirects (2>&1, \|\| true) | CONTINUE |
| 2 | Shell syntax rejection | Block pipes, redirects, variable expansion, command substitution | REJECT |
| 3 | Command parsing | Split interpreter/script/args | CONTINUE |
| 4 | Flag normalization | Classify safe vs dangerous flags | CONTINUE |
| 5 | Path normalization | Lexical canonicalization without filesystem traversal | CONTINUE |
| 6 | scripts/ containment | Auto-approve if script in project namespace | ALLOW ✅ |
| 7 | General command approval | Route to sub-phases 7A-7D | See below |

**Phase 7 (General Command) Sub-phases**:
- **7A**: Extract command name (e.g., `curl`, `git`, `node`)
- **7B**: Check ALWAYS_ASK list (`curl`, `sudo`, `npm`, etc.) → REJECT ❌
- **7B2 (NEW)**: Check `.claude/permission-config.yaml: subcommand_ask` patterns → REJECT ❌
  - Example: `git push` matches `"git:push"` → show dialog
  - Example: `git status` does NOT match → continue to 7C
- **7C**: Collect path-like arguments
- **7D**: Verify all paths contained in project → ALLOW ✅

**Configuration Files**:
- `.claude/permission-config.yaml` — Interpreter flags, ALWAYS_ASK list, subcommand_ask patterns (Layer 2: project config)
- `local/hooks/permission-config.yaml` — Local overlay (Layer 3: user-specific overrides)
- `.claude/settings.json` — allow/ask/deny patterns

**Testing**: `/permission-guard:permission-test` command (190+ regression tests)

### パーミッション判定フロー

Bash tool 呼び出し時の優先度順の判定フロー:

```
Bash tool 呼び出し
    ↓
[Tier 1] settings.json deny → 自動拒否
    ↓ not matched
[Tier 2] settings.json allow → 自動許可
    ↓ not matched
[Tier 3] PermissionRequest hook
    ├── Phases S0-2: シェル構文ガード → 拒否
    │    └─ 失敗 → REJECT ❌
    │
    ├── Phases 3-6: scripts/ 含義判定
    │    └─ プロジェクト内スクリプト → ALLOW ✅
    │
    └── Phase 7: 汎用コマンド承認
        ├── 7A: コマンド名抽出
        ├── 7B: ALWAYS_ASK リスト一致 → REJECT ❌
        │    (curl, sudo, npm, node 等)
        ├── 7B2: サブコマンド拒否パターン (.claude/permission-config.yaml) → REJECT ❌
        │    (git push, gh pr merge 等)
        ├── 7C: パス引数収集
        └── 7D: パス引数がプロジェクト内 → ALLOW ✅
    │
    ↓ not matched
[Tier 4] settings.json ask → 条件付き確認
    ↓ not matched
ユーザーに確認ダイアログ表示
```

deny > allow > hook > ask > default の優先順位で判定される。hookは allow に該当しないコマンドでも、条件を満たせば自動承認できる補完メカニズムである。Phase 7B2（サブコマンド拒否）により、危険な操作は確認ダイアログにルーティングされる。

### 操作カテゴリ別ポリシー

3段階制御: deny（自動拒否）> ask（毎回確認）> allow（自動許可）

| 操作カテゴリ | ポリシー |
|-------------|---------|
| Bash 基本ユーティリティ（ls, grep） | 自動許可（allow リスト） |
| Git 破壊操作（push, reset --hard, clean -f, checkout ., restore .） | 毎回確認（hook Phase 7B2 経由で subcommand_ask 拒否） |
| GitHub CLI 危険操作（pr merge, repo delete, repo archive） | 毎回確認（hook Phase 7B2 経由で subcommand_ask 拒否） |
| Git 安全操作（status, log, diff, add, commit） | 自動許可（hook Phase 7D 経由） |
| GitHub CLI 安全操作（pr view, issue list） | 自動許可（hook Phase 7D 経由） |
| スクリプト実行（scripts/ 配下） | hook Phase 6 経由で自動許可（詳細は `permission-guard` plugin 参照） |
| 汎用コマンド（プロジェクト内パス）（find, cat, wc, stat, tree 等） | hook Phase 7 経由で自動許可（パス封じ込め確認） |
| ALWAYS_ASK（ネットワーク・権限昇格・インタプリタ） | 毎回確認（curl, sudo, npm, node 等。詳細は `.claude/permission-config.yaml: always_ask` 参照） |
| ファイル操作ツール（Read, Glob, Grep） | 自動許可（allow リスト） |
| ファイル書き込み（Edit, Write） | 自動許可（allow リスト） |
| HTTP DELETE（curl -X DELETE） | 自動拒否（deny リスト） |
| 危険操作（rm -rf, rm -r, pipe to sh/bash, chmod 777, DROP TABLE 等） | 自動拒否（deny リスト。詳細は `.claude/settings.json` 参照） |

## Memory MCP候補の品質基準

Memory MCPに記録する知見は以下の基準を満たすこと:

**即却下（以下に該当する候補は生成・承認しない）**:
- 特定cmd参照（`cmd_NNN`）を含む候補
- claude-crew内部アーキテクチャの記述（decomposer, aggregator, parent session, Phase, execution_log等）
- Claudeの事前学習で既知の一般知識（プロジェクト固有文脈がないOWASP/NIST/CVE等）
- 環境設定の重複（CLAUDE.md / config.yaml に既存の情報）
- 未昇華の事実記録（教訓・判断基準への変換が必要）
- 行動に落とせない抽象論

**必須条件（全て満たすこと）**:
- Cross-cmd適用可能性: 3つ以上の将来cmdで異なるドメインに適用可能
- 行動変容可能性: 読んだサブエージェントが具体的に行動を変えられる
- 観測の具体性: 条件と効果が定量的または具体的

**命名規約**: `{domain}:{category}:{identifier}`
- Good: `security:env_file_exposure_risk`, `user:shogun:preference:report_brevity`
- Bad: `claude-crew:failure_pattern:result_file_missing` (内部アーキテクチャ)

**Note**: The "Bad" example above is an intentional illustration of the instant-reject filter. Do not use `claude-crew:*` naming in actual Memory MCP entities — it violates the domain-general principle.

**1cmdあたりの候補上限**: `config.yaml: retrospect.memory.max_candidates_per_cmd`（デフォルト: 5件）

## Claude Skills提案の品質基準

Skills提案は以下の5条件を全て満たす場合のみ提案する:

1. `/skill-name [args]` でユーザーが直接起動できる自己完結型ワークフローである
2. claude-crew以外の3つ以上のプロジェクトで使える
3. 月3回以上呼び出される想定がある
4. 3ステップ以上の定型手順がある
5. 生成元システム（claude-crew）外部に価値を提供する

上記を満たさない成功パターンは、テンプレート改善（IMP-NNN）またはMemory MCP候補として提案する。

**3軸スコアリング閾値**: `config.yaml: retrospect.memory.skill_min_score`（デフォルト: 12点/15点満点）

## ディレクトリ構造
```
work/
└── cmd_xxx/
    ├── request.md          … 人間の依頼内容
    ├── plan.md             … 分解役の出力（タスク分解結果）
    ├── tasks/
    │   ├── task_1.md       … サブタスク定義
    │   ├── task_2.md
    │   └── task_N.md
    ├── results/
    │   ├── result_1.md     … 各実働の成果
    │   ├── result_2.md
    │   └── result_N.md
    ├── plan_retry.md         … 再分解結果（フィードバックループ時のみ生成）
    ├── execution_log.yaml    … 実行ログ（親セッションが更新）
    ├── report.md             … 集約役の出力（最終報告・詳細版）
    ├── report_summary.md     … 集約役の出力（要約版・≤50行・親が読む）
    └── retrospective.md      … 回顧役の出力（改善提案書・Phase 4で生成）
```

## CLAUDE.md Supplement (Parent-Only Context)

以下のセクションは CLAUDE.md からトークン削減のため移動された。親セッション向けの詳細ルール。サブエージェントは各テンプレートに個別の指示を持つため、これらの情報を必要としない。

### よくある間違い

**間違い**: 親セッションが「単純なタスクだから」と判断して直接 Edit/Write を使う

**問題点**:
- 成果物に YAML frontmatter が付かず、Phase 4 のメタデータバリデーションで失敗する
- execution_log.yaml にサブエージェント実行記録が残らず、追跡不能になる
- 並列実行の利点が失われ、複数ファイルの変更が直列化される

**正解**: 例外条件に該当しない限り、必ず decomposer を起動してタスク分解を行う

**間違い**: Plan mode の出力を受けて親が直接実装する

**なぜ起きるか**:
- "Implement the following plan" が直接実行を誘導する
- Plan の詳細さが decomposer を不要に見せる
- 新セッション境界でワークフローの意識がリセットされる

**正解**: Plan mode の出力を request.md に書き出し、Phase 1 から開始する

### Learned Preferences (LP)

LP normative rules: `docs/lp_rules.md` (source of truth).
User-facing guide: `docs/learned_preferences.md`.
LP orchestration flow: see sections above (LP Flush, approval flow, State Management, etc.).
