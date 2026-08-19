# CLAUDE.md

Guidance for Claude Code in this repository. Start with
[AGENTS.md](./AGENTS.md) — this file only adds what is specific to Claude Code.

供 Claude Code 在本 repo 工作時參考。請先讀 [AGENTS.md](./AGENTS.md)；本檔只補充
Claude Code 專屬的部分。

## Where the work is / 工作在哪裡

| Path | Contents |
|---|---|
| `plan/plan.md` | The design, the reason behind each decision, and the phase checkboxes that record what is done. / 設計、每項決定的理由，以及記錄進度的階段核取方塊 |
| `src/*.swift` | The implementation. `main.swift` must be compiled LAST. / 實作。`main.swift` 必須排在編譯順序的最後 |
| `compile_csv2.zsh` | Build. Ends by RUNNING the binary, not by checking it exists. / 建置。結尾以「執行產物」驗證，而非檢查檔案存在 |
| `test/test_csv2.zsh` | The suite. Case numbers match the plan's test list one to one. / 測試。案例編號與計畫的測試清單一一對應 |
| `todo/todo.md` | Decided but not yet designed in full. / 已確定要做、但尚未完整設計的項目 |
| `compare/*.csv2` | Comparisons against SQLite and PostgreSQL; also the first real fixtures. / 與 SQLite、PostgreSQL 的比較，亦為第一批真實測試素材 |

```zsh
./compile_csv2.zsh && ./test/test_csv2.zsh    # 0 FAIL；唯一的 SKIP 是 T47
```

**Tick a checkbox in the plan only once its test passes.** Code written but not
tested is not done — that is the exact "looks like it succeeded" failure this
project keeps running into.
**計畫中的核取方塊，只有在對應測試通過時才打勾。** 寫好但沒測不算完成——那正是本
專案一再遇到的那種「看起來成功」的失敗。

## Working directory / 工作目錄

This repository is normally reached as a submodule of the parent project at
`/Volumes/LinuxCS/sos/csv2`. That volume is a case-sensitive sparse image and
must be mounted first; see the parent `CLAUDE.md`.

本 repo 通常以母專案的 submodule 形式存在於 `/Volumes/LinuxCS/sos/csv2`。該 volume 是
case-sensitive sparse image，須先掛載，詳見母專案的 `CLAUDE.md`。

Working inside the submodule directly is fine, but a commit here is only visible
to the parent once the parent's gitlink is updated. Push here **first**, then
commit the pointer in the parent — the reverse order leaves the parent naming a
commit no clone can fetch.

直接在 submodule 內工作沒有問題，但此處的 commit 要等母專案更新 gitlink 後才看得到。
請**先**在此推送，再於母專案提交指標——順序反過來會使母專案指向一個任何 clone 都取不到
的 commit。

## Commit messages / Commit 訊息

Bilingual, English first then Traditional Chinese. Explain **why**, not what —
the diff already says what. Decisions that were considered and rejected belong
in the message; they are the part that cannot be recovered from the code.

雙語，英文在前、繁體中文在後。說明**為什麼**而非做了什麼——diff 已經說了做了什麼。
曾經考慮但被否決的選項應寫進訊息，那是無法從程式碼還原的部分。

## Do not / 不要

- Do not add a `-key` flag taking the secret on the command line. It is visible
  in `ps`. `plan/plan.md` explains why it is excluded rather than warned about.
  不要加上以命令列傳遞秘密的 `-key`，它在 `ps` 中可見；`plan/plan.md` 說明了為何是
  排除而非警告。
- Do not silently repair malformed input. Report the record and field, exit
  non-zero. 不要靜默修復格式錯誤的輸入；請指出紀錄與欄位並以非零結束。
- Do not let the tool print anything on the normal path. It has to work in a
  pipeline. 正常路徑上不得輸出任何訊息，本工具必須能放進管線。
- Do not fix a reported defect before it is written down. Every finding from a
  blind-testing round goes into [`todo/known-defects.md`](./todo/known-defects.md)
  the moment it is reproduced by hand — with the commands and the output — and
  the fix comes after. A defect that exists only in a session transcript leaves
  the next reader a clean tree and a passing suite; and half the value of that
  file is the reproductions, which are the only way to tell later whether a fix
  has regressed. Two program defects were fixed straight into `plan/plan.md` on
  2026-08-19 and had to be backfilled from memory.
  不要在一個被回報的缺陷「被寫下來」之前就去修它。盲測每一回合的每一項發現，一經親手重現
  就寫進 [`todo/known-defects.md`](./todo/known-defects.md)——連同指令與輸出——修正在那之後。
  一個只存在於 session 逐字稿裡的缺陷，留給下一個讀者的是一棵乾淨的樹和一份全過的測試；
  而那個檔案有一半的價值在那些重現步驟，它們是日後判斷「修正有沒有退化」的唯一依據。
  2026-08-19 有兩個程式缺陷被直接修進 `plan/plan.md`，後來只能靠記憶補記。
- Do not run a blind-testing round from a session that has already been
  running. A subagent inherits its parent session's context, not the disk, and
  every `CLAUDE.md` was read into that context at start-up — so on 2026-08-19
  two rounds quoted a defect table that had already been deleted and
  committed. Removing something only helps sessions started afterwards. A
  round must be launched from a FRESH session, and the agent must be asked to
  disclose anything its context told it before it ran a command.
  不要從一個「已經在執行中」的 session 派出盲測回合。subagent 繼承的是母 session 的
  context 而不是磁碟，而每一份 `CLAUDE.md` 都在啟動時被讀進了那個 context——因此
  2026-08-19 有兩個回合引用了一張「已經被刪除並提交」的缺陷表。移除任何東西，都只對
  「之後開啟的 session」有效。一個回合必須從**全新的 session** 派出，而且要求該 agent
  揭露「在執行任何指令之前，它的 context 告訴了它什麼」。
- Do not put a defect list anywhere else — not in a `CLAUDE.md`, not in a
  README. One was kept in the global `CLAUDE.md` and by 2026-08-19 all five of
  its entries were false, every one having been fixed while the list went on
  steering people away from an operation that was already safe. Instruction
  files are also pre-injected into every agent's context, which is what stopped
  two README-only blind tests from being blind.
  缺陷清單不要放在別的地方——不放在任何 `CLAUDE.md`，也不放在 README。全域 `CLAUDE.md`
  曾經有一份，到 2026-08-19 時**五條全部不成立**，每一條都早已修掉，而那張表還在叫人避開
  一個已經安全的操作。指令檔還會被預先注入每一個 agent 的 context，那正是兩次「只讀 README
  的盲測」不再是盲測的原因。
