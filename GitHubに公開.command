#!/bin/bash
# これ1本で、GitHubへの公開までを全部やる。
#   リポジトリ作成 → push → Secret登録 → Pages有効化 → 初回実行 → URL表示
set -u
cd "$(dirname "$0")" || exit 1
clear

REPO="kabu"

say()  { printf "  %s\n" "$1"; }
head2(){ printf "\n  %s\n  %s\n" "$1" "----------------------------------------------"; }
die()  { printf "\n  ⛔ %s\n\n" "$1"; read -r -p "  Enterで閉じます " _; exit 1; }

printf "\n  父の持ち株ページを GitHub に公開します\n"
printf "  ==============================================\n"

# ---------------------------------------------- 0. 前提チェック
command -v gh  >/dev/null || die "gh コマンドがありません。ターミナルで  brew install gh  を実行してください。"
command -v git >/dev/null || die "git コマンドがありません。"
[ -f holdings.json ] || die "holdings.json がありません。"
[ -f docs/index.html ] || die "docs/index.html がありません。"

head2 "① GitHubへのログイン確認"
if gh auth status >/dev/null 2>&1; then
  say "✅ ログイン済み（$(gh api user -q .login 2>/dev/null)）"
else
  say "ログインしていません。ブラウザが開きます。"
  say "画面の指示に従ってGitHubにログインしてください。"
  gh auth login -h github.com -p https -w || die "ログインできませんでした。"
fi
OWNER="$(gh api user -q .login)" || die "ユーザー名を取得できませんでした。"

# ---------------------------------------------- 1. あいことば
head2 "② あいことばを決める"
say "父に教える合言葉です。半角英数で12文字くらい。"
say "（画面には表示されません）"
printf "\n  あいことば: "
read -rs PW; printf "\n"
[ ${#PW} -ge 4 ] || die "4文字以上にしてください。"
printf "  もう一度   : "
read -rs PW2; printf "\n"
[ "$PW" = "$PW2" ] || die "2回の入力が一致しませんでした。"
say "✅ 受け付けました"

# ---------------------------------------------- 2. ローカルのGit
head2 "③ ファイルをまとめる"
if [ ! -d .git ]; then
  git init -b main -q || die "git init に失敗しました。"
fi
git add -A || die "git add に失敗しました。"

# ★安全確認：機密ファイルが混ざっていたら、ここで必ず止める
LEAK="$(git ls-files --cached | grep -E '^(holdings\.json|_secret\.json|dump_kabutan.*\.html)$' || true)"
if [ -n "$LEAK" ]; then
  die "機密ファイルが混ざっています → $LEAK  .gitignore を確認してください。中止しました。"
fi
say "✅ 機密ファイル（holdings.json / _secret.json）は除外されています"
say "   公開されるファイル: $(git ls-files --cached | wc -l | tr -d ' ') 件"

git -c user.name="$OWNER" -c user.email="$OWNER@users.noreply.github.com" \
    commit -q -m "父の持ち株ページ" 2>/dev/null || say "   （変更なし）"

# ---------------------------------------------- 3. リポジトリ作成とpush
head2 "④ GitHubにアップロードする"
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  say "リポジトリ $OWNER/$REPO は既にあります。そこへ送ります。"
  git remote get-url origin >/dev/null 2>&1 || \
    git remote add origin "https://github.com/$OWNER/$REPO.git"
  git push -u origin main || die "push に失敗しました。"
else
  gh repo create "$REPO" --public --source=. --remote=origin --push \
     --description "持ち株のようす（自動更新）" || die "リポジトリの作成に失敗しました。"
fi
say "✅ https://github.com/$OWNER/$REPO"

# ---------------------------------------------- 4. Secret登録
head2 "⑤ 保有データと合言葉を登録する"
base64 -i holdings.json | tr -d '\n' | gh secret set HOLDINGS_JSON -R "$OWNER/$REPO" \
  || die "HOLDINGS_JSON の登録に失敗しました。"
say "✅ HOLDINGS_JSON"
printf '%s' "$PW" | gh secret set VIEW_PASSWORD -R "$OWNER/$REPO" \
  || die "VIEW_PASSWORD の登録に失敗しました。"
say "✅ VIEW_PASSWORD"

# ---------------------------------------------- 5. Pages有効化
head2 "⑥ ページを公開状態にする"
if gh api "repos/$OWNER/$REPO/pages" >/dev/null 2>&1; then
  gh api --method PUT "repos/$OWNER/$REPO/pages" \
     -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
     && say "✅ 設定を更新しました" || say "△ 既存の設定をそのまま使います"
else
  gh api --method POST "repos/$OWNER/$REPO/pages" \
     -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
     && say "✅ 公開しました" \
     || say "△ 自動設定できませんでした。あとで Settings → Pages で main / docs を選んでください。"
fi

# ---------------------------------------------- 6. 初回実行
head2 "⑦ 株価の自動更新を1回走らせる"
sleep 3
if gh workflow run update.yml -R "$OWNER/$REPO" >/dev/null 2>&1; then
  say "✅ 実行を開始しました（2〜3分かかります）"
else
  say "△ 自動起動できませんでした。Actions タブから手動で回してください。"
fi

# ---------------------------------------------- 7. 完了
URL="https://$OWNER.github.io/$REPO/"
printf "\n  ==============================================\n"
printf "  完了しました\n\n"
printf "  ページ  %s\n" "$URL"
printf "  設定    https://github.com/%s/%s/actions\n\n" "$OWNER" "$REPO"
printf "  ★ 次にやること\n"
printf "    1. 3分ほど待つ（初回の公開に時間がかかります）\n"
printf "    2. 上のページを自分で開く\n"
printf "    3. 更新時刻が今日の新しい時刻になっているか見る\n"
printf "    4. あいことばを入れて、金額が出るか確かめる\n"
printf "    5. それができてから、父にURLと合言葉を送る\n\n"
printf "  ==============================================\n\n"
read -r -p "  Enterでブラウザを開きます " _
open "$URL"
