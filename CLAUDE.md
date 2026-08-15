# CLAUDE.md

Guidance for Claude Code in this repository. Start with
[AGENTS.md](./AGENTS.md) — this file only adds what is specific to Claude Code.

供 Claude Code 在本 repo 工作時參考。請先讀 [AGENTS.md](./AGENTS.md)；本檔只補充
Claude Code 專屬的部分。

## Where the work is / 工作在哪裡

| Path | Contents |
|---|---|
| `plan/plan.md` | The design, and the reason behind each decision. / 設計文件，以及每項決定的理由 |
| `todo/todo.md` | Decided but not yet designed in full. / 已確定要做、但尚未完整設計的項目 |
| `compare/*.csv2` | Comparisons against SQLite and PostgreSQL; also the first real fixtures. / 與 SQLite、PostgreSQL 的比較，亦為第一批真實測試素材 |

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
