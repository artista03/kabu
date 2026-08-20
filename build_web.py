#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
父の持ち株ページ ― データ生成

株探から34銘柄の株価と配当利回りを取得し、2つのファイルを書き出す。

  docs/public.json  … 公開してよい情報だけ（銘柄名・株価・前日比・全体の騰落率）
  _secret.json      … 金額を含む機密情報。encrypt.mjs で暗号化してから公開する
                       （このファイル自体は .gitignore で除外され、リポジトリに入らない）

保有データ（holdings.json）は環境変数 HOLDINGS_JSON（base64）から読む。
ローカル実行時は同じフォルダの holdings.json を読む。
"""

import base64
import datetime
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(BASE, "docs")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
NUM = r"([\d,]+(?:\.\d+)?)"
KABUTAN_REF = {"^N225": "0000"}


# ------------------------------------------------------------ 取得

def num(s):
    try:
        return float(str(s).replace(",", ""))
    except (ValueError, AttributeError):
        return None


def strip_tags(x):
    return re.sub(r"<[^>]*>", "", x)


def get_html(url, timeout=20):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
        "Accept-Language": "ja,en-US;q=0.9",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(400000).decode("utf-8", "ignore")


def table_metric(html, label, lo=None, hi=None):
    """<th>…label…</th> が何列目かを数え、続く行の同じ列の <td> を読む。"""
    for tm in re.finditer(r"<table[^>]*>([\s\S]{0,6000}?)</table>", html):
        t = tm.group(1)
        ths = re.findall(r"<th[^>]*>([\s\S]*?)</th>", t)
        idx = None
        for i, th in enumerate(ths):
            if label in strip_tags(th):
                idx = i
                break
        if idx is None:
            continue
        for row in re.findall(r"<tr[^>]*>([\s\S]*?)</tr>", t):
            tds = re.findall(r"<td[^>]*>([\s\S]*?)</td>", row)
            if len(tds) > idx:
                v = num(re.sub(r"[^\d.]", "", strip_tags(tds[idx])))
                if v is not None and (lo is None or v >= lo) and (hi is None or v <= hi):
                    return v
    return None


def kabutan(sym, tries=2):
    code = KABUTAN_REF.get(sym) or (sym[:-2] if sym.endswith(".T") else sym)
    url = "https://kabutan.jp/stock/?code=%s" % urllib.parse.quote(code)
    for attempt in range(tries):
        try:
            html = get_html(url)
        except Exception:
            time.sleep(1.5 * (attempt + 1))
            continue
        m = re.search(r'class="kabuka"[^>]*>' + NUM, html)
        price = num(m.group(1)) if m else None
        prev = None
        m = re.search(r"前日終値</dt>\s*<dd[^>]*>" + NUM, html)
        if not m:
            m = re.search(r"前日終値[\s\S]{0,160}?" + NUM, html)
        if m:
            prev = num(m.group(1))
        if not (price and prev and prev > 0):
            time.sleep(1.0)
            continue
        return {"price": price, "prev": prev,
                "ypct": table_metric(html, "利回り", 0.0, 15.0)}
    return None


# ------------------------------------------------------------ 本体

def load_holdings():
    b64 = os.environ.get("HOLDINGS_JSON", "").strip()
    if b64:
        return json.loads(base64.b64decode(b64).decode("utf-8"))
    p = os.path.join(BASE, "holdings.json")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    sys.exit("holdings.json が見つかりません（環境変数 HOLDINGS_JSON も未設定）")


def main():
    cfg = load_holdings()
    holdings = cfg["holdings"]

    quotes = {}
    print("株探から %d 銘柄を取得します" % (len(holdings) + 1))
    for i, h in enumerate(holdings, 1):
        q = kabutan(h["code"] + ".T")
        if q:
            quotes[h["code"]] = q
            print("  %2d/%d  %s %s  %s円" % (i, len(holdings), h["code"],
                                             h["name"][:14], "{:,.1f}".format(q["price"])))
        else:
            print("  %2d/%d  %s %s  ×" % (i, len(holdings), h["code"], h["name"][:14]))
        time.sleep(0.6)
    n225 = kabutan("^N225")

    pub_stocks, sec_stocks = [], []
    total = total_prev = total_cost = total_base = div_year = 0.0
    n_div = 0

    for h in holdings:
        q = quotes.get(h["code"])
        if not q:
            continue
        shares = h.get("shares") or (h["eval_man"] * 10000.0 / h["ref_price"])
        value = shares * q["price"]
        prev_value = shares * q["prev"]
        ypct = h.get("yield_pct", q.get("ypct"))
        div = value * ypct / 100.0 if ypct else 0.0
        if ypct:
            n_div += 1

        total += value
        total_prev += prev_value
        total_cost += h["cost_man"] * 10000.0
        total_base += h["eval_man"] * 10000.0
        div_year += div

        pub_stocks.append({
            "code": h["code"], "name": h["name"],
            "price": round(q["price"], 1),
            "chg": round((q["price"] / q["prev"] - 1) * 100, 2),
        })
        sec_stocks.append({
            "code": h["code"],
            "value": round(value),
            "day": round(value - prev_value),
            "unreal": round(value - h["cost_man"] * 10000.0),
            "ypct": round(ypct, 2) if ypct else None,
            "div": round(div) if div else None,
        })

    if not pub_stocks:
        sys.exit("株価がひとつも取れませんでした")

    pub_stocks.sort(key=lambda s: s["chg"], reverse=True)
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9)))

    public = {
        "updated": now.strftime("%Y-%m-%d %H:%M"),
        "portfolio_chg": round((total / total_prev - 1) * 100, 2),
        "n225": ({"price": round(n225["price"]),
                  "chg": round((n225["price"] / n225["prev"] - 1) * 100, 2)}
                 if n225 else None),
        "count": len(pub_stocks),
        "stocks": pub_stocks,
    }

    secret = {
        "updated": public["updated"],
        "total": round(total),
        "day": round(total - total_prev),
        "since_base": round(total - total_base),
        "unreal": round(total - total_cost),
        "cost": round(total_cost),
        "div_year": round(div_year),
        "div_net": round(div_year * 0.79685),
        "yoc": round(div_year / total_cost * 100, 2) if total_cost else 0,
        "ycur": round(div_year / total * 100, 2) if total else 0,
        "n_div": n_div,
        "n_total": len(pub_stocks),
        "stocks": sec_stocks,
    }

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "public.json"), "w", encoding="utf-8") as f:
        json.dump(public, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(BASE, "_secret.json"), "w", encoding="utf-8") as f:
        json.dump(secret, f, ensure_ascii=False, separators=(",", ":"))

    print("")
    print("  評価額   %s円" % "{:,.0f}".format(total))
    print("  今日     %s円 (%+.2f%%)" % ("{:+,.0f}".format(total - total_prev),
                                          public["portfolio_chg"]))
    print("  年間配当 %s円（%d/%d銘柄）" % ("{:,.0f}".format(div_year), n_div, len(pub_stocks)))
    print("")
    print("  docs/public.json と _secret.json を書き出しました")


if __name__ == "__main__":
    main()
