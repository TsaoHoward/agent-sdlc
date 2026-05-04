# 使用說明（繁體中文）

## 文件資訊
- 版本: 0.1
- 狀態: Active
- 最後更新: 2026-04-29
- 維護者: Project Maintainer

## 這份文件是做什麼的
這是一份給人直接看的簡明操作說明。

如果你不想先讀完整的 `docs/user-capability-matrix.md`，可以先看這份，快速理解：
- 這個專案現在能做什麼
- 目前誰適合使用
- 最短怎麼啟動
- 怎麼送出一個 `@agent` 請求
- 要去哪裡看成功或失敗
- 目前有哪些限制

## 先講結論
目前這個專案不是正式對外服務。

它現在最適合的定位是：
- `Workbench`
- 帶有第一批 `Internal Eval` 證據

也就是說，它已經能跑出真的 task、session、PR、CI、traceability，但目前主要用途還是：
- 平台維護者驗證流程
- 維護者觀察 AI 在受限條件下的表現
- 用外部 target repo 做內部評估

不建議現在把它當成廣泛開放的正式 AI coding 服務。

## 目前能做什麼
目前只有一條 live 入口：

`Gitea issue comment -> @agent run <token>`

支援的 token：
- `@agent run docs`
- `@agent run code`
- `@agent run review`
- `@agent run ci`

目前已經可以接上的流程：
1. 使用者在 Gitea issue comment 留下 `@agent` 指令
2. 系統建立 task request
3. 系統啟動 agent session
4. agent 在隔離 workspace 內產生修改
5. 系統建立 branch / PR
6. CI 獨立驗證
7. traceability 回寫到 PR 與本機狀態
8. 人工決定是否接受與合併

## 誰適合用
目前最適合的使用者不是一般終端使用者，而是：
- 專案維護者
- 平台操作員
- 想手動驗證 P1 流程的人

如果你的目的是：
- 驗證流程有沒有跑通
- 看 AI 改了哪些檔案
- 看 PR/CI/traceability 是否完整
- 比較 docs 任務和 code 任務的穩定度

那這套現在就有價值。

## 快速開始
在 repo 根目錄執行：

```powershell
npm install
npm run dev:env:up
npm run dev:gitea-runner -- ensure-runner
npm run dev:env:status
```

看到的重點應該是：
- Gitea 已啟動
- task gateway webhook listener 已啟動
- review webhook listener 已啟動
- runner online

如果你剛改過這個 repo 的 tracked 檔案，而且想拿 `howard/agent-sdlc` 當 live 測試目標，先補這一步：

```powershell
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
```

原因是目前本機 Gitea 的 `main` 必須和你正在測的 workspace `HEAD` 對齊；不然系統會在 proposal 建立前 fail-closed。

Gitea 預設網址：
- `http://localhost:43000/`

預設帳號：
- `howard / agent-dev-password`

## 最短操作方式
1. 打開 `http://localhost:43000/`
2. 進入 repo `howard/agent-sdlc`
3. 建立一個 issue
4. 在 issue comment 貼上：

```text
@agent run code
summary: Add a very small bounded change and keep behavior unchanged.
```

如果你要先跑比較穩的 docs 路徑，建議改用：

```text
@agent run docs
summary: Add a short note to README.md and one matching docs update.
```

## 送指令時要注意什麼
- `docs` 路徑目前比 `code` 穩
- `code` 路徑一定要把需求寫得短、窄、清楚
- `summary:` 不是越長越好
- bounded-code 路徑目前有明確 intake 邊界，`summary:` 太長會直接 fail-closed
- 如果你用的是本機 seeded `howard/agent-sdlc`，在測試前要注意 forge `main` 有沒有 reseed 到最新 workspace `HEAD`

目前手動驗證中已觀察到：
- `docs` external target 可以穩定通過
- `code` external target 第一次曾因 `summary:` 超過 280 字而直接被拒絕，不會建立 task
- 把描述縮短後，同一條 `code` 路徑可以成功完成 PR 與 CI

## 成功後會看到什麼
成功時，通常可以在這幾個地方看到證據：

- `.agent-sdlc/state/task-requests/`
  會有新的 task request
- `.agent-sdlc/state/agent-sessions/`
  會有新的 session
- `.agent-sdlc/traceability/`
  會有對應的 traceability 記錄
- Gitea PR 頁面
  會看到 agent 建立的 PR
- Gitea Actions 頁面
  會看到 CI run

最後希望看到的狀態通常是：
- `ci_status: success`
- `review.status: ready-for-human-review`
- `proposal_body_sync_status: synced`

## 失敗時現在會看到什麼
如果請求沒有成功走完整條 live 流程，現在不應該只剩下「看起來沒反應」。

目前至少有幾種可見回報：
- intake 格式不符合時，issue thread 會收到 `agent-admin` 的說明 comment
- 如果 proposal 建立前被 stale-forge preflight 擋下，issue thread 會收到原因和 reseed 指令
- 如果 agent 執行完後判定不需要改任何 repo 檔案，系統會停止在建 PR 之前，並在 issue thread 回報這次是 no-op

常見修復指令：

```powershell
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
```

## 怎麼判斷目前比較建議跑哪條
如果你是第一次確認功能，建議順序是：

1. 先跑平台流程確認
2. 再跑 `docs`
3. 最後跑 `code`

原因很簡單：
- `docs` 比較適合先確認外部 target repo 路徑真的通
- `code` 雖然可用，但目前比較敏感，更依賴 prompt discipline

## 如果你要逐步手動驗證
直接看這兩份：
- `docs/phase1-deliverable.md`
- `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md`

`TC-008` 會把目前 P1 建議驗證順序串起來。

## 目前限制
- 只有 Gitea issue comment 是 live `@agent` 入口
- 還不支援 label、PR comment、PR review comment 當 intake
- 目前還不是 `Pilot`
- 目前還不是 `Production`
- `code` 任務還需要更嚴格的人工作 diff review
- 外部 target repo 的證據目前只有第一批 fixture family，不代表已經能泛化到各種專案

## 你應該看哪份文件
- 想快速上手：看這份
- 想看目前能力邊界：看 `docs/user-capability-matrix.md`
- 想看 P1 交付定義：看 `docs/phase1-deliverable.md`
- 想一步一步手動驗證：看 `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md`
- 想看完整測試流程：看 `docs/testing/README.md`

## 變更紀錄
- 2026-04-29: 初版，提供較精簡、直接的繁體中文操作說明。
- 2026-04-29: 補上 seeded local forge reseed 前置條件，並說明 fail-closed / no-op 時的 issue-thread 可見回報。
