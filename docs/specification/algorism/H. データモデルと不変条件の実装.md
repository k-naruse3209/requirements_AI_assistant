# H. データモデルと不変条件の実装 
これは何をするシステム？
要点だけ： アプリ全体のデータを「壊れない形」で保つための**スキーマ（表・列・制約）**と、破られてはいけないルール（不変条件／Invariant）をDBレベルで担保する仕組みです。
* スキーマ：どんなテーブルがあり、どう繋がるか（PK/FK/型）。
* 不変条件：例）ocean_timeseriesは追記専用、p01∈[0,1]、T∈[0,100]、idempotency_keyは重複禁止、など。
* これらをDBの機能で強制（CHECK制約・UNIQUE・FK・権限・トリガ・ロール）し、アプリ側のバグや並行処理でも破れないようにします。MySQL 8ではCHECK制約が実際に強制されます（8.0.16+） MySQL Developer Zone+1。

他システムとの連携（どこから何を受け、何を守る？）

A: スコア整形・正規化  →  H: スキーマ＆不変条件（値域・単位を保証）
B: ベイズ統合           →  H: 時系列ストア（追記専用・FK整合）
C: 確信度/品質ルール     →  H: 観測分散の下限/上限チェック
D: 時系列特徴            →  H: 読み取り専用ビュー（分析者へ）
E: 介入プランナー        →  H: 方策/根拠タグの監査ログ整合
F: LLM後処理             →  H: 配信用カードのスキーマ検証・監査保存
G: KPI集計/評価          →  H: 参照ビュー/実験用テーブル（FK/一意性）
n8n（オーケストレーション）→  H: 書込は専用ロールのみ/再実行はイデンポテンシで吸収
* 権限はロールで管理（例：pipeline_writer はINSERTのみ、analyst_readerは読取のみ）。MySQLにはロール機能があり、権限束ねと付与が可能です MySQL Developer Zone+1。
* 並行性：InnoDBの既定はREPEATABLE READ。必要に応じてセッション単位でREAD COMMITTEDへ切替できます MySQL Developer Zone+1。
* n8nのMySQLノードはDECIMALを文字列で返すので、アプリ側で数値変換／丸め方針を統一します n8n Docs。

どのように構築する？（実装ロードマップ）
1) テーブル設計（例・主要部）
便宜上、Tスコアは0–100、p01は0–1で保存します（Aでクランプ済み前提）。
* users：user_id(PK) ほか
* baseline_profiles：初回IPIP結果（user_id FK、administered_at、ocean_T、ocean_p01、norm_version…）
    * 不変条件：p01∈[0,1]、T∈[0,100]（CHECK制約） MySQL Developer Zone
* text_personality_estimates：日々のテキスト由来のOCEAN推定（観測分散も格納）
* ocean_timeseries：BのPosteriorの追記専用時系列（user_id, date, O..N_T/p01, posterior_var_T）
    * 不変条件：UPDATE/DELETE禁止（権限でUpdate/ Deleteを付与しない＋トリガで防壁）
    * トリガでは**SIGNAL SQLSTATE '45000'**でエラー発火可能です MySQL Developer Zone+1
* intervention_plans：Eの選定結果（technique/tone/length/CTA/根拠タグ）
* behavior_events：配信・閲覧・実行・完了などの行動ログ（idempotency_key UNIQUE）
    * イデンポテンシ：同じidempotency_keyは二重処理しない（重複拒否）。API/分散処理では広く推奨されています Stripe+1
* audit_log：入力→出力→配信までの監査痕跡（OWASPのセキュア・ロギング推奨に準拠） OWASP チートシートシリーズ+1
プライバシー：GDPR等のデータ最小化（必要な目的・期間に限定）を原則化します GDPR+1。

2) 制約・権限・トリガ（サンプルDDL）

-- 役割と権限
CREATE ROLE pipeline_writer, analyst_reader;                               -- 役割
GRANT SELECT, INSERT ON db.* TO pipeline_writer;
GRANT SELECT         ON db.* TO analyst_reader;                            -- 読取専用
-- 実ユーザーへロールを付与
GRANT pipeline_writer TO 'n8n_pipeline'@'%';
GRANT analyst_reader  TO 'bi_analyst'@'%';                                  -- 参考: 役割の設計 :contentReference[oaicite:9]{index=9}

