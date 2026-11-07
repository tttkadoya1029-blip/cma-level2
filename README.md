# CMA 2次 正誤チャレンジ

証券アナリスト第2次レベル（市場と経済の分析・コーポレート・ファイナンス・財務分析）の
**オリジナル正誤問題100問**に本番形式で挑戦するWebアプリです。

- **本番モード**：1問ごとに解答時間を計測。正誤と解説は最後にまとめて表示。途中で終了してそこまでを採点することもできる
- **科目が分かる**：各問題に科目・回・テキストの学習ポイント番号・難易度を表示
- **難問に挑戦するか選べる**：標準64問／難問36問。科目もしぼれる
- **問題数を選べる**：10・20・30・50問・すべて、または好きな数を入力。範囲内からランダムに出題
- **会員登録**：ニックネーム・お名前・メールアドレス（Googleログインまたはメール＋パスワード）
- **自分の記録**：科目別の正答率と時間（中央値）をみんなと比較、苦手な学習ポイント、過去の挑戦の振り返り
- **講師用分析**：受講者一覧（偏差値）、科目×受講者、問題別正答率、個別の指導優先順位、CSV書き出し

## 問題の内訳（100問）
| 科目 | 回 | 問題数 |
|---|---|---|
| 市場と経済の分析 | 第1回〜第4回 | 45 |
| コーポレート・ファイナンス | 第1回・第2回 | 22 |
| 財務分析 | 第1回〜第3回 | 33 |

標準64問（○32・×32）、難問36問（○18・×18）。問題文はすべてオリジナルで、テキスト（2025年度版）の本文と照合して作成しています。

## セットアップ（専用のSupabaseプロジェクト：jmwshxdrxzvgsswupamx）
`config.js` には接続情報（プロジェクトURLと publishable key）が入っています。publishable key は公開して問題ない鍵です。

1. Supabase の **SQL Editor** で `supabase/schema.sql` を実行し、続けて `supabase/seed.sql` を実行（100問が入ります）
2. **Authentication → Sign In / Providers → Email** で「Confirm email」をオフ（標準のメール送信は1時間に数通までのため）
3. Vercel で「Add New → Project」からこのリポジトリを Import → Deploy
4. **Authentication → URL Configuration** の Site URL と Redirect URLs に、Vercel のURLを入力
5. Googleログインを使う場合：このプロジェクトの **Authentication → Sign In / Providers → Google** にクライアントIDとシークレットを入力し、
   Google Cloud 側の「承認済みのリダイレクトURI」に `https://jmwshxdrxzvgsswupamx.supabase.co/auth/v1/callback` を追加
6. 公開URLで一度ログインして会員登録したあと、SQL Editor で自分を講師にする：
   ```sql
   update public.l2_members set role = 'teacher' where email = 'あなたのメールアドレス';
   ```

## アップデートしたとき
データベースの仕組みを変えた場合は、SQL Editor で `supabase/schema.sql` をもう一度実行してください（何度実行しても大丈夫で、記録は消えません）。

## 問題を追加・修正するには
`tools/questions.py` を編集して `python3 tools/build_seed.py` を実行し、できた `supabase/seed.sql` を SQL Editor で実行します。
同じIDの問題は上書きされ、過去の解答記録は残ります。

## スマホ表示の確認（開発者向け）
`node dev/check-mobile.js` で、iPhone SE・iPhone 15・小さめのAndroid・PCの幅で全画面を自動操作し、
横はみ出しやエラーがないか確認して `dev/screens/` にスクリーンショットを保存します（Playwright が必要）。
