# blind-test-flow.md

How a round of blind documentation testing is run here, and why each step is
the way it is. Every rule below was paid for: the round number beside it is
where it went wrong before the rule existed.

這裡是怎麼跑一回合「盲測文件」的，以及每一步為什麼是這樣。底下每一條規則都是付過代價的；
旁邊那個回合編號，就是「在這條規則存在之前，它出錯的地方」。

This is not [flow.md](../../flow.md), which is about starting a new subproject.
This is about a project that already works finding out what it is still wrong
about.

這不是 [flow.md](../../flow.md)——那一份講的是「怎麼開始一個新的子專案」。這一份講的是
「一個已經能用的專案，怎麼找出它仍然錯在哪裡」。

---

## Why a stranger

The person who wrote the documentation cannot test it. They know too much:
they supply the missing sentence from memory and then believe it was written.
The only reliable measurement is somebody who genuinely does not know.

寫文件的人測不了他自己的文件。他知道得太多了：他會憑記憶補上那句沒寫出來的話，然後相信它寫過。
唯一可靠的量測，是一個真的不知道的人。

**What it measures is not "is the README nice to read".** It is one falsifiable
claim: *can somebody who has read only the README use this tool correctly?*

**它量的不是「README 讀起來順不順」**，而是一個可否證的命題：**一個只讀過 README 的人，能不能
正確地使用這個工具？**

---

## Running a round

### 1. The tree must be clean first

Commit or at least build what is there. A round against a half-finished state
produces failures that cannot be attributed -- documentation or program, and
nobody can tell which.

先把樹弄乾淨：提交，或至少確認建置是好的。對著一個半完成的狀態派出一個回合，得到的失敗無法歸屬
——是文件還是程式，沒有人分得出來。

### 2. Launch from a FRESH session, never a fork

`claude -p`, a new process. **Not** a subagent of the session doing the work.

用 `claude -p`，一個新的行程。**不要**用正在工作的那個 session 的 subagent。

A subagent inherits its parent's context, not the disk. Every `CLAUDE.md` was
read into that context at start-up, so on 2026-08-19 two rounds quoted a defect
table that had already been deleted and committed. **Removing something only
helps sessions started afterwards.**

一個 subagent 繼承的是母 session 的 context，不是磁碟。每一份 `CLAUDE.md` 都在啟動時被讀進了那個
context——因此 2026-08-19 有兩個回合引用了一張「已經被刪除並提交」的缺陷表。**移除任何東西，都只對
「之後開啟的 session」有效。**

### 3. Say what may be read, and what may not

Readable: the READMEs, both languages. Forbidden: `src/`, `test/`, `plan/`,
`todo/`, `compare/`, `verifications/`, every `CLAUDE.md` and `AGENTS.md`, git
history -- and **`--help`**, which is the most important prohibition. A round
that runs `--help` is no longer testing the README.

可讀：兩份 README。禁讀：`src/`、`test/`、`plan/`、`todo/`、`compare/`、`verifications/`、任何
`CLAUDE.md` 與 `AGENTS.md`、git 歷史——以及 **`--help`**，那是最重要的一條禁令。一個跑了 `--help`
的回合，測的已經不是 README 了。

### 4. Make it disclose its contamination

Require a section, written BEFORE the first command: *what did my context
already tell me about this tool?* Instruction files are pre-injected into every
agent's context, and this is not hypothetical -- round 75 reported that tasks 1
and 2 were pre-seeded with `-get` syntax, `record:field` addressing and `-i`,
and said plainly that its verdict on those two was a judgement about the text
rather than evidence from a naive reader.

要求它在**第一個指令之前**寫一節：「在我執行任何東西之前，我的 context 已經告訴了我什麼？」
指令檔會被預先注入每一個 agent 的 context，而這不是假設——第 75 回合回報它的任務 1 與 2 被預先
餵了 `-get` 語法、`record:field` 定址與 `-i`，並明說它對那兩項的判定是「對文字的判斷」，不是
「來自一個無知讀者的證據」。

### 5. Tasks describe a GOAL, never a command

"Get one field out of a record, clean enough to assign to a shell variable" is
a task. "Run `csv2 -get 1:3`" is not -- that is handing over the answer.

任務描述**目的**，絕不給指令。「把某一筆的某一欄取出來，乾淨到可以指派給一個 shell 變數」是任務；
「執行 `csv2 -get 1:3`」不是——那是把答案交出去。

Aim at what has been used least. Rounds 74 to 77 found little in code a year
old and ten defects in code two days old, all in the same round (78), because
that round was pointed at the two features nobody but the author had used --
and told to treat every claim about them as something to falsify.

瞄準「最少被用過」的地方。第 74 到 77 回合在一年前的程式碼裡找到的很少，而第 78 回合在兩天大的
程式碼裡一次找到十個——因為那一回合是對準「除了作者以外沒有人用過」的兩個功能派出去的，並且被
告知要把關於它們的每一條宣稱當成「待否證的主張」。

### 6. Four categories, and they must not be merged