-- スキーマ例（抜粋）
CREATE TABLE baseline_profiles (
  user_id BIGINT NOT NULL,
  administered_at DATETIME NOT NULL,
  O_T TINYINT UNSIGNED, C_T TINYINT UNSIGNED, E_T TINYINT UNSIGNED, A_T TINYINT UNSIGNED, N_T TINYINT UNSIGNED,
  O_p01 DECIMAL(5,4),  C_p01 DECIMAL(5,4),  E_p01 DECIMAL(5,4),  A_p01 DECIMAL(5,4),  N_p01 DECIMAL(5,4),
  norm_version VARCHAR(32) NOT NULL,
  PRIMARY KEY (user_id, administered_at),
  CONSTRAINT ck_p01_range CHECK (O_p01 BETWEEN 0 AND 1 AND C_p01 BETWEEN 0 AND 1
    AND E_p01 BETWEEN 0 AND 1 AND A_p01 BETWEEN 0 AND 1 AND N_p01 BETWEEN 0 AND 1),
  CONSTRAINT ck_t_range CHECK (O_T BETWEEN 0 AND 100 AND C_T BETWEEN 0 AND 100
    AND E_T BETWEEN 0 AND 100 AND A_T BETWEEN 0 AND 100 AND N_T BETWEEN 0 AND 100)
); -- MySQL 8.0.16+のCHECKは実際に強制されます :contentReference[oaicite:10]{index=10}

CREATE TABLE ocean_timeseries (
  user_id BIGINT NOT NULL,
  date DATE NOT NULL,
  O_T TINYINT UNSIGNED, ... , N_p01 DECIMAL(5,4),
  posterior_var_T DECIMAL(8,3) NOT NULL,
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 追記専用: UPDATE/DELETEをトリガで禁止（権限で禁止＋二重防御）
DELIMITER //
CREATE TRIGGER ocean_timeseries_no_update BEFORE UPDATE ON ocean_timeseries
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ocean_timeseries is append-only';
END//
CREATE TRIGGER ocean_timeseries_no_delete BEFORE DELETE ON ocean_timeseries
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ocean_timeseries is append-only';
END//

-- 任意：時系列特徴テーブル（Dモジュール）
CREATE TABLE ocean_features (
  user_id BIGINT NOT NULL,
  date DATE NOT NULL,
  trait CHAR(1) NOT NULL CHECK (trait IN ('O','C','E','A','N')),
  ewma_T DECIMAL(6,2) NULL,
  slope_T_7d DECIMAL(6,2) NULL,
  var_T_14d DECIMAL(6,2) NULL,
  change_flag TINYINT(1) NULL,
  PRIMARY KEY (user_id, date, trait),
  FOREIGN KEY (user_id, date) REFERENCES ocean_timeseries(user_id, date)
);
DELIMITER ;  -- SIGNALは手続きからエラーを返す仕組みです :contentReference[oaicite:11]{index=11}

-- Idempotency: 重複リクエスト防止
CREATE TABLE behavior_events (
  event_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  event_type ENUM('sent','viewed','clicked','completed') NOT NULL,
  event_ts DATETIME NOT NULL,
  idempotency_key CHAR(36) NOT NULL,
  UNIQUE (idempotency_key)  -- 同じ処理を二重に実行しない :contentReference[oaicite:12]{index=12}
);
注意：n8nのMySQLノードはDECIMALを文字列で返すため、後段のJSでNumber()変換や丸め戦略を統一しておきます（意図的仕様） n8n Docs。

3) ビューと読み取り専用アクセス
分析者にはベース表への権限を与えず、SQL SECURITY DEFINERのビュー経由で提供します（行/列の最小権限）。権限はロール単位で管理します MySQL Developer Zone+1。

CREATE VIEW v_ocean_daily AS
SELECT user_id, date, O_T, C_T, E_T, A_T, N_T
FROM ocean_timeseries;
GRANT SELECT ON v_ocean_daily TO analyst_reader;

