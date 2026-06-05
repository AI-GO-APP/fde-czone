# agent ↔ aigo 契約

## weigh 請求（agent 用 API Key 呼叫）
| 欄位 | 必填 | 說明 |
|---|---|---|
| image | 是 | base64 或 URL；含車牌、盡量含磅數顯示器 |
| weight | 否 | OCR 失敗/未啟用時的人工讀數（公噸） |
| weigh_operator | 是 | 過磅人員 |
| manual_plate | 否 | 辨識失敗時人工指定車牌 |

## weigh 回應
| 欄位 | 說明 |
|---|---|
| ticket_no | 單號 YYYYMMDD-NNN |
| event | first(一磅) / second(二磅) |
| plate / customer_id / gross_weight / tare_weight / net_weight | 過磅結果 |
| print_payload | 見下 |
| needs_manual | 需人工補的欄位清單，如 ["customer"]、["material"] |

## 列印 payload（對齊 Fast Report SR_ 欄位）
company, SR_Sn(單號), SR_Tn(車號), SR_Date, SR_User(人員),
SR_Direction(進/出), SR_Material(料種), SR_GwTon(毛重), SR_TwTon(空重), SR_NwTon(淨重)
