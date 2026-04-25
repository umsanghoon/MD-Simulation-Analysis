#!/bin/bash
set -euo pipefail

# ============================================================
# [커맨드 1] Desmond trajectory RMSD 추출 스크립트 - aligned version
# 작성 목적:
#   Desmond GUI의 Prot_CA RMSD와 더 유사하게,
#   매 frame을 reference structure에 C-alpha 기준으로 superposition한 뒤
#   RMSD를 계산한다.
#
# 출력 파일:
#   현재 폴더명_RMSD.dat
#   예) 2026-04-20_NPG6-4_r1_RMSD.dat
#   예) 2026-04-20_NPG6-4_A3a_r1_RMSD.dat
#
# 출력 컬럼:
#   # frame  rmsd_ca
#
# 기본 입력 파일:
#   test-out.cms  : trajectory topology/output cms
#   test_trj      : trajectory folder
#   test-in.cms   : reference structure, 있으면 이걸 기준으로 RMSD 계산
#
# 중요:
#   기존 버전은 좌표를 alignment하지 않고 단순 차이를 계산했기 때문에
#   Desmond GUI Prot_CA RMSD와 크게 달라질 수 있었다.
#   이 버전은 Kabsch alignment를 수행한 뒤 RMSD를 계산한다.
# ============================================================

FOLDER=$(basename "$PWD")

# ------------------------------------------------------------
# 파일명은 현재 폴더명을 그대로 사용한다.
# 따라서 폴더명이 아래처럼 생겼으면:
#   2026-04-20_NPG6-4_r1
#   2026-04-20_NPG6-4_A3a_r1
# 출력 파일은 각각:
#   2026-04-20_NPG6-4_r1_RMSD.dat
#   2026-04-20_NPG6-4_A3a_r1_RMSD.dat
# 로 저장된다.
# ------------------------------------------------------------
OUTFILE="${FOLDER}_RMSD.dat"

# ------------------------------------------------------------
# 필요하면 실행할 때 환경변수로 바꿀 수 있음.
# 예:
#   CMS_FILE=my-out.cms TRJ_DIR=my_trj REF_CMS=my-in.cms bash 01_extract_RMSD_aligned.sh
# ------------------------------------------------------------
CMS_FILE="${CMS_FILE:-test-out.cms}"
TRJ_DIR="${TRJ_DIR:-test_trj}"
REF_CMS="${REF_CMS:-test-in.cms}"
ASL="${ASL:-protein and a.pt CA}"

if [ -z "${SCHRODINGER:-}" ]; then
    echo "❌ 오류: SCHRODINGER 환경변수가 설정되어 있지 않습니다."
    exit 1
fi

if [ ! -f "$CMS_FILE" ]; then
    echo "❌ 오류: $CMS_FILE 파일이 현재 폴더에 없습니다."
    exit 1
fi

if [ ! -d "$TRJ_DIR" ]; then
    echo "❌ 오류: $TRJ_DIR 폴더가 현재 폴더에 없습니다."
    exit 1
fi

# reference cms가 없으면 trajectory 첫 frame을 reference로 사용한다.
# 단, Desmond GUI Prot_CA와 최대한 비슷하게 하려면 test-in.cms가 있는 편이 좋다.
if [ -f "$REF_CMS" ]; then
    REF_MODE="cms"
    echo "▶ Reference : $REF_CMS"
else
    REF_MODE="first_frame"
    echo "⚠️ $REF_CMS 파일이 없어 trajectory 첫 frame을 reference로 사용합니다."
    echo "   GUI Prot_CA와 완전히 일치시키려면 test-in.cms도 함께 두는 것을 권장합니다."
fi

echo "▶ 현재 폴더 : $FOLDER"
echo "▶ CMS 파일   : $CMS_FILE"
echo "▶ TRJ 폴더   : $TRJ_DIR"
echo "▶ ASL 선택   : $ASL"
echo "▶ 출력 파일 : $OUTFILE"
echo ""

