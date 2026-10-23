#!/usr/bin/env python3
"""The GitHub data the notch panel draws, as one line of JSON.

A single call to the GraphQL API brings all three things: the contribution grid
for the last year, the total, and the latest commits from the most recently
touched repos. The streak is counted here because the API does not provide it.

Authentication is handled by `gh`, which is already logged in on the machine.
No token is touched here: the binary is invoked and it takes care of it.

It ALWAYS prints something. If the network fails or gh is missing, it emits the
last good response from ~/.cache/quickshell/github.json with "stale": true, so
the panel shows yesterday's data in grey instead of going blank. Only if there
is no cache either does it print an object with "error".

The cadence is NOT here: there is no loop and no sleep. A QML Timer calls it,
which is the house rule -- a bash loop outlives quickshell if it dies
suddenly, gets adopted by systemd and keeps running forever.
"""

import json
import os
import subprocess
import sys
from datetime import date, datetime, timedelta

CACHE_DIR = os.path.expanduser("~/.cache/quickshell")
CACHE = os.path.join(CACHE_DIR, "github.json")

# The five levels the API returns. They are translated to 0..4 here and not in
# QML so the panel receives numbers and not strings it would have to map.
NIVELES = {
    "NONE": 0,
    "FIRST_QUARTILE": 1,
    "SECOND_QUARTILE": 2,
    "THIRD_QUARTILE": 3,
    "FOURTH_QUARTILE": 4,
}

CONSULTA = """
{
  viewer {
    login
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks {
          contributionDays { date contributionCount contributionLevel }
        }
      }
    }
    repositories(first: 8, orderBy: {field: PUSHED_AT, direction: DESC},
                 ownerAffiliations: OWNER, isFork: false) {
      nodes {
        name
        isPrivate
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: 5) {
                nodes { messageHeadline committedDate }
              }
            }
          }
        }
      }
    }
  }
}
"""


def racha(dias):
    """Consecutive days with at least one contribution, counting backwards.

    It starts from yesterday and not today on purpose: at nine in the morning
    you have not done anything yet, and a 40-day streak should not show up as
    broken just because the day has only just started. If today already has
    something, it counts too.
    """
    por_fecha = {d["date"]: d["contributionCount"] for d in dias}
    hoy = date.today()
    n = 0
    if por_fecha.get(hoy.isoformat(), 0) > 0:
        n = 1
    cursor = hoy - timedelta(days=1)
    while por_fecha.get(cursor.isoformat(), 0) > 0:
        n += 1
        cursor -= timedelta(days=1)
    return n


def consultar():
    salida = subprocess.run(
        ["gh", "api", "graphql", "-f", "query=" + CONSULTA],
        capture_output=True, text=True, timeout=20,
    )
    if salida.returncode != 0:
        raise RuntimeError((salida.stderr or "gh fallo").strip().split("\n")[0])
    return json.loads(salida.stdout)["data"]["viewer"]


def construir(v):
    cal = v["contributionsCollection"]["contributionCalendar"]

    # The grid goes as a list of weeks of 7 numbers, in the same order GitHub
    # shows it: each week is a COLUMN and starts on Sunday. The API already
    # sends every week complete except the last, which is cut off at today;
    # those days are padded with -1 and not 0, because -1 means "has not
    # happened yet" and the panel leaves it empty, whereas a 0 would paint a
    # "you did nothing" square in the future.
    #
    # `cuentas` runs in parallel with the real numbers: the levels are for the
    # colour and the counts for what the panel says when you hover over it.
    semanas, cuentas, dias = [], [], []
    for w in cal["weeks"]:
        dd = w["contributionDays"]
        fila = [NIVELES.get(d["contributionLevel"], 0) for d in dd]
        nums = [d["contributionCount"] for d in dd]
        fila += [-1] * (7 - len(fila))
        nums += [-1] * (7 - len(nums))
        semanas.append(fila[:7])
        cuentas.append(nums[:7])
        dias.extend(dd)

    # The Sunday the grid starts on. With this the panel works out the date of
    # any square by adding days, without having to be sent 371 dates.
    inicio = cal["weeks"][0]["contributionDays"][0]["date"] if cal["weeks"] else ""

    hoy = date.today().isoformat()
    commits = []
    for repo in v["repositories"]["nodes"]:
        rama = repo.get("defaultBranchRef") or {}
        objetivo = rama.get("target") or {}
        for c in (objetivo.get("history") or {}).get("nodes", []):
            commits.append({
                "repo": repo["name"],
                "priv": repo["isPrivate"],
                "msg": c["messageHeadline"],
                "when": c["committedDate"],
            })
    commits.sort(key=lambda c: c["when"], reverse=True)

    return {
        "login": v["login"],
        "total": cal["totalContributions"],
        "streak": racha(dias),
        "today": next((d["contributionCount"] for d in dias if d["date"] == hoy), 0),
        "weeks": semanas,
        "counts": cuentas,
        "start": inicio,
        "commits": commits[:6],
        "stale": False,
    }


def cache_vieja(motivo):
    try:
        with open(CACHE, encoding="utf-8") as f:
            datos = json.load(f)
        datos["stale"] = True
        datos["error"] = motivo
        return datos
    except (OSError, ValueError):
        return {"error": motivo, "stale": True, "weeks": [], "counts": [],
                "start": "", "commits": [], "total": 0, "streak": 0,
                "today": 0, "login": ""}


def main():
    try:
        datos = construir(consultar())
    except Exception as e:                      # network, gh not installed, token expired
        print(json.dumps(cache_vieja(str(e)[:120])))
        return 0

    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = CACHE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(datos, f)
        os.replace(tmp, CACHE)
    except OSError:
        pass                                    # without a cache it carries on the same

    print(json.dumps(datos))
    return 0


if __name__ == "__main__":
    sys.exit(main())
