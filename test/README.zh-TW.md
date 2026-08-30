# csv2 回歸測試

測試套件涵蓋解析、選取、輸出格式、編輯、保護、索引、平行搜尋、診斷，以及
平台特定行為。

```zsh
./test_csv2.zsh
CSV2=/path/to/csv2 ./test_csv2.zsh
```

未指定二進位檔時，腳本會先建置 `release/csv2`。結果會寫到終端機與旁邊的
`test_csv2.log`。任何案例失敗時以非零結束；略過的案例會附上原因。

測試以 `T<n>` 編號，並依功能分組。母專案 runner 會在 aarch64 Linux guest
執行套件，並完成無法在單一平台內完成的 host／guest 逐位元一致性比較。

大部分 fixture 都由腳本產生，確保 BOM、CR、無效 UTF-8、缺少結尾換行與引號內
逗號等精確位元組不會被編輯器正規化。已提交的 `fixtures/TARGET_PACKAGES.csv`
用於較接近實際資料的引號欄位案例。

環境變數會降低門檻，讓小型 fixture 也能測試大型檔案行為：

| 變數 | 用途 |
|---|---|
| `CSV2_INDEX_MIN_BYTES` | 索引建立與追加測試 |
| `CSV2_PARALLEL_MIN_BYTES` | 平行／單執行緒比較 |
| `CSV2_PARALLEL_CHUNK_BYTES` | 產生多個搜尋區塊 |
| `CSV2_PRETTY_MAX_BYTES` | 限制 Markdown 算繪大小 |
| `CSV2_MD_MAX_BYTES` | 限制 Markdown 輸入大小 |
| `CSV2_MAX_BUFFER_RECORDS` | 限制 tail／上下文緩衝大小 |

新增案例時，先加入 `../plan/plan.md`，再以相同編號實作；只有在支援的平台上
通過後，才將它標記為完成。
