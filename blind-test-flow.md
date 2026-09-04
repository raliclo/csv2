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
