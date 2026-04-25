#!/bin/bash
set -euo pipefail

# ============================================================
# [커맨드 2] Rg (Radius of Gyration) 추출 스크립트
#
# 현재 폴더명 규칙:
#   2026-04-20_NPG6-4_r1
#   2026-04-20_NPG6-4_A3a_r1
#
# 출력 파일:
#   2026-04-20_NPG6-4_r1_Rg.dat
#   2026-04-20_NPG6-4_A3a_r1_Rg.dat
#
# 즉, 날짜와 replicate 사이에 들어가는 모든 이름을
# 구조 이름으로 유지한다.
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

OUTFILE="${DATE}_${STRUCTURE}_${REP}_Rg.dat"

echo "▶ 현재 폴더 : $FOLDER"
echo "▶ 날짜      : $DATE"
echo "▶ 구조 이름 : $STRUCTURE"
echo "▶ Replicate : $REP"
echo "▶ 출력 파일 : $OUTFILE"
echo ""

CMS_FILE="test-out.cms"
TRJ_DIR="test_trj"

if [ ! -f "$CMS_FILE" ]; then
    echo "❌ 오류: $CMS_FILE 파일이 현재 폴더에 없습니다."
    exit 1
fi

if [ ! -d "$TRJ_DIR" ]; then
    echo "❌ 오류: $TRJ_DIR 폴더가 현재 폴더에 없습니다."
    exit 1
fi

TMPPY="_tmp_rg_${$}.py"

cat > "$TMPPY" <<'PY'
import sys
import numpy as np
from schrodinger.application.desmond.packages import topo, traj

cms_file = sys.argv[1]
trj_dir = sys.argv[2]
out_file = sys.argv[3]

msys_model, cms_model = topo.read_cms(cms_file)
tr = traj.read_traj(trj_dir)

# protein 전체 원자 기준 Rg 계산
aids = cms_model.select_atom("protein")
if len(aids) == 0:
    raise ValueError("No atoms matched ASL: protein")

# 원자 질량 사용. 질량 정보가 없으면 1.0으로 대체
st0 = cms_model.copy()
masses = []

for i in aids:
    atom = st0.atom[i]
    mass = getattr(atom, "atomic_weight", None)
    if mass is None or mass == 0:
        mass = 1.0
    masses.append(float(mass))

masses = np.array(masses, dtype=float)

with open(out_file, "w") as fh:
    fh.write("# frame rg\n")

    for i, fr in enumerate(tr):
        st = cms_model.copy()
        topo.update_ct(st, cms_model, fr)

        xyz = np.array([st.atom[j].xyz for j in aids], dtype=float)

        # center of mass
        com = np.average(xyz, axis=0, weights=masses)

        # mass-weighted radius of gyration
        rg2 = np.sum(masses * np.sum((xyz - com) ** 2, axis=1)) / np.sum(masses)
        rg = np.sqrt(rg2)

        fh.write(f"{i} {rg:.6f}\n")
PY

$SCHRODINGER/run python3 "$TMPPY" "$CMS_FILE" "$TRJ_DIR" "$OUTFILE"

rm -f "$TMPPY"

echo "✓ 완료: $OUTFILE"