1. **DOC WRONG** — the README says something the program does not do
2. **DOC MISSING** — something needed and not findable
3. **DOC UNCLEAR** — written, but readable two ways
4. **TOOL BROKEN** — the README is right and the program is wrong

An unsorted report is much less useful: 1 and 4 need opposite fixes, and 3 is
the one that gets ignored and causes the most misuse.

一份不分類的回報用處小得多：第 1 類與第 4 類要修的東西完全相反，而第 3 類最容易被忽略、也最常
造成誤用。

### 7. Make it rule out its own environment

Add this to the brief, verbatim, because three rounds have filed their own
shell as a csv2 defect:

把這一段逐字加進簡報，因為已經有三個回合把自己的 shell 當成 csv2 的缺陷回報：

> For anything in category 4, first re-run it by absolute path with no `cd`,
> take the exit status from `$pipestatus` rather than through a pipe, and print
> captured output with `printf '%s'` rather than `echo`.

Each clause is a scar. A `cd` triggered this machine's `chpwd` hook and printed
a directory listing that round 75 filed as installer output. A pipe returned
`head`'s exit status instead of csv2's. And zsh's `echo` decodes `\u`, which
made correctly escaped `--json-ascii` output look unescaped and cost half an
hour.

每一句都是一道疤。一次 `cd` 觸發了這台機器的 `chpwd` hook、印出一份目錄列表，而第 75 回合把它當成
安裝程式的輸出回報。一條管線回傳的是 `head` 的結束狀態而不是 csv2 的。而 zsh 的 `echo` 會解讀
`\u`，讓正確跳脫的 `--json-ascii` 輸出看起來沒有跳脫，花掉了半小時。

---

## After the report

### 8. Verify every claim by hand. TOOL BROKEN first.

**Do not fix from the report.** Reproduce each item yourself. Category 4 is the
one to distrust most -- rounds 76 and 77 each ruled out their own candidates
and reported an empty category 4, which is a better outcome than a full one.

**不要照著報告修。** 每一項自己重現一次。第 4 類最該被懷疑——第 76 與 77 回合各自排除了自己的候選、
回報了一個**空的**第 4 類，而那比一個滿的更有價值。

When a claim is right, it is often righter than reported: round 78 said `-md`
turned a CR into an LF; measuring it showed a CRLF could not survive either,
which the round never reached.

而當一項宣稱是對的時，它往往比回報的更對：第 78 回合說 `-md` 把 CR 變成了 LF；實際去量，發現
CRLF 也活不下來，而那是那個回合沒有走到的。

### 8b. A task that EDITS a file must checksum it, because no stream will tell you

Round 79's only real defect was invisible in everything a caller normally
reads: `--dry-run` with `-md` exited 0, wrote zero bytes to stdout, zero bytes
to stderr, and modified the file. The round found it because it took a sha256
before and after; nothing else in its transcript would have. A round that
judged that task by exit status and output would have reported "worked".

So: every task in a brief that edits a file gets a before/after checksum, and
the report states it. Not a diff of the region the task touched -- a checksum
of the whole file, because the surprise is a write nobody asked about.

The same asymmetry decides where a case asserts first. T246 checks the
CHECKSUM before it checks the report, because a case checking only the report
would have started passing the moment the report was added while the write
went on happening underneath it.

### 8b. 一個「會編輯檔案」的任務必須取校驗和，因為沒有任何一條串流會告訴你

第 79 回合唯一一個真正的缺陷，在呼叫端平常會讀的每一樣東西裡都是隱形的：`--dry-run` 搭配
`-md` 以 0 結束、stdout 零位元組、stderr 零位元組，而檔案被改了。那個回合能發現它，是因為它
在前後各取了一次 sha256；它的逐字稿裡沒有別的東西看得到。一個用退出碼與輸出去判斷那個任務的
回合，會回報「成功」。

因此：brief 裡每一個會編輯檔案的任務，都要取前後校驗和，並在報告中寫出來。不是「任務碰到的
那個區域的 diff」——是**整個檔案**的校驗和，因為意外的正是那次沒有人問起的寫入。

同一個不對稱決定了一個案例先斷言什麼。T246 先檢查**校驗和**、再檢查報告，因為一個只檢查報告
的案例，會在報告被加上去的那一刻開始通過，而底下那次寫入照樣繼續發生。

**在回歸測試裡，等價的做法是 `cmp -s` 加一份 `cp` 出來的原始複本，不是校驗和。** 一個盲測 agent
跑在完整的 macOS shell 上，那裡 `shasum` 一定在；這套測試還要在 busybox 上跑，而那裡沒有 `shasum`
——於是前後兩次擷取雙雙變成空字串，`空 == 空` 讓那個案例以「什麼都沒量」的方式通過。T246a 第一版
就是這樣，見 mistakes 第 1 條第十一次。

In a regression case the equivalent is `cmp -s` against a `cp` of the original, NOT a checksum.
A blind-test agent runs in a full macOS shell where `shasum` exists; this suite also runs on
busybox, where it does not -- and both captures collapse to the empty string, which are equal,
so the case passes having measured nothing.

