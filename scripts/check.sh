#!/usr/bin/env bash
# =============================================================
# scripts/check.sh — 公開前チェック(CLAUDE.md 手順5で必須)
#
# 検査内容(対象: docs/):
#   (1) 内部リンク切れ(href/src の相対パスが実在するか)
#   (2) {{}} プレースホルダの残存(templates/ は対象外)
#   (3) docs/issues/**/*.html と index.html・map.html の網羅性
#       (issues にあるのに index/map からリンクされていないページを警告)
#   (4) 課題ページの ●(緊急度・深刻度)が各5個ちょうどか
#   (5) 出典セクションを持たない課題ページの警告
#
# すべてOKなら exit 0、NGが1つでもあれば exit 1
# =============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$ROOT/docs"
FAIL=0

ok() { printf 'OK  %s\n' "$1"; }
ng() { printf 'NG  %s\n' "$1"; FAIL=1; }

if [ ! -d "$DOCS" ]; then
  ng "docs/ が見つかりません: $DOCS"
  exit 1
fi

# ---------------------------------------------------------
echo "== (1) 内部リンク切れ検査 =="
broken=0
while IFS= read -r file; do
  dir="$(dirname "$file")"
  while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*|tel:*|data:*|javascript:*|'#'*|'') continue ;;
    esac
    path="${link%%#*}"
    path="${path%%\?*}"
    [ -z "$path" ] && continue
    # サイト絶対パス(GitHub Pages: /yokosuka-todo/ 配下)は docs/ 起点で解決
    # (404.html はどのパスでも表示されるため絶対パスが正当)
    case "$path" in
      /yokosuka-todo/*|/yokosuka-todo)
        target="$DOCS/${path#/yokosuka-todo}"
        target="${target%/}"
        ;;
      /*)
        echo "    サイト外の絶対パス: ${file#"$ROOT"/} -> $link"
        broken=1
        continue
        ;;
      *)
        target="$dir/$path"
        ;;
    esac
    # ディレクトリを指す場合は index.html の存在を確認
    if [ -d "$target" ]; then
      target="$target/index.html"
    fi
    if [ ! -e "$target" ]; then
      echo "    リンク切れ: ${file#"$ROOT"/} -> $link"
      broken=1
    fi
  done < <(grep -oE '(href|src)="[^"]*"' "$file" 2>/dev/null | sed -E 's/^(href|src)="//; s/"$//')
done < <(find "$DOCS" -name '*.html' | sort)
if [ "$broken" -eq 0 ]; then
  ok "内部リンク切れなし"
else
  ng "内部リンク切れがあります"
fi

# ---------------------------------------------------------
echo "== (2) {{}} プレースホルダ検査(docs/ のみ) =="
placeholders="$(grep -rn '{{' "$DOCS" --include='*.html' 2>/dev/null || true)"
if [ -z "$placeholders" ]; then
  ok "プレースホルダの残存なし"
else
  echo "$placeholders" | sed -e "s|^$ROOT/|    |"
  ng "{{}} プレースホルダが残っています"
fi

# ---------------------------------------------------------
echo "== (3) index.html・map.html の網羅性検査 =="
coverage_ng=0
while IFS= read -r file; do
  rel="${file#"$DOCS"/}"   # 例: issues/economy/oppama-factory.html
  if ! grep -q "href=\"$rel\"" "$DOCS/index.html"; then
    echo "    index.html に未掲載: $rel"
    coverage_ng=1
  fi
  if ! grep -q "href=\"$rel\"" "$DOCS/map.html"; then
    echo "    map.html に未掲載: $rel"
    coverage_ng=1
  fi
done < <(find "$DOCS/issues" -name '*.html' | sort)
if [ "$coverage_ng" -eq 0 ]; then
  ok "全課題ページが index.html・map.html に掲載済み"
else
  ng "index.html / map.html に未掲載の課題ページがあります"
fi

# ---------------------------------------------------------
echo "== (4) 緊急度・深刻度の●(計5個)検査 =="
dots_ng=0
while IFS= read -r file; do
  result="$(perl -CSD -Mutf8 -0777 -ne '
    while (/<dt>(緊急度|深刻度)<\/dt>\s*<dd[^>]*class="dots"[^>]*>(.*?)<\/dd>/gs) {
      my ($label, $body) = ($1, $2);
      $body =~ s/<[^>]*>//g;
      my $n = () = $body =~ /[●○]/g;
      print "$label $n\n";
    }
  ' "$file")"
  for label in 緊急度 深刻度; do
    count="$(printf '%s\n' "$result" | awk -v l="$label" '$1==l {print $2; exit}')"
    if [ -z "$count" ]; then
      echo "    ${file#"$DOCS"/}: ${label}の表記(class=\"dots\")が見つかりません"
      dots_ng=1
    elif [ "$count" -ne 5 ]; then
      echo "    ${file#"$DOCS"/}: ${label}の●○が計${count}個(5個であるべき)"
      dots_ng=1
    fi
  done
done < <(find "$DOCS/issues" -name '*.html' | sort)
if [ "$dots_ng" -eq 0 ]; then
  ok "全課題ページで緊急度・深刻度とも計5個"
else
  ng "●の個数が5個でないページがあります"
fi

# ---------------------------------------------------------
echo "== (5) 出典セクション検査 =="
sources_ng=0
while IFS= read -r file; do
  if ! grep -qE '<h2[^>]*>[^<]*出典' "$file"; then
    echo "    出典セクションなし: ${file#"$DOCS"/}"
    sources_ng=1
  fi
done < <(find "$DOCS/issues" -name '*.html' | sort)
if [ "$sources_ng" -eq 0 ]; then
  ok "全課題ページに出典セクションあり"
else
  ng "出典セクションを持たない課題ページがあります"
fi

# ---------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  echo "すべての検査をパスしました"
else
  echo "NGの検査があります。修正してから再実行してください"
fi
exit "$FAIL"
