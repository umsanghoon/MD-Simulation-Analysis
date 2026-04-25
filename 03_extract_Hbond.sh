#!/bin/bash
set -euo pipefail

# ============================================================
# [커맨드 3] Hydrogen bond 추출 스크립트
#
# 현재 폴더명 규칙:
#   2026-04-20_NPG6-4_r1
#   2026-04-20_NPG6-4_A3a_r1
#
# 출력 파일:
#   2026-04-20_NPG6-4_r1_Hbond.csv
#   2026-04-20_NPG6-4_A3a_r1_Hbond.csv
#
# 계산 항목:
#   all       = 전체 protein H-bond
#   intra_A   = chain A 내부 H-bond
#   intra_B   = chain B 내부 H-bond
#   intra_C   = chain C 내부 H-bond
#   inter_AB  = chain A - chain B 사이 H-bond
#   inter_AC  = chain A - chain C 사이 H-bond
#   inter_BC  = chain B - chain C 사이 H-bond
# ============================================================

FOLDER=$(basename "$PWD")

DATE=$(echo "$FOLDER" | cut -d'_' -f1)
REP=$(echo "$FOLDER" | grep -oE 'r[0-9]+$')

if [ -z "$REP" ]; then
    echo "❌ 오류: 폴더명 끝에서 replicate 번호(r1, r2 등)를 찾지 못했습니다."
    echo "현재 폴더명: $FOLDER"
    exit 1
fi

STRUCTURE="${FOLDER#${DATE}_}"
STRUCTURE="${STRUCTURE%_${REP}}"

OUTFILE="${DATE}_${STRUCTURE}_${REP}_Hbond.csv"

echo "▶ 현재 폴더 : $FOLDER"
echo "▶ 날짜      : $DATE"
echo "▶ 구조 이름 : $STRUCTURE"
echo "▶ Replicate : $REP"
echo "▶ 출력 파일 : $OUTFILE"
echo ""

CMS_FILE="test-out.cms"

HB="$SCHRODINGER/run /libs/Schrodinger_Suites_2026-1_Advanced_Linux-x86_64/mmshare-v7.3/python/common/trajectory_analyze_hbonds.py"

if [ ! -f "$CMS_FILE" ]; then
    echo "❌ 오류: $CMS_FILE 파일이 현재 폴더에 없습니다."
    exit 1
fi

TMPDIR="_tmp_hbond_${$}"
mkdir -p "$TMPDIR"

echo "▶ H-bond 개별 항목 계산 시작"

$HB "$CMS_FILE" "$TMPDIR/all.csv" "protein"
echo "  → all 완료"

$HB "$CMS_FILE" "$TMPDIR/intra_A.csv" "chain A"
echo "  → intra_A 완료"

$HB "$CMS_FILE" "$TMPDIR/intra_B.csv" "chain B"
echo "  → intra_B 완료"

$HB "$CMS_FILE" "$TMPDIR/intra_C.csv" "chain C"
echo "  → intra_C 완료"

$HB -asl2 "chain B" "$CMS_FILE" "$TMPDIR/inter_AB.csv" "chain A"
echo "  → inter_AB 완료"

$HB -asl2 "chain C" "$CMS_FILE" "$TMPDIR/inter_AC.csv" "chain A"
echo "  → inter_AC 완료"

$HB -asl2 "chain C" "$CMS_FILE" "$TMPDIR/inter_BC.csv" "chain B"
echo "  → inter_BC 완료"

# ============================================================
# 개별 csv들을 하나의 최종 csv로 병합
#
# 최종 출력 형태:
#   frame,all,intra_A,intra_B,intra_C,inter_AB,inter_AC,inter_BC
# ============================================================

cat > "$TMPDIR/merge_hbond.py" <<'PY'
import csv
import os

tmpdir = os.environ["TMPDIR_HB"]
outfile = os.environ["OUTFILE_HB"]

files = {
    "all": "all.csv",
    "intra_A": "intra_A.csv",
    "intra_B": "intra_B.csv",
    "intra_C": "intra_C.csv",
    "inter_AB": "inter_AB.csv",
    "inter_AC": "inter_AC.csv",
    "inter_BC": "inter_BC.csv",
}

def read_series(path):
    rows = []

    with open(path, newline="") as fh:
        reader = csv.reader(fh)

        for row in reader:
            if not row:
                continue

            first = row[0].strip().lower()

            # header 또는 단위 row 제거
            if first in ("frame", "# frame", "frame_no"):
                continue

            rows.append(row)

    series = []

    for i, row in enumerate(rows):
        # 보통 frame,value 형식
        if len(row) >= 2:
            frame = row[0].strip()
            value = row[1].strip()
        # 혹시 value only 형식이면 frame을 자동 생성
        else:
            frame = str(i)
            value = row[0].strip()

        series.append((frame, value))

    return series

data = {
    key: read_series(os.path.join(tmpdir, filename))
    for key, filename in files.items()
}

n = max(len(v) for v in data.values())

with open(outfile, "w", newline="") as fh:
    writer = csv.writer(fh)

    writer.writerow([
        "frame", "all",
        "intra_A", "intra_B", "intra_C",
        "inter_AB", "inter_AC", "inter_BC"
    ])

    for i in range(n):
        row = [str(i)]

        for key in [
            "all",
            "intra_A", "intra_B", "intra_C",
            "inter_AB", "inter_AC", "inter_BC"
        ]:
            series = data[key]

            if i < len(series):
                frame, value = series[i]
                row[0] = frame
                row.append(value)
            else:
                row.append("")

        writer.writerow(row)
PY

TMPDIR_HB="$TMPDIR" OUTFILE_HB="$OUTFILE" \
$SCHRODINGER/run python3 "$TMPDIR/merge_hbond.py"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ H-bond 분석 완료"
echo "   출력 파일 : $OUTFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

head -10 "$OUTFILE"

rm -rf "$TMPDIR"

echo "✓ 임시 파일 삭제 완료"