### 8c. 驗證一項回報，包含「驗證它建議的補救」

規則 8 說「逐條親手驗證」，而那通常被讀成「確認它說的現象是真的」。**那只是一半。**

2026-09-07，第 92 回合回報：`-rownum` 在定位報告上被靜默忽略，而 `--json` 底下是硬拒絕；它建議
讓報告那一側也拒絕。**那個現象是真的**——我重現了。我照建議改了程式，然後 **T15a 與 T15d 立刻失敗**。

T15 的註解寫著：「`-rownum` 只作用在輸出側：它**必須不**改變定址、也**必須不**可被搜尋——否則一個
『只是多印一欄』的旗標，會安靜地改變每一個位址的意義。」而它正是以「跑 `-contains -rownum` 並檢查
位址沒有移動」來斷言那件事。**拒絕那一對，等於刪掉那個不變量被表達的方式。**

一個盲測回合看得見這一頁與這支程式，**看不見這棵樹為什麼決定成這樣**。它指出的不一致往往是真的；
它提議的方向則是在沒有那段歷史的情況下猜的。

**做法**：一項回報若建議「讓 A 也變成 B 那樣」，在改之前先問——**有沒有任何測試是靠 A 現在的樣子
才寫得出來的？** 有的話，那個不對稱多半是被決定過的，該做的是**記載它**，不是抹平它。

### 8c. Verifying a report includes verifying its proposed remedy

Rule 8 says reproduce every claim by hand, which is usually read as confirming the SYMPTOM. That
is half of it. Round 92 correctly reported an asymmetry and proposed removing it; the removal
broke T15, whose comment records the invariant the asymmetry exists to express. A round sees the
page and the program, never why the tree decided what it decided. When a report says "make A
behave like B", ask first whether any test is written the way it is BECAUSE of A. If one is, the
asymmetry was chosen, and the fix is to document it rather than flatten it.

### 9. Write it down BEFORE fixing it

Every reproduced finding goes into [`todo/known-defects.md`](./todo/known-defects.md)
with the commands and the output, and the fix comes after.

每一項重現過的發現，連同指令與輸出，先寫進 `todo/known-defects.md`，修正在那之後。

A defect that exists only in a session transcript leaves the next reader a clean
tree and a passing suite. Half that file's value is the reproductions: they are
the only way to tell later whether a fix has regressed. On 2026-08-19 two
defects were fixed straight into `plan/plan.md` and had to be backfilled from
memory.

一個只存在於 session 逐字稿裡的缺陷，留給下一個讀者的是一棵乾淨的樹和一份全過的測試。那個檔案有
一半的價值在那些重現步驟——它們是日後判斷「修正有沒有退化」的唯一依據。

Record the ones that turn out NOT to be defects too, with the disproof. The next
round will very likely report the same thing, and that should cost thirty
seconds rather than an afternoon.

那些「結果不成立」的也要記，連同否證。下一個回合很可能會再報一次，而那時應該花三十秒、不是一個
下午。

### 10. Every corrected sentence needs a test

A behaviour description that is not asserted anywhere is worse than no
description, because a reader will rely on it. When the fix is in the
documentation, the test is what keeps the new sentence honest.

一句沒有任何東西斷言的行為描述，比沒有描述更糟，因為讀者會依賴它。當修正是在文件上時，那個測試
就是讓那句新話保持誠實的東西。

Check the test can FAIL. Put the defect back and watch the case catch it. Round
78's fixes were each verified that way; so was T204, where three separate faults
were reintroduced one at a time.

確認那個測試**失敗得了**。把缺陷放回去，看那個案例抓不抓得到。

### 11. Four platforms, and macOS passing means nothing

macOS, the aarch64 guest, WSL2, Windows MSVC. **Do not push on macOS alone.**

macOS、aarch64 guest、WSL2、Windows MSVC。**不要只憑 macOS 就推送。**

This is the most expensive lesson here. In one day: a guard refused
`/dev/stdout` for the wrong reason only in the guest, on a case macOS skips; a
test passed on macOS *because macOS lacks `getent`* and so exercised a fallback
rather than the thing it named; a static library linked on Mach-O and failed on
Linux where a type's metadata is referenced from `.data.rel.ro`; and a Windows
build failed while the node kept its previous binary and the tests afterwards
reported on a program that was never made.

這是這裡最貴的一課。同一天之內：一道守衛只在 guest 上、且只在一個 macOS 會跳過的案例上，以錯的
理由拒絕了 `/dev/stdout`；一個測試在 macOS 上通過**是因為 macOS 沒有 `getent`**，於是它運動到的是
一條退路、而不是它指名的那個東西；一個靜態 library 在 Mach-O 上連結得起來、在 Linux 上失敗，因為
那裡一個型別的 metadata 是從 `.data.rel.ro` 被引用的；而一次 Windows 建置失敗、那個節點保留了它
先前的二進位檔，之後的測試回報的是一個從未被造出來的程式。

Read the `build:` line. Twice it said `FAILED` plainly and twice a grep of mine
hid it.