TMPPY="_tmp_rmsd_aligned_${$}.py"

cat > "$TMPPY" <<'PY'
import sys
import numpy as np
from schrodinger.application.desmond.packages import topo, traj

cms_file = sys.argv[1]
trj_dir = sys.argv[2]
out_file = sys.argv[3]
ref_mode = sys.argv[4]
ref_cms = sys.argv[5]
asl = sys.argv[6]

# ------------------------------------------------------------
# Kabsch alignment 후 RMSD 계산 함수
#
# P: mobile coordinates, 현재 frame
# Q: reference coordinates
#
# 계산 순서:
#   1) 두 좌표의 중심을 원점으로 이동
#   2) 최적 회전행렬 계산
#   3) mobile을 reference에 superpose
#   4) RMSD 계산
# ------------------------------------------------------------
def kabsch_rmsd(P, Q):
    P = np.asarray(P, dtype=float)
    Q = np.asarray(Q, dtype=float)

    if P.shape != Q.shape:
        raise ValueError(f"Coordinate shape mismatch: mobile {P.shape}, reference {Q.shape}")

    P_cent = P - P.mean(axis=0)
    Q_cent = Q - Q.mean(axis=0)

    C = P_cent.T @ Q_cent
    V, S, Wt = np.linalg.svd(C)

    # reflection 방지
    d = np.sign(np.linalg.det(V @ Wt))
    D = np.diag([1.0, 1.0, d])

    U = V @ D @ Wt
    P_aligned = P_cent @ U

    diff = P_aligned - Q_cent
    return np.sqrt(np.sum(diff * diff) / P.shape[0])

# ------------------------------------------------------------
# trajectory system 읽기
# ------------------------------------------------------------
msys_model, cms_model = topo.read_cms(cms_file)
tr = traj.read_traj(trj_dir)

# mobile atom selection: 일반적으로 protein C-alpha
mobile_aids = cms_model.select_atom(asl)
if len(mobile_aids) == 0:
    raise ValueError(f"No atoms matched ASL in {cms_file}: {asl}")

# ------------------------------------------------------------
# reference 좌표 준비
# ------------------------------------------------------------
if ref_mode == "cms":
    ref_msys, ref_model = topo.read_cms(ref_cms)
    ref_aids = ref_model.select_atom(asl)
    if len(ref_aids) == 0:
        raise ValueError(f"No atoms matched ASL in {ref_cms}: {asl}")
    if len(ref_aids) != len(mobile_aids):
        raise ValueError(
            f"Atom count mismatch for ASL '{asl}': "
            f"reference={len(ref_aids)}, mobile={len(mobile_aids)}"
        )
    ref_xyz = np.array([ref_model.atom[i].xyz for i in ref_aids], dtype=float)
else:
    ref_frame = tr[0]
    ref_model = cms_model.copy()
    topo.update_ct(ref_model, cms_model, ref_frame)
    ref_xyz = np.array([ref_model.atom[i].xyz for i in mobile_aids], dtype=float)

# ------------------------------------------------------------
# 각 frame에 대해:
#   1) 좌표 update
#   2) CA 좌표 추출
#   3) reference에 alignment
#   4) RMSD 저장
# ------------------------------------------------------------
with open(out_file, "w") as fh:
    fh.write("# frame rmsd_ca\n")

    for i, fr in enumerate(tr):
        st = cms_model.copy()
        topo.update_ct(st, cms_model, fr)
        mob_xyz = np.array([st.atom[j].xyz for j in mobile_aids], dtype=float)

        val = kabsch_rmsd(mob_xyz, ref_xyz)
        fh.write(f"{i} {val:.6f}\n")
PY

$SCHRODINGER/run python3 "$TMPPY" "$CMS_FILE" "$TRJ_DIR" "$OUTFILE" "$REF_MODE" "$REF_CMS" "$ASL"
rm -f "$TMPPY"

echo "✓ 완료: $OUTFILE"
echo ""
echo "확인:"
echo "  head $OUTFILE"
