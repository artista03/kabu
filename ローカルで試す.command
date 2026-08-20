#!/bin/bash
# GitHubに上げる前に、手元で動かして見た目を確認する。
cd "$(dirname "$0")" || exit 1
clear
echo ""
echo "  ローカル確認"
echo "  ----------------------------------------------"
echo ""

if [ ! -f holdings.json ]; then
  echo "  holdings.json がありません。"
  echo "  ../株ウォッチ/holdings.json をこのフォルダにコピーしてください。"
  echo ""
  exit 1
fi

read -r -p "  あいことば（父に教えるもの）: " PW
if [ ${#PW} -lt 4 ]; then
  echo "  4文字以上にしてください。"
  exit 1
fi
echo ""

python3 build_web.py || exit 1
VIEW_PASSWORD="$PW" node encrypt.mjs || exit 1

echo ""
echo "  ブラウザを開きます。閉じるときはこの画面で Control + C 。"
echo ""
sleep 1
( sleep 1; open "http://localhost:8765/" ) &
cd docs && python3 -m http.server 8765