**要讀那一行 `build:`。** 它有兩次明明白白地說了 `FAILED`，而兩次把它藏起來的都是我自己的 grep。

**Look at the SKIP list, not the PASS count.** A case that skips looks exactly
like a case that passes. When the kernel changed by 13,187 commits, the answer
that mattered was that the seven skips were the same seven -- not that the total
had gone up.

**要看 SKIP 清單，不要看 PASS 數。** 一個跳過的案例，看起來與一個通過的案例一模一樣。當核心換了
13,187 個 commit 時，真正要緊的答案是「那七個 SKIP 是同樣的七個」，而不是總數變多了。

### 11a. `--help` and BOTH READMEs are part of the change, not follow-up

A flag the parser knows and the documentation does not is a flag nobody will
find. T154c and T154e exist to make that impossible to forget: one checks that
every flag the parser accepts appears in `--help`, the other that it appears in
**each** README. On 2026-08-27 they were the only two failures in a suite of
1039 after `-add-column` was implemented, and they were right -- the verb
worked and was undiscoverable.

一個「解析器認得、而文件不認得」的旗標，是一個沒有人會找到的旗標。T154c 與 T154e 的存在就是為了
讓這件事無法被忘記：一個檢查「解析器接受的每一個旗標都出現在 `--help` 裡」，另一個檢查它出現在
**每一份** README 裡。2026-08-27，在 `-add-column` 實作完之後，它們是一份 1039 個案例的測試裡
僅有的兩個失敗，而它們是對的——那個動詞能用，而且找不到。

**This applies to new features, not only to defects found by a round.** Rules
11 to 13 sit under "After the report" because that is where they were learned,
but nothing about them is specific to a report: a feature added on request
needs the same four platforms, the same documentation in both languages, and
the same commit order.

**這適用於新功能，不只適用於某一回合找到的缺陷。** 第 11 到 13 條排在「收到報告之後」底下，
是因為它們是在那裡學到的，但它們沒有一條是「只對報告成立」的：一個依要求新增的功能，需要同樣的
四個平台、同樣兩種語言的文件、以及同樣的 commit 順序。

### 11b. How the four nodes are actually upgraded

Section 11 says why. This is the order, and every line of it was paid for on
2026-09-02..05.

**The order is Mac -> Linux VM -> WSL2 -> Windows, and it is not arbitrary.**
It runs cheapest-feedback-first: the Mac is where the code is written and a
failure costs one rebuild; the guest is driven locally from here and costs
minutes; WSL2 and Windows are on another machine and each round trip costs a
message and someone else's attention. A defect that survives to the fourth node
has been paid for four times. Every step also invalidates the ones after it --
a failure on the Mac makes the other three meaningless, so there is no reason
to spend them.

**Reach the aarch64 guest through `sos/test_submodules/run_csv2_test.zsh`, not
through a shell into it.** The parent project also offers
`helper/run_remote.zsh guest '<cmd>'`, which is one line and looks like the
obvious choice. On 2026-09-10 a full suite run through it produced 408 lines of
output in which the failures were not failures:

```
T168b  missing 'CSV2_MAX_BUFFER_RECORDS' in: csv2: -B 6 exceeds the buffered-record lim
T171a  missing 'single-threaded' in: c
T170b2 missing 'unterminated record' in:
T169a  missing '\x1B' in: 2026-09-09T23:40:48.184Z INFO  csv2 -update …
```

Cut mid-word, cut to one character, empty, and one case capturing a different
line entirely. Every one of those cases inspects the OUTPUT of a command, so a
channel that truncates command substitution turns correct behaviour into a page
of specific, plausible-looking defects. **That is the worst kind to receive:
each message argues for itself.** Acting on them means changing correct code
until the wrong thing passes.

The session that owns that helper hit the same channel from the other side the
same morning -- a large-output command that ran 500 seconds and returned
nothing, then a zero-output command immediately after it that also hung. Hangs
there, truncation here; large output in both cases. Two independent shapes
ruled out two explanations: it is not csv2 behaving differently, and it is not
one test's shape.

**What is NOT established yet is that `run_csv2_test.zsh` is immune.** It takes
a different route -- a payload tar and the serial console -- and the guess is
that this is why it exists, but nobody wrote that reason down and a guess is not
a reason. When a run through it passes on the same commit, the reason belongs in
that file's comments, with these four lines as the evidence. Until then this
paragraph says what was seen, not what it means.

**經由 `sos/test_submodules/run_csv2_test.zsh` 抵達 aarch64 guest，不要用一個進去它的 shell。**
母專案另外提供 `helper/run_remote.zsh guest '<cmd>'`，一行就能用，看起來是理所當然的選擇。
2026-09-10 一次完整的測試套件走它，吐出 408 行，而其中的失敗不是失敗：訊息斷在字中間、只剩一個
字元、是空字串、或抓到了另一行的內容。那些案例檢查的**都是某個命令的輸出**，因此一個會截斷命令
替換的通道，會把正確的行為變成滿滿一頁「具體而且看起來言之有物」的缺陷。**那是最糟的一種：
每一則訊息都在為自己辯護。** 照著它們去修，等於改動正確的程式碼，直到錯的那個通過。

