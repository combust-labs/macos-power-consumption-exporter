# Proposal: Extract All Maintainer User Prompts from Pi Session JSON

## Background
The Pi session export (`pi‑session‑<timestamp>.html`) contains a `<script id="session-data" type="application/json">` element with a Base64‑encoded JSON payload. After decoding, the JSON has the following shape:

```json
{
  "header": { … },
  "entries": [
    { "type": "message", "message": { "role": "user", "content": [{"type":"text","text":"…"}] } },
    { "type": "message", "message": { "role": "assistant", … } },
    …
  ]
}
```

Each maintainer prompt is stored as a **message** entry where `message.role` equals `"user"`. The actual prompt text lives in the `message.content` array as objects with `"type":"text"`.

## Goal
Provide a reliable, reproducible method to extract **all** user prompts (maintainer inputs) from the decoded session JSON, preserving their original order.

## Proposed Solution
Four complementary ways are offered:

1. **Human‑driven file selection & Base64 extraction** – the agent first asks the operator which Pi‑session HTML file should be processed. The operator supplies the full path (e.g. `~/Downloads/pi‑session‑2026‑03‑15T22‑51‑42‑220Z_22f50581-3755-4f79-a834-7adf84d98f4c.html`). The agent then runs:
   ```bash
   # Extract the Base64 payload from the <script> tag
   perl -0777 -ne 'if (/<script id="session-data"[^>]*>(.*?)<\/script>/s) { print $1 }' "$SELECTED_FILE" > /tmp/session_base64.txt

   # Decode it to plain JSON
   base64 -d /tmp/session_base64.txt > /tmp/session_base64-decoded.txt
   ```
   After these commands the JSON payload is available at **`/tmp/session_base64-decoded.txt`** and all subsequent steps work on that file.
2. **`jq` one‑liner** – the preferred, concise solution using the JSON query tool.
3. **Python script** – for environments where `jq` is unavailable but Python is present.
4. **Pure Bash/grep** – a fallback when neither `jq` nor Python can be installed.
### 2. `jq` One‑Liner
```bash
jq -r '
  .entries[]
  | select(.type == "message" and .message.role == "user")
  | .message.content[]
  | select(.type == "text")
  | .text
' /tmp/session_base64-decoded.txt
```
*Explanation*
- Iterate over all entries.
- Keep only `type == "message"` with `role == "user"`.
- Walk through the `content` array, selecting the `text` objects.
- Output the raw prompt strings (`-r`).

### 3. Python Script (`extract_user_prompts.py`)
```python
#!/usr/bin/env python3
import json, sys
with open("/tmp/session_base64-decoded.txt") as f:
    data = json.load(f)
for entry in data.get("entries", []):
    if entry.get("type") == "message" and entry.get("message", {}).get("role") == "user":
        for part in entry["message"].get("content", []):
            if part.get("type") == "text":
                print(part["text"])
```
Run with `python3 extract_user_prompts.py`.

### 4. Bash/grep Fallback
```bash
grep -Poz '"role"\s*:\s*"user".*?\K"text"\s*:\s*"\K[^"]+(?=")' \
    /tmp/session_base64-decoded.txt | tr -d '\0'
```
*Limitations*: May fail on escaped quotes inside the text; use only as a last resort.

## Benefits
- **Accuracy**: By parsing the JSON structure (`jq`/Python), we avoid false positives that string‑search approaches can cause.
- **Portability**: All three options run on typical developer machines (macOS/Linux). `jq` is lightweight; Python is ubiquitous.
- **Maintainability**: The logic is explicit and easy to adapt if the session schema evolves.

## Acceptance Criteria
- The command/script outputs **every** user prompt, one per line, in chronological order.
- No prompts are missed or duplicated.
- The solution works on the current repository checkout (the session file is located at `/tmp/session_base64-decoded.txt`).
- Documentation added to the repository (this proposal) and a README entry under `docs/` (optional).

## Implementation Plan
1. Add the proposal file (this one) to `.proposals/`.
2. Create a small helper script `scripts/extract_user_prompts.sh` that wraps the `jq` command for convenience.
3. Update the project `README.md` with a usage example.
4. Verify on the existing session file and on a newly generated one.
5. Merge the changes after review.

---
*Prepared by the AI assistant on 2026‑03‑16.*
