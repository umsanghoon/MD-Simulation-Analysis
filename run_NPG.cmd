# @ class = fire-gpu
# @ error = error

#!/bin/bash
set -euo pipefail

# ============================================================
# run_NPG.cmd
#
# 목적:
#   각 input 폴더 안에서 현재 폴더의 Desmond input 파일을 자동 인식하고,
#   기존에 잘 돌았던 FIRE GPU 방식으로 실행한다.
#
# 사용 위치 예:
#   cd /fire/lynn/sum4/my_project/input/2026-04-24_NPG6-4_A0a_r1
#   llsubmit /fire/lynn/sum4/my_project/scripts/run_NPG.cmd
#
# 현재 폴더 안에 있어야 하는 파일:
#   *_desmond_md_job*.msj
#   *_desmond_md_job*.cfg
#   *_desmond_md_job*.cms
#
# 출력:
#   test-out.cms
#   test_trj/
#   test.log
#   test.ene
#   test.cpt
#   test_*-out.tgz
#
# 중요:
#   -JOBNAME test 로 고정했기 때문에 출력 파일 prefix는 항상 test.
#   - output folder를 따로 쓰지 않고 현재 input folder 안에 결과 생성.
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ run_NPG.cmd 시작"
echo "▶ 현재 폴더: $(pwd)"
echo "▶ 시작 시간: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# [1] GPU 설정
# ============================================================

export CUDA_VISIBLE_DEVICES=0

# ============================================================
# [2] 현재 폴더 안에서 input 파일 자동 탐색
# ============================================================

MSJ_FILE=$(ls *_desmond_md_job*.msj 2>/dev/null | head -n 1 || true)
CFG_FILE=$(ls *_desmond_md_job*.cfg 2>/dev/null | head -n 1 || true)
CMS_FILE=$(ls *_desmond_md_job*.cms 2>/dev/null | head -n 1 || true)

if [ -z "$MSJ_FILE" ]; then
    echo "❌ 오류: *_desmond_md_job*.msj 파일을 찾지 못했습니다."
    exit 1
fi

if [ -z "$CFG_FILE" ]; then
    echo "❌ 오류: *_desmond_md_job*.cfg 파일을 찾지 못했습니다."
    exit 1
fi

if [ -z "$CMS_FILE" ]; then
    echo "❌ 오류: *_desmond_md_job*.cms 파일을 찾지 못했습니다."
    exit 1
fi

echo "▶ MSJ 파일: $MSJ_FILE"
echo "▶ CFG 파일: $CFG_FILE"
echo "▶ CMS 파일: $CMS_FILE"

# ============================================================
# [3] 출력 prefix 고정
# ============================================================

JOBBASE="test"
OUTCMS="${JOBBASE}-out.cms"

echo "▶ 출력 prefix: $JOBBASE"
echo "▶ 출력 CMS: $OUTCMS"

# ============================================================
# [4] 기존 test 출력물이 있으면 충돌 방지
# ============================================================

if ls ${JOBBASE}* 1>/dev/null 2>&1; then
    echo "❌ 오류: 현재 폴더에 이미 ${JOBBASE}로 시작하는 파일/폴더가 있습니다."
    echo "   기존 결과와 섞이지 않도록 먼저 백업하거나 삭제하세요."
    echo ""
    ls -lh ${JOBBASE}* || true
    exit 1
fi

# ============================================================
# [5] JSC local server 시작
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ JSC local server 시작"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

$SCHRODINGER/jsc local-server-start

# local-server가 이미 켜져 있거나, 중간 에러가 나도 마지막에 stop 시도
cleanup() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ JSC local server 종료 시도"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    $SCHRODINGER/jsc local-server-stop || true
}
trap cleanup EXIT

# ============================================================
# [6] Desmond 실행
#
# 기존에 성공한 커맨드와 동일한 핵심 옵션 사용:
#   -JOBNAME test
#   -HOST localhost:56
#   -description 'Molecular Dynamics'
#   -mode umbrella
#   -o test-out.cms
#   -lic DESMOND_GPGPU:1
#   -WAIT
#
# output은 현재 폴더의 test-out.cms로 생성되도록 설정.
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Desmond 실행"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

"${SCHRODINGER}/utilities/multisim" \
  -JOBNAME "$JOBBASE" \
  -HOST localhost:56 \
  -m "$MSJ_FILE" \
  -c "$CFG_FILE" \
  -description 'Molecular Dynamics' \
  "$CMS_FILE" \
  -mode umbrella \
  -o "$OUTCMS" \
  -lic DESMOND_GPGPU:1 \
  -WAIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ run_NPG.cmd 완료"
echo "▶ 종료 시간: $(date)"
echo "▶ 생성된 주요 파일:"
ls -lh ${JOBBASE}* 2>/dev/null || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