擁有那支 helper 的 session 在同一個早上從另一側撞到同一個通道——一條輸出量大的命令跑滿 500 秒、
一個字都沒回來，緊接著一條輸出為零的命令也掛住。那邊是掛住、這邊是截斷，而兩邊的共同點都是大量
輸出。兩種獨立的形狀排除了兩個解釋：不是 csv2 行為改變，也不是某一個測試的形狀特殊。

**還沒有被確立的是「`run_csv2_test.zsh` 免疫」。** 它走的是另一條路——payload tar 加序列主控台
——而「那大概就是它存在的理由」是一個猜測，不是理由。等到走它的一次執行在**同一個 commit** 上通過，
那個理由就該連同上面那四行證據，補進那個檔案的註解裡。在那之前，這一段說的是「看到了什麼」，
不是「那代表什麼」。

**How to reach the other two, because not saying it cost days.** The Mac dials
out. `~/.multissh/generated/config2Win` reaches Windows on port 16888 and
`config2WSL` reaches WSL2 on 16889; both use user `lowei` and the host answers
to `Ralic-W11.local` as well as to the IPv6 link-local address in the file:

```zsh
~/proj/multissh/release/multissh -f ~/.multissh/generated/config2Win \
    Ralic-W11.local 'cd ~/proj/csv2 && git pull --rebase && ./compile_csv2.zsh && ./test/test_csv2.zsh'
```

Swap `config2Win` for `config2WSL` to reach WSL2; nothing else in the line
changes.

**It has to be that binary. `ssh` cannot reach these nodes at all**, and the
message it gives says nothing about why. The daemons present a
`ssh-mldsa44-ed25519@openssh.com` host key, which stock OpenSSH has never
supported -- so the honest failure is `Bad key types`. You are unlikely to
see it. On 2026-09-08, macOS 10.3p1 percent-expands `HostName`, and the IPv6
scope id in both profiles (`fe80::...%en1`) reads to it as an unknown token
`%e`, so `ssh -F` dies at **config-parse** time with
`vdollar_percent_expand: unknown key %e` -- before it has looked at a host, a
port, or a key. That message invites you to go and fix the profile. The
profile is fine; it was never for this program. This session lost half an
hour there in round 96 and only got out by noticing that the multissh runner
scripts name a `client=release/multissh` of their own.

把 `config2Win` 換成 `config2WSL` 就是 WSL2，那一行的其他部分都不變。

**必須是那個執行檔。`ssh` 根本連不到這兩個節點**，而它給的訊息完全沒有說出原因。
那兩個 daemon 呈現的是 `ssh-mldsa44-ed25519@openssh.com` 主機金鑰，原版 OpenSSH 從來
不支援——所以誠實的失敗是 `Bad key types`。你多半看不到它。2026-09-08 起，macOS 上的
10.3p1 會對 `HostName` 做百分號展開，而兩份 profile 裡的 IPv6 scope id（`fe80::...%en1`）
在它眼中是一個未知的 `%e`，於是 `ssh -F` 在**解析設定檔**的階段就死了，訊息是
`vdollar_percent_expand: unknown key %e`——那時它還沒看過主機、埠號或金鑰。那句訊息會
邀請你去修那份 profile。那份 profile 沒有問題，它本來就不是給這支程式用的。第 96 回合
這個 session 在那裡耗掉半小時，最後是靠著注意到 multissh 的 runner 腳本自己指名了一個
`client=release/multissh` 才走出來。

**`multissh_upgrade_flow.md` in the multissh project says the opposite** -- that
Windows is the node that dials -- and on 2026-09-02 to 09-06 this session
believed it, told the user and another session four times that there was no
channel, and did the Windows work by relay instead. The config file's own
header says "macOS -> Windows ... this machine is the one dialling out". Two
documents describing one thing, contradicting each other, with nothing to
notice.

**When two texts disagree about a system, believe the one the machine reads.**
A config is executed; a flow document is not. That is not a rule about
documents being unreliable -- it is that one of these two is load-bearing and
the other is a description, and only the description can drift without anything
breaking.

**怎麼連上另外兩個節點，因為不寫下來，代價是好幾天。** 撥接的是 Mac。
`~/.multissh/generated/config2Win` 連 Windows（埠 16888），`config2WSL` 連 WSL2（埠 16889），
兩者的使用者都是 `lowei`，而那台機器對 `Ralic-W11.local` 與檔案裡那個 IPv6 link-local 位址都會回應
（用法見上方指令）。

**multissh 專案裡的 `multissh_upgrade_flow.md` 說的是相反的事**——說 Windows 才是撥接的那一端
——而 2026-09-02 到 09-06 之間，這個 session 相信了它，四次告訴使用者與另一個 session「沒有管道」，
並改用轉述的方式處理 Windows 的工作。那個設定檔自己的檔頭寫著「macOS → Windows……對外撥接的是
本機」。**兩份文字描述同一件事、互相矛盾，而沒有任何東西會發現。**

