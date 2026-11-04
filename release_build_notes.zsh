#!/usr/bin/env zsh
# =====================================================================
#  release_build_notes.zsh — the release notes' build-and-suites line, from a CI run
#  release_build_notes.zsh — release notes 的「建置與測試結果」那一行，取自一次 CI 執行
#
#    zsh release_build_notes.zsh <version> <run id> <commit> <out file> <platform>...
#
#  Each job's own log says its PASS/FAIL/SKIP, so nothing is transcribed. A
#  Linux or macOS job without that summary refuses; Windows does not run the
#  suite in CI, and the line says so rather than leaving a gap that reads as a
#  pass. Used by publish_matrix.zsh (a person's machine) and by release.yml's
#  publish job, so the two cannot word it differently.
#  每個 job 自己的 log 說了它的 PASS/FAIL/SKIP，因此沒有任何東西是手抄的。Linux 或 macOS 的 job 沒有
#  那份摘要就拒絕；Windows 在 CI 裡不跑整套測試，這一行就照實說，而不是留下一個看起來像通過的空白。
#  publish_matrix.zsh（人的機器上）與 release.yml 的 publish job 都用它，所以兩邊不可能寫得不一樣。
# =====================================================================
emulate -L zsh
setopt no_unset pipe_fail errexit

(( $# >= 5 )) || { print -u2 -- "usage: zsh release_build_notes.zsh <version> <run id> <commit> <out file> <platform>..."; exit 2 }
VERSION=$1 run_id=$2 TAG_SHA=$3 out=$4
PLATFORMS=(${@:5})
TAG=v$VERSION
REPO=raliclo/csv2
WORKFLOW=release.yml
cd -- "${0:A:h}"
[[ $run_id == <-> ]] || { print -u2 -- "the run id must be a number (got: $run_id)"; exit 2 }

# The job logs are fetched with curl, not `gh api`. They are full of terminal
# escape sequences (colour codes), and a newer gh refuses to print such a
# response -- "the response contains terminal escape sequences; pass
# --allow-escape-sequences" -- while older ones (2.89, 2.95) do not know that
# flag at all. The first eight-archive publish job (2026-11-04) got an empty
# log that way and refused. curl passes the bytes through whatever gh does.
# The token: GH_TOKEN in a workflow, gh's own on a person's machine, and none
# where a proxy supplies it (a Claude Code session).
# job log 用 curl 抓，不用 `gh api`。log 裡滿是終端機跳脫序列（顏色碼），較新的 gh 拒絕輸出這種回應——
# 「the response contains terminal escape sequences; pass --allow-escape-sequences」——而較舊的（2.89、2.95）
# 根本不認得那個旗標。第一次八份封存的 publish job（2026-11-04）因此拿到空的 log 而拒絕。curl 不論 gh 怎麼
# 做都把位元組原樣交出。token：workflow 裡用 GH_TOKEN，人的機器上用 gh 自己的，有 proxy 代為提供的地方
# （Claude Code session）就不帶。
log_token=${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}
job_log() {   # job_log <job id>
    if [[ -n $log_token ]]; then
        curl -sfL -H "Authorization: Bearer $log_token" "https://api.github.com/repos/$REPO/actions/jobs/$1/logs"
    else
        curl -sfL "https://api.github.com/repos/$REPO/actions/jobs/$1/logs"
    fi
}
swift_win=$(sed -n 's/^ *SWIFT_VERSION: *"\([0-9.]*\)".*/\1/p' .github/workflows/$WORKFLOW | head -1)
typeset -a suites_en suites_zh
for plat in $PLATFORMS; do
    [[ $plat == windows-* ]] && continue
    job=$(gh api "repos/$REPO/actions/runs/$run_id/jobs?per_page=50" --jq ".jobs[] | select(.name == \"$plat\") | .id")
    [[ $job == <-> ]] || { print -u2 -- "no job named $plat in run $run_id / 執行 $run_id 裡沒有名為 $plat 的 job"; exit 1 }
    counts=$(job_log "$job" | LC_ALL=C grep -a -oE 'PASS [0-9]+ +FAIL [0-9]+ +SKIP [0-9]+' | tail -1 || true)
    [[ -n $counts ]] || { print -u2 -- "the $plat job's log has no suite summary / $plat 的 log 裡沒有測試摘要"; exit 1 }
    c=(${=counts})
    suites_en+=("$plat $c[2]/$c[4]/$c[6]")
    suites_zh+=("$plat $c[2]/$c[4]/$c[6]")
done
# The Windows names come from the platforms passed in, not from a literal: a
# line naming an architecture this run did not build is LA, and T239 holds
# every script to it.
# Windows 的名字取自傳進來的平台清單，不寫成字面值：說出一個這次執行沒有建置的架構就是 LA，而 T239 要求
# 每一支腳本都遵守它。
wins=(${(M)PLATFORMS:#windows-*})
(( ${#wins} )) || wins=(Windows)
{
    print -r -- "Built at \`$TAG / ${TAG_SHA[1,8]}\` by [release.yml run $run_id](https://github.com/$REPO/actions/runs/$run_id), each platform on a runner of its own. Suites (pass/fail/skip): ${(j:, :)suites_en}. On ${(j: and :)wins} the suite does not run in CI; release.zsh extracted each archive, ran the binary and had it read a CSV. Windows needs the Swift $swift_win runtime."
    print -r -- ""
    print -r -- "每個平台都在它自己的 runner 上、於 \`$TAG / ${TAG_SHA[1,8]}\` 由 [release.yml 執行 $run_id](https://github.com/$REPO/actions/runs/$run_id) 建置。測試（通過/失敗/略過）：${(j:、:)suites_zh}。${(j: 與 :)wins} 在 CI 裡不跑整套測試；release.zsh 解開了每一份封存、執行了執行檔，並讓它讀一個 CSV。Windows 需要 Swift $swift_win runtime。"
} > "$out"
