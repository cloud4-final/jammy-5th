#!/usr/bin/env python3
"""Route 53 장애 전환 측정: 5초마다 DNS 답(직접/8.8.8.8)과 헬스체크 상태를 기록한다."""
import csv
import json
import subprocess
import sys
import time
from datetime import datetime

NAME = sys.argv[1] if len(sys.argv) > 1 else "jammy.cloud"
RESOLVERS = {"r53": "ns-247.awsdns-30.com", "google": "8.8.8.8"}
INTERVAL = 5
ENDPOINT_TYPES = {"HTTP", "HTTPS", "HTTP_STR_MATCH", "HTTPS_STR_MATCH", "TCP"}
OUTFILE = f"failover_{datetime.now():%m%d_%H%M%S}.csv"


def run(cmd, timeout=3):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:  # 지연되면 실패로 보고 다음 주기 진행
        return None
    return r.stdout if r.returncode == 0 else None


def dig(server):
    r = subprocess.run(["dig", "+short", "+time=2", "+tries=1", NAME, f"@{server}"],
                       capture_output=True, text=True)
    if r.returncode != 0:  # 시간 초과 등은 오류 문구 대신 표시만
        return "timeout"
    return " ".join(sorted(r.stdout.split())) or "-"


def health_checks():
    out = run(["aws", "route53", "list-health-checks", "--output", "json"], timeout=15)
    if out is None:
        sys.exit("헬스체크 목록 조회 실패: aws 자격 증명 확인")
    checks = {}
    for h in json.loads(out)["HealthChecks"]:
        cfg = h["HealthCheckConfig"]
        if cfg.get("Type") not in ENDPOINT_TYPES:  # 계산형·CloudWatch형은 엔드포인트 측정 대상 아님
            continue
        # FQDN 기반 헬스체크는 IPAddress가 없음
        checks[h["Id"]] = cfg.get("IPAddress") or cfg.get("FullyQualifiedDomainName") or h["Id"]
    return checks


def hc_status(hc_id):
    # 헬스체커(전 세계 여러 대) 중 성공 응답 수 / 전체
    out = run(["aws", "route53", "get-health-check-status",
               "--health-check-id", hc_id, "--output", "json"])
    if out is None:  # 일시 실패는 표시만 하고 측정 계속
        return "err"
    try:
        obs = json.loads(out)["HealthCheckObservations"]
    except (json.JSONDecodeError, KeyError):  # 응답 형식이 이상해도 표시만
        return "err"
    ok = sum(o["StatusReport"]["Status"].startswith("Success") for o in obs)
    return f"{ok}/{len(obs)}"


def main():
    checks = health_checks()
    header = ["time", "elapsed_s", "r53", "google"] + [f"hc_{ip}" for ip in checks.values()]
    start = time.time()
    with open(OUTFILE, "x", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        print(" | ".join(header))
        while True:
            t0 = time.time()
            row = [datetime.now().strftime("%H:%M:%S"), int(t0 - start),
                   dig(RESOLVERS["r53"]), dig(RESOLVERS["google"])]
            row += [hc_status(i) for i in checks]
            w.writerow(row)
            f.flush()
            print(" | ".join(map(str, row)))
            time.sleep(max(0, INTERVAL - (time.time() - t0)))  # 주기 유지


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n저장: {OUTFILE}")