**當兩份文字對一個系統的說法不一致時，相信機器會讀的那一份。** 設定檔會被執行，流程文件不會。
這不是一條「文件不可靠」的規則——而是這兩者之中有一份是承重的、另一份是描述，**而只有描述可以
在不弄壞任何東西的情況下漂走**。

**Each node gets there by `git pull` where it can.** That is what makes a
node's numbers mean something: they name a commit anyone can fetch and re-run.

**Uncommitted code goes by multiscp -- and that is a different kind of
result.** The binary is at `~/proj/multissh/release/multiscp` and is NOT on
PATH, so give the full path. **The destination on the receiving node is under
its own `~/proj`** -- not the tree the node normally builds from. Copying into
the working tree replaces files the node may be mid-edit on, and it destroys
the one thing that makes the copy recoverable: the ability to compare what
arrived against what that node already had. But numbers from code that was
copied rather than pulled belong to a state with no commit id: nobody can reproduce them later,
including you. So say which files were sent, and RE-RUN the node after the
commit exists. A green four-node run on uncommitted code is not a green
four-node run on the commit that follows it -- this tree's whole subject is
results that look like something they are not.

**Build with `./compile_csv2.zsh` on every node, including Windows.** Do not
invoke `compile_csv2_win.bat` yourself. The dispatcher's Windows branch already
carries `MSYS2_ARG_CONV_EXCL='*'` (without it MSYS eats `/c` and the batch file
NEVER RUNS, at exit status 0, with the binary unchanged) and the `.\` prefix
(cmd does not search the working directory). KY happened because this session
told a node to run the batch file directly, stepping around a dispatcher that
already knew both.

**Push before asking anyone to pull.** A node cannot test a commit it cannot
fetch, and "please test HEAD" is meaningless if HEAD is local.

**Ask for three numbers AND the SKIP list.** Not "did it pass". A matching
total can be produced by two errors that cancel -- section 11 says this about
kernel upgrades and it is equally true of a code change. On 2026-09-03 an
expected-skip count was one too HIGH from a stale entry and one too LOW from a
new case added the same day; left alone they would have cancelled and the check
would have passed carrying both.

**Confirm the binary is new before believing any number.** The suite's STALE
BINARY gate only speaks if someone runs the suite; a node that compared the
binary's fingerprint before and after caught a build that never ran, which the
gate never saw because no tests followed it.

**A node you cannot reach leaves the state UNKNOWN, not passing.** Say so in
the words: "three green, one unknown". Put it in the commit message, because
the person reading that commit in six months will not remember which node was
missing. Do not let an unreachable node quietly become an assumed one.

**Do not couple unrelated work to convergence.** This session deferred a guest
image rebuild until "the four nodes align", and the two had nothing to do with
each other -- rebuilding an aarch64 rootfs tells you nothing about a Windows
build. The only real precondition was "no run of mine is in flight".

**When a node reports a failure you cannot reproduce, ask for the exact text
BEFORE theorising.** Two round-trips went into `strerror_s` on the theory that
it was the deprecated call. The node's one sentence -- "it compiled without
complaint; the error is on the next line" -- ended it, and the real fix was a
function that already existed seventy lines away in the same file. A guess
costs a round-trip; the exact text costs a line.

**The parent's gitlink is last, and it must separate what was verified from
what was quoted.** See section 12.

### 11b. 四個節點實際上怎麼升級

第 11 節說的是為什麼。這裡是順序，而它的每一行都在 2026-09-02..05 付過代價。

**順序是 Mac → Linux VM → WSL2 → Windows，而那不是隨意排的。** 它是「回饋最便宜的先跑」：
Mac 是程式被寫出來的地方，一次失敗的代價是一次重建；guest 由這裡在本地驅動，代價是幾分鐘；
WSL2 與 Windows 在另一台機器上，每一輪往返的代價是一則訊息與別人的注意力。**一個活到第四個節點
的缺陷，已經被付了四次錢。** 而且每一步都會讓它後面的失效——Mac 上失敗會讓另外三個變得沒有意義，
那就沒有理由去花掉它們。

**每個節點盡可能以 `git pull` 抵達。** 那正是「一個節點的數字有意義」的原因：它指名一個任何人都
取得回來、也重跑得了的 commit。

**未提交的程式用 multiscp 送——而那是另一種結果。** 執行檔在
`~/proj/multissh/release/multiscp`，而且**不在 PATH 上**，要給完整路徑。**接收端的目標目錄放在
那個節點自己的 `~/proj` 底下**——不是那個節點平常拿來建置的那棵樹。複製進工作樹會覆蓋掉那個節點
可能正在編輯的檔案，而且會毀掉「讓這份複製可回溯」的唯一憑據：把送到的東西與那個節點原本就有的
東西比對的能力。但「用複製而不是拉取」得到的數字，屬於一個沒有 commit id 的狀態：**日後沒有人重現得了它，包括你自己。** 因此要說出送了
哪些檔案，並且在 commit 存在之後**重跑那個節點**。一次在未提交程式上的四節點綠燈，不是它之後那個
commit 的四節點綠燈——而「看起來像某個東西、其實不是」正是這棵樹整個主題。

**每個節點都用 `./compile_csv2.zsh` 建置，Windows 也是。** 不要自己去叫
`compile_csv2_win.bat`。dispatcher 的 Windows 分支已經帶著 `MSYS2_ARG_CONV_EXCL='*'`
（少了它，MSYS 會吃掉 `/c`，**批次檔根本不會執行**，退出碼 0，二進位檔一個位元組不變）與 `.\`
前綴（cmd 不搜尋工作目錄）。KY 的成因正是本 session 叫一個節點直接跑那個批次檔，繞過了一個
早就知道這兩件事的 dispatcher。

**先推送，再請人拉。** 一個節點測不了它取不到的 commit，而「請測 HEAD」在 HEAD 還在本地時
毫無意義。

**要三個數字，**以及** SKIP 清單。** 不是「過了沒」。一個相同的總數可以由兩個互相抵銷的錯誤
產生——第 11 節對核心升級講過這件事，對一次程式改動同樣成立。2026-09-03 有一個預期略過數因為
一筆過期項目而**多一**，又因為同一天新增的案例漏了計數而**少一**；放著不管它們會抵銷，那個檢查
會帶著兩個錯誤通過。

**在相信任何數字之前，先確認那個二進位是新的。** 測試的 STALE BINARY 守衛只有在有人跑測試時才
會說話；那次「從未執行的建置」是被一個「建置前後比對指紋」的節點當場抓到的，而那道守衛完全沒有
看到它，因為後面根本沒有測試。

**一個你連不上的節點，留下的狀態是「未知」，不是「通過」。** 要把那句話說出來：「三綠一未知」。
寫進 commit message，因為六個月後讀那個 commit 的人不會記得少的是哪一個節點。**不要讓一個連不上
的節點安靜地變成一個被假定沒問題的節點。**

**不要把不相干的工作綁在「收斂」上。** 本 session 曾把 guest image 的重建押後到「四節點對齊」，
而那兩件事毫無關係——重建一個 aarch64 rootfs 對一個 Windows 建置什麼也說不了。真正的前提只有
一個：「我這邊沒有進行中的執行」。

**當一個節點回報你重現不了的失敗時，先要原文，再想理論。** 為了 `strerror_s` 花掉兩輪往返，
理論是「那個被廢棄的呼叫」。那個節點一句話結束了它——「它一個字沒被抱怨，錯在下一行」——而真正
的修法是一個早就存在、在同一個檔案裡七十行外的函式。**一次猜測的代價是一輪往返，一段原文的代價
是一行。**

**母專案的 gitlink 放最後，而且必須把「驗過的」與「引述的」分開。** 見第 12 節。

### 12. Commit, push, then the parent's gitlink

In that order. A gitlink pointing at a commit that exists only locally names
something no clone can fetch.

依這個順序。一個指向「只存在於本機的 commit」的 gitlink，指的是任何 clone 都取不到的東西。

### 13. Then, and only then, the next round

一個回合修完、驗過、推送之後，才開下一個。

---

## What a good round looks like

Not "it found the most". Round 77 found one DOC WRONG and an empty category 4,
and it was the most valuable of the series: it had tried to falsify the
performance claims and failed, which is a result. Round 76 filed nothing under
TOOL BROKEN after ruling out four of its own candidates.

不是「找到最多的那個」。第 77 回合找到一項 DOC WRONG、第 4 類是空的，而它是這一系列裡最有價值的
一輪：它試著否證那些效能宣稱而**沒有成功**，那本身就是一個結果。第 76 回合在排除了自己四個候選
之後，第 4 類什麼也沒放。

A round that reports "it was all fine" without having tried to break anything is
worse than no round: it produces confidence without evidence.

一個「什麼都沒試著弄壞、就回報一切都好」的回合，比不跑更糟：它產生的是沒有證據的信心。

---

## What 100 rounds produced, and the one thing to keep

Rounds 1–100 ran between 2026-08-16 and 2026-09-08. The suite went from a few
hundred cases to 1345. The defect record in
[`todo/known-defects.md`](./todo/known-defects.md) runs from A to PZ.

**The single most useful number: in the last eleven rounds, category 4 — "the
TOOL is wrong" — was empty nine times.** That is not a sign the rounds stopped
being worth running. It is what a mature program looks like from outside: the
code is right and the page describing it is where the failures move to. Rounds
90 through 100 found one crash (OF/OG, round 95), one verb that reported success
while doing nothing (OP, round 97), one installer claiming a verification it had
not performed (OK, round 96), and one measurement harness publishing the wrong
code path (OW/OX, round 98). Everything else was documentation.

**And documentation defects are not the small ones.** OW would have made a
reader size a container at 64 MiB for a job that needs 177. PT would have put a
plausible wrong licence count into a real report. The tester in round 100 read a
2.8× speedup off a search that matched nothing, at exit 0.

### The one thing to keep, if only one thing is kept

**Rounds 97, 98 and 99 each introduced a defect that the NEXT round found.**

| Round | Fixed | Introduced | Found by |
|---|---|---|---|
| 97 | OU — the `#` refusal is not only "at the top" | it "fires wherever the line is", which over-claims: the predicate is ONE FIELD | round 100 (PG) |
| 98 | OY — ciphertext is base64, so an empty cell is not distinguishable | corrected the English paragraph only | round 99 (PH) |
| 99 | PI — the code set is not three | removed the stability promise from English only (PR); wrote the 141 claim without its precondition (PS) | round 100 |

