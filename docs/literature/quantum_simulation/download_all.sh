#!/bin/bash
# Download ALL quantum simulation papers for Sturm.jl literature survey.
# Run from the repo root: bash docs/literature/quantum_simulation/download_all.sh
#
# Phase 1: arXiv papers (no VPN needed, ~95 PDFs)
# Phase 2: Paywalled papers (needs TIB VPN + headed Playwright browser)
#
# For Phase 2, ensure:
#   1. TIB VPN is active
#   2. Node.js + Playwright available (use existing install in ../qvls-sturm/viz/node_modules/)
#   3. Run: node docs/literature/quantum_simulation/fetch_paywalled.mjs

set -euo pipefail
BASE="docs/literature/quantum_simulation"

echo "=== Phase 1: arXiv papers (no VPN needed) ==="
echo ""

# All arXiv IDs extracted from the 8 survey.md files
ARXIV_IDS="
0811.3171 1003.3683 1202.5822 1304.3061 1312.1414 1403.1539 1406.4920
1411.4028 1412.4687 1501.01715 1509.04279 1512.06860 1606.02685
1610.06546 1611.09301 1612.01011 1704.05018 1709.03489 1711.10980
1712.09271 1801.03922 1803.11173 1805.00582 1805.00675 1805.03662
1805.08385 1806.01838 1806.11123 1807.09802 1808.05225 1810.02327
1811.08017 1812.08767 1812.08778 1812.11173 1901.00564 1901.07653
1902.02134 1902.10673 1906.07115 1909.02108 1910.06255 1911.10205
1912.05559 1912.08854 1912.11047 2001.00550 2002.12508 2008.02941
2008.11751 2011.00622 2012.09265 2012.09194 2101.07808 2105.12767
2105.14377 2107.08032 2109.03308 2110.04993 2110.12071 2111.05176
2111.05324 2202.02671 2204.05955 2205.00081 2205.06261 2206.06409
2209.10162 2211.02691 2211.09133 2212.05952 2302.14811 2303.01029
2303.05533 2306.10603 2306.12569 2306.16572 2312.08044 2402.05595
2407.15357 2408.11683 2409.03744 2410.03059 2411.06485 2503.05647
2509.08030 2602.00555 2603.29857 quant-ph/0508139
1001.3855
"

# Category mapping: each paper goes to the FIRST survey that mentions it
CATEGORIES="product_formulas randomized_methods lcu_taylor_series qsp_qsvt quantum_walks variational_hybrid applications_chemistry surveys_complexity"

OK=0; FAIL=0; SKIP=0

for id in $ARXIV_IDS; do
    safe_id="${id//\//_}"

    # Find which category mentions this ID
    cat_dir=""
    for cat in $CATEGORIES; do
        if grep -q "$id" "$BASE/$cat/survey.md" 2>/dev/null; then
            cat_dir="$BASE/$cat"
            break
        fi
    done
    [ -z "$cat_dir" ] && cat_dir="$BASE/uncategorized" && mkdir -p "$cat_dir"

    outpath="$cat_dir/${safe_id}.pdf"

    if [ -f "$outpath" ] && [ "$(stat -c%s "$outpath" 2>/dev/null || echo 0)" -gt 10000 ]; then
        SKIP=$((SKIP+1))
        continue
    fi

    echo -n "FETCH $id -> $(basename "$cat_dir")/ ... "
    code=$(curl -sS -L -o "$outpath" -w "%{http_code}" \
        -H "User-Agent: Sturm.jl-research/1.0" \
        --connect-timeout 15 --max-time 120 \
        "https://arxiv.org/pdf/${id}" 2>/dev/null)

    if [ "$code" = "200" ] && file -b "$outpath" 2>/dev/null | grep -q "^PDF"; then
        echo "OK ($(stat -c%s "$outpath") bytes)"
        OK=$((OK+1))
    else
        echo "FAIL (HTTP $code)"
        rm -f "$outpath"
        FAIL=$((FAIL+1))
    fi
    sleep 3
done

echo ""
echo "arXiv: $OK downloaded, $FAIL failed, $SKIP skipped"
echo ""

# Create cross-category symlinks
echo "=== Creating cross-category symlinks ==="
for cat in $CATEGORIES; do
    survey="$BASE/$cat/survey.md"
    [ -f "$survey" ] || continue
    for id in $(grep -ohP 'arxiv\.org/abs/\K[^\s\)]+' "$survey" 2>/dev/null | sed 's/[).,]$//' | sort -u); do
        safe_id="${id//\//_}"
        target="$BASE/$cat/${safe_id}.pdf"
        [ -f "$target" ] && continue  # already has real file
        [ -L "$target" ] && continue  # already has symlink
        # Find the real file in other categories
        for other_cat in $CATEGORIES; do
            real="$BASE/$other_cat/${safe_id}.pdf"
            if [ -f "$real" ] && [ ! -L "$real" ]; then
                ln -s "../$other_cat/${safe_id}.pdf" "$target"
                break
            fi
        done
    done
done
echo "Done."

echo ""
echo "=== Phase 2: Paywalled papers (TIB VPN required) ==="
echo "Run manually:"
echo "  1. Connect to TIB VPN"
echo "  2. node docs/literature/quantum_simulation/fetch_paywalled.mjs"
echo "  (Uses headed Chromium browser, click through Cloudflare challenges)"
echo ""
echo "The fetch_paywalled.mjs script downloads 6 pre-arXiv papers:"
echo "  - Trotter 1959 (JSTOR)"
echo "  - Feynman 1982 (Springer)"
echo "  - Suzuki 1985 (AIP)"
echo "  - Suzuki 1990 (Elsevier)"
echo "  - Suzuki 1991 (chaosbook.org, free)"
echo "  - Lloyd 1996 (MIT, free)"
