// _secret.json を合言葉で暗号化して docs/secret.enc に書き出す。
// 公開サーバーに置かれるのは、この暗号文だけ。復号は父のブラウザの中でしか起きない。
//
//   使い方:  VIEW_PASSWORD=あいことば node encrypt.mjs
//
// 形式: base64( salt(16) | iv(12) | ciphertext | tag(16) )
//       鍵は PBKDF2-SHA256 / 250,000回 で導出、本体は AES-256-GCM。
//       ブラウザの WebCrypto がそのまま復号できる並びにしてある。

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BASE = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(BASE, "_secret.json");
const OUT = path.join(BASE, "docs", "secret.enc");
const ITER = 250000;

const pw = process.env.VIEW_PASSWORD;
if (!pw || pw.length < 4) {
  console.error("VIEW_PASSWORD が設定されていません（4文字以上）");
  process.exit(1);
}
if (!fs.existsSync(SRC)) {
  console.error(`${SRC} がありません。先に build_web.py を実行してください`);
  process.exit(1);
}

const plain = fs.readFileSync(SRC, "utf8");
const salt = crypto.randomBytes(16);
const iv = crypto.randomBytes(12);
const key = crypto.pbkdf2Sync(pw, salt, ITER, 32, "sha256");

const c = crypto.createCipheriv("aes-256-gcm", key, iv);
const ct = Buffer.concat([c.update(plain, "utf8"), c.final()]);
const tag = c.getAuthTag();

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, Buffer.concat([salt, iv, ct, tag]).toString("base64"));

console.log(`docs/secret.enc を書き出しました（${plain.length} → ${fs.statSync(OUT).size} バイト）`);