Every one of those was written while the correct information was on screen, by
someone who had just spent an hour understanding it. **A correction is a change
like any other, and it is made at the moment of highest confidence — which is
exactly when nothing is checked.** The three shapes it took here:

1. **Over-claiming.** The old sentence was too narrow, so the new one was made
   broad, and the broad version is false. Fixing "at the top" to "wherever the
   line is" skipped over the actual predicate.
2. **Half the pair.** Two files say the same thing; one gets corrected. This
   happened twice in three rounds, and the second time a test written for the
   first occurrence could not see it, because it pinned an instance rather than
   the class.
3. **Dropping the precondition.** A claim observed on one input is written
   without the condition that made it true, so it is false on the input anyone
   would verify it on.

The countermeasure is not "be careful". It is: **after fixing a documentation
defect, run the two greps that catch shapes 2 and 3** — does the other file say
the same thing, and does the new sentence hold on the smallest input you can
build? Both take under a minute, and each of the four defects above would have
been caught by one of them.

## 一百個回合產出了什麼，以及只留一件事的話該留哪一件

第 1–100 回合跑在 2026-08-16 至 2026-09-08 之間。測試從數百個案例長到 1345 個，
[`todo/known-defects.md`](./todo/known-defects.md) 的缺陷編號從 A 排到 PZ。