4) トランザクションと再実行（堅牢化）
* 既定の隔離レベルはREPEATABLE READ。必要ならセッションでREAD COMMITTEDに切替（ロック競合回避） MySQL Developer Zone+1。
* イデンポテンシキーでn8nの再試行が安全になります（重複INSERTをUNIQUE制約で弾き、同じレスポンスを返す設計がベストプラクティス） Stripe。

5) 監査・ログ・プライバシー
* 何を（入力/出力/選定根拠）いつ（時刻）誰が（サービスID/ロール）行ったかを監査ログに記録。OWASPのロギング・チートシートに従い、セキュアに保存（改ざん防止・アクセス制御） OWASP チートシートシリーズ。
* GDPRのデータ最小化に合わせ、PIIは極力保持しない／ハッシュ化、保持期間を明記して削除ジョブを運用します GDPR+1。

6) スキーマ変更（移行ツール）
本番稼働後の変更は手運用禁止。Flywayなどのマイグレーションツールでバージョン管理＆CI実行します（migrate/validate/infoの標準コマンド） brunomendola.github.io+1。

初心者向けの設計チェックリスト（不変条件の例）
1. 単位の一貫性：scale_type∈{'T','p01'}、p01∈[0,1]、T∈[0,100]（CHECK） MySQL Developer Zone
2. 参照の一貫性：全FKがusers等と結び、ON DELETE方針を明文化。
3. 追記専用：ocean_timeseriesは権限でUPDATE/DELETE不可＋トリガで二重防御（SIGNAL） MySQL Developer Zone
4. 二重処理防止：behavior_events.idempotency_key UNIQUE（Stripe等が推奨） Stripe
5. 監査可能：OWASPのガイドに沿ったセキュアロギング（不可欠イベントと保存方針） OWASP チートシートシリーズ

受け入れ基準（例）
* 整合性：制約違反のデータ（p01=-0.1等）がINSERT/UPDATEで必ず拒否される（CHECK動作） MySQL Developer Zone
* 追記専用：ocean_timeseriesへのUPDATE/DELETEは権限で拒否、万一届いてもトリガがSQLSTATE '45000'で失敗する MySQL Developer Zone
* 再試行安全：同じidempotency_keyでの再送はUNIQUE違反で副作用ゼロ、APIは前回結果を返す（設計書に手順） martinfowler.com
* 最小権限：analyst_readerはビューのみ参照可、ベース表には権限なし（ロール運用） MySQL Developer Zone
* プライバシー：GDPRの最小化＆保持期間が文書化され、削除ジョブが定期実行される GDPR

よくある落とし穴 → こう避ける
* CHECKが効かない古いバージョン：MySQL 8.0.16+で強制されます。バージョンを確認し、NOT ENFORCEDを誤用しない MySQL Developer Zone。
* アプリ側だけで制御：DB制約＋権限＋トリガで二重・三重防御に。
* ログ不備：OWASPのロギング・チートシートに列挙のイベント種別・安全な保存先を準拠 OWASP チートシートシリーズ。
* 数値型の丸め事故：n8nはDECIMAL→文字列で返す仕様。変換関数と小数点扱いを共通化する n8n Docs。

整合性チェック（5回）
1. DB機能で強制できる不変条件（CHECK/UNIQUE/FK/権限/トリガ）と、求める制御（値域・追記専用・一意性）が一対一に対応。OK（CHECK/トリガ/ロールの一次資料に整合）。MySQL Developer Zone+2MySQL Developer Zone+2
2. 再実行時の安全性はIdempotency-Key＋UNIQUEで担保し、分散/再試行のベストプラクティスに沿う。OK。Stripe
3. 並行性の前提（InnoDBの既定はREPEATABLE READ、必要ならREAD COMMITTEDへ）を明記。OK。MySQL Developer Zone+1
4. ログとプライバシーはOWASPロギングとGDPR最小化に準拠。OK。OWASP チートシートシリーズ+1
5. 移行運用はFlyway等のマイグレーションで一元管理（手運用禁止）。OK。brunomendola.github.io+1

必要なら、このHモジュールのDDL一式（CHECK/ロール/トリガ/ビュー）、Flywayマイグレーション雛形、**監査ログのフィールド設計（OWASP準拠）**まで、このまますぐお渡しできます。
