import json
import re
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parent
CONFIG = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
STATE_PATH = ROOT / "data/state.json"
QUARANTINE_PATH = ROOT / "data/quarantine.json"
UA = "OldFrag-AntiCheat-Curator/1.0 (+https://github.com/DmitriySivko/oldfrag-anticheat)"


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def parse_report(html: str, report_id: int):
    soup = BeautifulSoup(html, "html.parser")
    text = clean(soup.get_text(" ", strip=True))
    if not any(x in text for x in CONFIG["allowed_build_markers"]):
        return None
    if any(x in text for x in CONFIG["rejected_build_markers"]):
        return None
    result = next((x for x in CONFIG["accepted_results"] if x in text), None)
    if not result:
        return None

    heading = soup.find(lambda tag: tag.name in {"h1", "h2"} and "Найденные читы" in tag.get_text())
    labels = []
    if heading:
        table = heading.find_next("table")
        if table:
            for row in table.select("tbody tr"):
                cells = [clean(x.get_text(" ", strip=True)) for x in row.select("td")]
                if len(cells) >= 2 and cells[1]:
                    labels.append(cells[1])
    return {"report_id": report_id, "result": result, "labels": sorted(set(labels))}


def main():
    state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    quarantine = json.loads(QUARANTINE_PATH.read_text(encoding="utf-8"))
    session = requests.Session()
    session.headers["User-Agent"] = UA
    current = int(state["last_report_id"]) + 1
    misses = 0

    for report_id in range(current, current + int(CONFIG["max_reports_per_run"])):
        response = session.get(CONFIG["source"].format(report_id=report_id), timeout=20)
        if response.status_code == 404:
            misses += 1
            if misses >= 10:
                break
            continue
        response.raise_for_status()
        misses = 0
        report = parse_report(response.text, report_id)
        if report:
            for label in report["labels"]:
                item = quarantine.setdefault(label, {"count": 0, "report_ids": [], "results": {}})
                item["count"] += 1
                item["report_ids"] = (item["report_ids"] + [report_id])[-50:]
                item["results"][report["result"]] = item["results"].get(report["result"], 0) + 1
        state["last_report_id"] = report_id
        time.sleep(float(CONFIG["request_delay_seconds"]))

    QUARANTINE_PATH.write_text(json.dumps(quarantine, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