**最有用的一個數字：最後十一個回合裡，第 4 類（「工具錯了」）有九次是空的。** 那不代表這些回合
不值得再跑。那是一個成熟的程式從外面看起來的樣子：程式是對的，於是失敗全都搬到描述它的那一頁去了。
第 90 到 100 回合找到一次當機（OF／OG，第 95 回合）、一個「回報成功卻什麼都沒做」的動詞（OP，
第 97 回合）、一個「宣稱做過一次它沒做的驗證」的安裝器（OK，第 96 回合），以及一份「發表了錯誤
程式路徑」的量測 harness（OW／OX，第 98 回合）。其餘全是文件。

**而文件缺陷不是小的那一種。** OW 會讓一個讀者為一件需要 177 MiB 的工作把容器開在 64 MiB；PT 會把
一個看起來合理的錯誤授權計數放進一份真實報表；第 100 回合的受測者從一次什麼都沒命中的搜尋上，讀出
了 2.8 倍的加速比，rc=0。

### 只留一件事的話，留這一件

**第 97、98、99 三個回合，每一個都帶進了一個「被下一個回合找到」的缺陷。**

| 回合 | 修好了 | 帶進了 | 被誰找到 |
|---|---|---|---|
| 97 | OU——`#` 的拒絕不只在「檔案開頭」 | 改成「不論在哪裡都會觸發」，那過度概括了：真正的述詞是「恰好一個欄位」 | 第 100 回合（PG） |
| 98 | OY——密文是 base64，所以空儲存格分辨不出來 | 只修了英文那一段 | 第 99 回合（PH） |
| 99 | PI——code 不只三個 | 只從英文版移除了「跨版本穩定」的承諾（PR）；把 141 那個宣稱寫成無條件的（PS） | 第 100 回合 |

那每一次，正確的資訊都**就在螢幕上**，而寫下它的人剛剛花了一小時去理解它。**一次更正與任何其他改動
沒有兩樣，而它發生在信心最高的那一刻——那也正好是什麼都沒有被檢查的時刻。** 它在這裡採取的三種形狀：

1. **過度概括。** 舊句子太窄，於是新句子被寫寬，而寬的那個版本是假的。把「在開頭」改成「不論在哪裡」，
   跳過了真正的述詞。
2. **只做了一半的那一對。** 兩份檔案說同一件事，只有一份被更正。這在三個回合裡發生了兩次，而第二次
   時，為第一次寫下的測試看不到它——因為它釘住的是一個**實例**，不是那個**類別**。
3. **拿掉前提。** 一個在某種輸入上觀察到的宣稱，被寫成沒有那個「讓它為真的條件」，於是它在
   「任何人會拿來驗證它的那種輸入」上是假的。

對策不是「小心一點」。是：**修完一個文件缺陷之後，跑兩次 grep 去接住第 2、3 種形狀**——另一份檔案有
沒有說同一件事，以及這個新句子在你做得出來的**最小**輸入上還成不成立。兩件都不到一分鐘，而上面那
四個缺陷，每一個都會被其中之一接住。
