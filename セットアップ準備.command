#!/bin/bash
# GitHubに登録する2つのSecretを用意する。
cd "$(dirname "$0")" || exit 1
clear
echo ""
echo "  GitHub Secrets の準備"
echo "  =============================================="
echo ""

if [ ! -f holdings.json ]; then
  echo "  holdings.json がありません。"
  echo "  ../株ウォッチ/holdings.json をこのフォルダにコピーしてください。"
  echo ""
  exit 1
fi

base64 -i holdings.json | tr -d '\n' | pbcopy
echo "  ① HOLDINGS_JSON をクリップボードにコピーしました。"
echo ""
echo "     GitHubのリポジトリで"
echo "       Settings → Secrets and variables → Actions → New repository secret"
echo "     を開き、"
echo "       Name  : HOLDINGS_JSON"
echo "       Secret: ⌘V で貼り付け"
echo "     で保存してください。"
echo ""
read -r -p "  保存できたら Enter を押してください… " _
echo ""
echo "  ② もうひとつ、同じ画面で作ります。"
echo ""
echo "       Name  : VIEW_PASSWORD"
echo "       Secret: 父に教えるあいことば（4文字以上・推測されにくいもの）"
echo ""
echo "     ※ このあいことばを知っている人だけが金額を見られます。"
echo "     ※ 変更したら、ワークフローを1回手動で回してください。"
echo ""
read -r -p "  保存できたら Enter を押してください… " _
echo ""
echo "  ③ 最後に Pages を有効にします。"
echo ""
echo "       Settings → Pages"
echo "       Source : Deploy from a branch"
echo "       Branch : main  /  フォルダ: /docs   → Save"
echo ""
echo "  ④ Actions タブ →「株価を更新」→ Run workflow を1回押す。"
echo "     2〜3分で   https://<ユーザー名>.github.io/<リポジトリ名>/   が出来ます。"
echo ""
echo "  =============================================="
echo ""
