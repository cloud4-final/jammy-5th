#!/usr/bin/env python3
"""Route 53 장애 전환 측정: 5초마다 DNS 답(직접/8.8.8.8)과 헬스체크 상태를 기록한다."""
import csv, json, subprocess, sys, time
from datetime import datetime

NAME = sys.argv[1] if len(sys.argv) > 1 else "jammy.cloud"
RESOLVERS = {"r53": "ns-247.awsdns-30.com", "google": "8.8.8.8"}
INTERVAL = 5
OUTFILE = f"failover_{datetime.now():%m%d_%H%M}.csv"

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def dig(server):
    ips = run(["dig", "+short", "+time=2", "+tries=1", NAME, f"@{server}"]).split()
    return " ".join(sorted(ips)) or "-"

def health_checks():
    data = json.loads(run(["aws", "route53", "list-health-checks", "--output", "json"]))
    return {h["Id"]: h["HealthCheckConfig"]["IPAddress"] for h in data["HealthChecks"]}

def hc_status(hc_id):
    # 헬스체커 중 성공 수 / 전체
    data = json.loads(run(["aws", "route53", "get-health-check-status",
                           "--health-check-id", hc_id, "--output", "json"]))
    obs = data["HealthCheckObservations"]
    ok = sum(o["StatusReport"]["Status"].startswith("Success") for o in obs)
    return f"{ok}/{len(obs)}"

def main():
    checks = health_checks()
    header = ["time", "elapsed_s", "r53", "google"] + [f"hc_{ip}" for ip in checks.values()]
    start = time.time()
    with open(OUTFILE, "w", newline="") as f:
        w = csv.writer(f); w.writerow(header); print(" | ".join(header))
        while True:
            t0 = time.time()
            row = [datetime.now().strftime("%H:%M:%S"), int(t0 - start),
                   dig(RESOLVERS["r53"]), dig(RESOLVERS["google"])]
            row += [hc_status(i) for i in checks]
            w.writerow(row); f.flush(); print(" | ".join(map(str, row)))
            time.sleep(max(0, INTERVAL - (time.time() - t0)))  # 주기 유지

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n저장: {OUTFILE}")
